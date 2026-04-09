const { Inventory, KitchenInventory, TransferHistory, User } = require('../../models');
const ExcelJS = require('exceljs'); 

// ✅ Transfer items to kitchen inventory
const transferToKitchen = async (req, res) => {
  try {
    const { inventoryId, quantity, unit, userId } = req.body;
    console.log(req.body);
    // 👉 Find the item in main inventory
    const inventory = await Inventory.findByPk(inventoryId);

    if (!inventory) {
      return res.status(404).json({ message: 'Inventory item not found' });
    }

    // 👉 Log to see what we get from inventory
    console.log(`Inventory quantity: ${inventory.quantity}, Inventory unit: ${inventory.unit}`);
    console.log(`Requested quantity: ${quantity}, Requested unit: ${unit}`);

    // Normalize the units for comparison
    let normalizedQuantity = quantity;
    let normalizedInventoryQuantity = inventory.quantity;

    // Normalize the inventory quantity to grams or ml if it's in kg or liters
    if (inventory.unit === 'Kg' || inventory.unit === 'L') {
      normalizedInventoryQuantity = inventory.quantity * 1000;  // Convert kg/L to grams/ml
    }

    // Normalize the requested quantity to grams or ml if it's in kg or liters
    if (unit === 'Kg' || unit === 'L') {
      normalizedQuantity = quantity * 1000;  // Convert kg/L to grams/ml
    }

    // Log normalized quantities to ensure they are correct
    console.log(`Normalized inventory quantity: ${normalizedInventoryQuantity}`);
    console.log(`Normalized requested quantity: ${normalizedQuantity}`);

    // 👉 Check if sufficient quantity is available in the main inventory
    if (normalizedInventoryQuantity < normalizedQuantity) {
      return res.status(400).json({
        message: 'Insufficient quantity in main inventory',
      });
    }

    // 👉 Deduct from main inventory (based on unit)
    if (unit === 'Unit') {
      inventory.quantity -= normalizedQuantity;
    } else {
      inventory.quantity -= normalizedQuantity / 1000; // Convert back to kg/L for storage
    }

    // Ensure quantity doesn't go negative
    inventory.quantity = Math.max(inventory.quantity, 0);
    await inventory.save();

    // 👉 Check if the item already exists in kitchen inventory
    let kitchenInventory = await KitchenInventory.findOne({
      where: { inventoryId },
    });

    let totalQuantityRemaining;

    // Determine totalQuantityRemaining based on unit
    if (unit === 'Kg' || unit === 'Liters') {
      totalQuantityRemaining = parseInt(normalizedQuantity * 1000);  // 1 bag = 1000g/ml
    } else if (unit === 'Unit') {
      totalQuantityRemaining = parseInt(normalizedQuantity);  // Direct unit count
    } else {
      totalQuantityRemaining = 0;  // Fallback
    }

    if (kitchenInventory) {
      // If kitchenInventory exists, update it
      let kitchenQuantity = kitchenInventory.quantity;

      if (unit === 'Kg' || unit === 'L') {
        kitchenQuantity = kitchenQuantity * 1000 + normalizedQuantity;
        kitchenInventory.quantity = kitchenQuantity / 1000;
      } else if (unit === 'Unit') {
        kitchenInventory.quantity += normalizedQuantity;
      }

      if (!kitchenInventory.bagSize) {
        kitchenInventory.bagSize = 1000;
      }

      kitchenInventory.totalQuantityRemaining = kitchenInventory.quantity * kitchenInventory.bagSize;
      await kitchenInventory.save();
    } else {
      // If kitchenInventory doesn't exist, create a new record
      kitchenInventory = {
        inventoryId,
        quantity: unit === 'Unit' ? normalizedQuantity : normalizedQuantity / 1000,
        unit,
        bagSize: 1000,
        totalQuantityRemaining,
      };

      await KitchenInventory.create(kitchenInventory);
    }

    // ✅ Create a transfer history record
    await TransferHistory.create({
      date: new Date(),
      itemName: inventory.itemName,
      quantity,
      unit,
      userId,
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
    // 👉 Destroy all records in KitchenInventory
    await KitchenInventory.destroy({ where: {} });

    res.status(200).json({ message: 'Kitchen inventory cleared successfully!' });
  } catch (error) {
    console.error('Error clearing kitchen inventory:', error);
    res.status(500).json({ message: 'Error clearing kitchen inventory', error: error.message });
  }
};

// ✅ Get kitchen inventory with associated inventory details
const getKitchenInventory = async (req, res) => {
  try {
    const kitchenInventory = await KitchenInventory.findAll({
      include: {
        model: Inventory,
        as: 'inventory',
      },
    });
    res.json(kitchenInventory);
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
    const kitchenInventory = await KitchenInventory.findAll({
      include: {
        model: Inventory,
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



const getTransferHistory = async (req, res) => {
  try {
    const history = await TransferHistory.findAll({
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
    console.error('Error fetching kitchen inventory:', error);
    res.status(500).json({
      message: 'Error fetching kitchen inventory',
      error: error.message,
    });
  }
};

const addTransferHistory = async (req, res) => {
  try {
    const kitchenInventory = await KitchenInventory.findAll({
      include: {
        model: Inventory,
        as: 'inventory',
      },
    });
    res.json(kitchenInventory);
  } catch (error) {
    console.error('Error fetching kitchen inventory:', error);
    res.status(500).json({
      message: 'Error fetching kitchen inventory',
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
