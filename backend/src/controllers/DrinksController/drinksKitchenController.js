const { DrinksInventory, DrinksKitchenInventory, DrinksTransferHistory, User } = require('../../models');
const ExcelJS = require('exceljs'); 

// ✅ Transfer items to kitchen inventory
const transferToKitchen = async (req, res) => {
  try {
    const { inventoryId, quantity, unit, userId } = req.body;

    // 👉 Find the item in main inventory
    const drinksInventory = await DrinksInventory.findByPk(inventoryId);

    if (!drinksInventory) {
      return res.status(404).json({ message: 'Inventory item not found' });
    }

    // 👉 Check if the unit matches the inventory unit
    if (drinksInventory.unit !== unit) {
      console.log(drinksInventory.unit, unit)
      return res.status(400).json({
        message: `Unit mismatch. Expected ${drinksInventory.unit}, but got ${unit}.`,
      });
    }

    // 👉 Check if sufficient quantity is available in the main inventory
    if (drinksInventory.quantity < quantity) {
      return res.status(400).json({
        message: 'Insufficient quantity in main drinksInventory',
      });
    }

    // 👉 Deduct from main inventory
    drinksInventory.quantity -= quantity;
    await drinksInventory.save();

    // 👉 Calculate totalQuantityRemaining (quantity * bottleSize)
    const totalQuantityRemaining = quantity * drinksInventory.bottleSize;

    // 👉 Check if the item already exists in kitchen inventory
    let drinksKitchenInventory = await DrinksKitchenInventory.findOne({
      where: { inventoryId },
    });

    if (drinksKitchenInventory) {
      drinksKitchenInventory.quantity += parseInt(quantity);
      drinksKitchenInventory.totalQuantityRemaining += totalQuantityRemaining;
      await drinksKitchenInventory.save();
    } else {
      await DrinksKitchenInventory.create({
        inventoryId,
        quantity,
        unit,
        bottleSize: drinksInventory.bottleSize,
        totalQuantityRemaining,
      });
    }

    // ✅ Create a transfer history record
    await DrinksTransferHistory.create({
      date: new Date(),                  // use current date
      itemName: drinksInventory.itemName, // use name from the inventory item
      quantity,
      unit,
      userId,                            // Use dynamic userId from request
      bottleSize: drinksInventory.bottleSize,
    });

    res.status(200).json({
      message: 'Items transferred to kitchen inventory successfully!',
    });

  } catch (error) {
    console.error('Error transferring to kitchen:', error);
    res.status(500).json({
      message: 'Error transferring items',
      error: error.message,
    });
  }
};


// ✅ Clear kitchen inventory (useful for resetting)
const clearKitchenInventory = async (req, res) => {
  try {
    // 👉 Destroy all records in DrinksKitchenInventory
    await DrinksKitchenInventory.destroy({ where: {} });

    res.status(200).json({ message: 'Kitchen inventory cleared successfully!' });
  } catch (error) {
    console.error('Error clearing kitchen inventory:', error);
    res.status(500).json({ message: 'Error clearing kitchen inventory', error: error.message });
  }
};

// ✅ Get kitchen inventory with associated inventory details
const getKitchenInventory = async (req, res) => {
  try {
    const drinksKitchenInventory = await DrinksKitchenInventory.findAll({
      include: {
        model: DrinksInventory,
        as: 'drinksInventory',
      },
    });

    const modifiedInventory = drinksKitchenInventory.map(item => {
      const quantity = item.quantity;
      const bottleSize = item.bottleSize;
      const totalMl = item.totalQuantityRemaining; // Use DB value directly

      // Calculate pegs (1 peg = 30 ml)
      const peg = Math.floor(totalMl / 30);

      // Format quantity string
      let quantityDisplay = '';

      if (quantity < 1 && quantity > 0) {
        quantityDisplay = `${Math.round(totalMl)} ml`;
      } else if (quantity % 1 !== 0) {
        const wholeBottles = Math.floor(quantity);
        const decimalPart = quantity - wholeBottles;
        const ml = decimalPart * bottleSize;
        quantityDisplay = `${wholeBottles} Bottle & ${Math.round(ml)} ml`;
      } else {
        quantityDisplay = `${quantity} Bottle`;
      }

      return {
        ...item.toJSON(),
        quantity: quantityDisplay,
        peg: peg,
      };
    });

    res.json(modifiedInventory);

  } catch (error) {
    console.error('Error fetching kitchen inventory:', error);
    res.status(500).json({
      message: 'Error fetching kitchen inventory',
      error: error.message,
    });
  }
};

// Download inventory as Excel
const downloadKitchenInventory = async (req, res) => {
  try {
    const kitchenInventory = await DrinksKitchenInventory.findAll({
      include: {
        model: DrinksInventory, // Make sure this is the correct model name
        as: 'inventory',
      },
    });

    const workbook = new ExcelJS.Workbook();
    const worksheet = workbook.addWorksheet('Kitchen Inventory');

    // 📝 Define columns
    worksheet.columns = [
      { header: 'ID', key: 'id', width: 10 },
      { header: 'Item Name', key: 'itemName', width: 25 },
      { header: 'Quantity', key: 'quantity', width: 15 },
      { header: 'Unit', key: 'unit', width: 15 },
    ];

    // ➕ Add rows
    kitchenInventory.forEach(item => {
      worksheet.addRow(item.toJSON());
    });

    // 📦 Set headers for download
    res.setHeader(
      'Content-Type',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    );
    res.setHeader(
      'Content-Disposition',
      'attachment; filename=Kitchen-Inventory.xlsx'
    );

    // 💾 Write workbook to response
    await workbook.xlsx.write(res);
    res.status(200).end();
  } catch (error) {
    console.error('Error downloading inventory:', error);
    res.status(500).json({ message: 'Error downloading kitchen inventory', error: error.message });
  }
};

// Get transfer history
const getTransferHistory = async (req, res) => {
  try {
    const history = await DrinksTransferHistory.findAll({
      include: [{ model: User, as: 'user', attributes: ['name'] }],
      order: [['date', 'DESC']],
    });
    
    res.json(history.map(item => ({
      item_name: item.itemName,
      quantity: item.quantity,
      unit: item.unit || '',
      username: item.user?.name || '',
      date: item.date ? item.date.toISOString().split('T')[0] : '',
    })));
  } catch (error) {
    console.error('Error fetching transfer history:', error);
    res.status(500).json({
      message: 'Error fetching transfer history',
      error: error.message,
    });
  }
};



const transferViaBarcode = async (req, res) => {
  try {
    const { barcode, userId } = req.body; // barcode = "42#3#kg"

    if (!barcode) {
      return res.status(400).json({ message: 'Barcode is required' });
    }

    const parts = barcode.split('#');
    if (parts.length < 3) {
      return res.status(400).json({ message: 'Invalid barcode format' });
    }
    console.log(parts);

    const inventoryId = parseInt(parts[0]);
    const quantity = parseFloat(parts[1]);
    const unit = parts[2];

    // Reuse your existing logic
    req.body = { inventoryId, quantity, unit, userId };
  
    return await transferToKitchen(req, res);

  } catch (error) {
    console.error('Error transferring via barcode:', error);
    res.status(500).json({
      message: 'Error transferring via barcode',
      error: error.message,
    });
  }
};


module.exports = {
  transferToKitchen,
  getKitchenInventory,
  clearKitchenInventory,
  downloadKitchenInventory,
  getTransferHistory,
  transferViaBarcode
};
