const { DrinksPurchaseHistory, Vendor, DrinksInventory, DrinksCategory } = require('../../models');
const ExcelJS = require('exceljs');
const { Op } = require('sequelize');
const fs = require('fs');
const csv = require('csv-parser');
const multer = require('multer');
const { Sequelize } = require('sequelize');

// Multer config
const excelupload = multer({ dest: 'uploads/excel-uploads/drinks-inventory-purchases/' });

// Get all purchase history items
const getPurchaseHistory = async (req, res) => {
  try {
    const purchaseHistory = await DrinksPurchaseHistory.findAll({
      include: [
        {
          model: Vendor,
          as: 'vendor',
          attributes: ['name'],
        },
      ],
    });
    res.status(200).json(purchaseHistory);
  } catch (error) {
    console.error('Error fetching purchase history:', error);
    res.status(500).json({ message: 'Error fetching purchase history', error: error.message });
  }
};

// Get single item by ID
const getItemById = async (req, res) => {
  const item = await DrinksPurchaseHistory.findByPk(req.params.id);
  if (!item) return res.status(404).json({ message: 'Item not found' });
  res.json(item);
};


//Add New Purchase
const createPurchase = async (req, res) => {
  try {
    const { vendor_id, amount, date, notes, title } = req.body;

    const imagePath = req.files?.receipt_image?.[0]
      ? `/uploads/purchase_receipts/${req.files.receipt_image[0].filename}`
      : null;

    let parsedItems = [];

    // Parse JSON items if provided
    if (req.body.items && typeof req.body.items === 'string') {
      parsedItems = JSON.parse(req.body.items);
    } else if (Array.isArray(req.body.items)) {
      parsedItems = req.body.items;
    }

    // Parse Excel if uploaded
    const excelFile = req.files?.excel_file?.[0];
    if (excelFile) {
      const workbook = new ExcelJS.Workbook();
      await workbook.xlsx.readFile(excelFile.path);
      const worksheet = workbook.getWorksheet('Drinks Purchases') || workbook.worksheets[0];

      const inventories = await DrinksInventory.findAll({ raw: true });
      const nameToInventory = Object.fromEntries(
        inventories.filter(i => i.itemName).map(i => [i.itemName.trim(), i])
      );

      const categories = await DrinksCategory.findAll({ raw: true });
      const categoryMap = Object.fromEntries(
        categories.filter(c => c.categoryName).map(c => [c.categoryName.trim(), c.id])
      );

      for (let i = 2; i <= worksheet.rowCount; i++) {
        const row = worksheet.getRow(i);
        const itemName = row.getCell(1).value?.toString().trim();
        const qty = parseFloat(row.getCell(2).value);
        const unit = row.getCell(3).value?.toString().trim();
        const price = parseFloat(row.getCell(4).value) || 0;
        const bottleSize = row.getCell(5).value?.toString().trim();
        const categoryName = row.getCell(6).value?.toString().trim();

        if (!itemName || isNaN(qty) || !unit) continue;

        let categoryId = categoryMap[categoryName];
        if (!categoryId && categoryName) {
          const newCat = await DrinksCategory.create({ categoryName });
          categoryId = newCat.id;
          categoryMap[categoryName] = categoryId;
        }

        parsedItems.push({ itemName, qty, unit, price, bottleSize, categoryId });
      }

      fs.unlinkSync(excelFile.path);
    }

    if (!parsedItems.length) return res.status(400).json({ message: 'No purchase items provided.' });

    // ✅ Save drinks purchase with approved=false
    const newPurchase = await DrinksPurchaseHistory.create({
      vendor_id,
      amount,
      date,
      notes,
      receipt_image: imagePath,
      items: parsedItems,
      title,
      approved: false
    });

    return res.status(201).json({
      message: 'Drinks purchase created successfully and pending approval.',
      purchase: newPurchase,
    });
  } catch (error) {
    console.error('Error saving drinks purchase:', error);
    return res.status(500).json({ message: 'Error saving drinks purchase', error: error.message });
  }
};



const approvePurchase = async (req, res) => {
  const { id } = req.params;

  try {
    const purchase = await DrinksPurchaseHistory.findByPk(id);
    if (!purchase) return res.status(404).json({ message: 'Purchase not found' });
    if (purchase.approved) return res.status(400).json({ message: 'Purchase already approved' });

    const items = Array.isArray(purchase.items) ? purchase.items : JSON.parse(purchase.items);

    for (const item of items) {
      const { itemName, qty, unit, price, bottleSize, categoryId } = item;
      if (!itemName || !qty) continue;

      let inventoryItem = await DrinksInventory.findOne({ where: { itemName } });
      if (inventoryItem) {
        inventoryItem.quantity += parseFloat(qty);
        inventoryItem.price = price || inventoryItem.price;
        inventoryItem.bottleSize = bottleSize || inventoryItem.bottleSize;
        await inventoryItem.save();
      } else {
        await DrinksInventory.create({
          itemName,
          quantity: parseFloat(qty),
          unit,
          price: price || 0,
          bottleSize,
          categoryId: categoryId || null,
          minimumQuantity: 5,
          minimumQuantity_unit: unit,
        });
      }
    }

    purchase.approved = true;
    await purchase.save();

    return res.status(200).json({ message: 'Drinks purchase approved and inventory updated', purchase });
  } catch (error) {
    console.error('Error approving drinks purchase:', error);
    return res.status(500).json({ message: 'Server error', error: error.message });
  }
};


// Update existing purchase
const updateItem = async (req, res) => {
  try {
    const { id } = req.params;
    const { vendor_id, amount, date, notes, items } = req.body;
    const item = await DrinksPurchaseHistory.findByPk(id);

    if (!item) return res.status(404).json({ message: 'Item not found' });

    const parsedItems = typeof items === 'string' ? JSON.parse(items) : items;

    item.vendor_id = vendor_id ?? item.vendor_id;
    item.amount = amount ?? item.amount;
    item.date = date ?? item.date;
    item.notes = notes ?? item.notes;
    item.items = parsedItems ?? item.items;

    if (req.file) {
      item.receipt_image = `/uploads/receipts/${req.file.filename}`;
    }

    await item.save();
    res.status(200).json(item);
  } catch (error) {
    console.error('Error updating item:', error);
    res.status(500).json({ message: 'Error updating item', error: error.message });
  }
};

// Delete a purchase
const deleteItem = async (req, res) => {
  const item = await DrinksPurchaseHistory.findByPk(req.params.id);
  if (!item) return res.status(404).json({ message: 'Item not found' });
  await item.destroy();
  res.json({ message: 'Item deleted successfully' });
};

// Download as Excel
const downloadPurchaseHistory = async (req, res) => {
  try {
    const purchaseHistory = await DrinksPurchaseHistory.findAll({
      include: [
        {
          model: Vendor,
          as: 'vendor',
          attributes: ['name'],
        },
      ],
    });

    const workbook = new ExcelJS.Workbook();
    const worksheet = workbook.addWorksheet('PurchaseHistory');

    worksheet.columns = [
      { header: 'ID', key: 'id', width: 10 },
      { header: 'Purchase Date', key: 'date', width: 20 },
      { header: 'Vendor Name', key: 'vendorName', width: 25 },
      { header: 'Amount (₹)', key: 'amount', width: 15 },
      { header: 'Items', key: 'items', width: 60 },
      { header: 'Notes', key: 'notes', width: 30 },
    ];

    worksheet.getRow(1).font = { bold: true };
    worksheet.getColumn('items').alignment = { wrapText: true, vertical: 'top' };
    ['vendorName', 'amount', 'notes', 'date'].forEach((key) => {
      worksheet.getColumn(key).alignment = { vertical: 'top' };
    });

    purchaseHistory.forEach((entry) => {
      const data = entry.toJSON();
      const formattedItems = (data.items || [])
        .map(
          (item) =>
            `${item.menuItem} ×${item.quantity} — ₹${item.totalAmount} @ ₹${item.pricePerUnit}`
        )
        .join('\n');

      const formattedDate = new Date(data.date).toLocaleDateString('en-GB', {
        day: '2-digit',
        month: 'short',
        year: 'numeric',
      });

      worksheet.addRow({
        id: data.id,
        date: formattedDate,
        vendorName: data.vendor?.name || 'N/A',
        amount: data.amount,
        items: formattedItems,
        notes: data.notes || '',
      });
    });

    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.setHeader('Content-Disposition', 'attachment; filename=purchase_history.xlsx');

    await workbook.xlsx.write(res);
    res.status(200).end();
  } catch (error) {
    console.error('Error downloading purchase history:', error);
    res.status(500).json({ message: 'Error downloading purchase history', error: error.message });
  }
};

module.exports = {
  getPurchaseHistory,
  getItemById,
  createPurchase,
  updateItem,
  deleteItem,
  downloadPurchaseHistory,
  excelupload,
  approvePurchase,
};
