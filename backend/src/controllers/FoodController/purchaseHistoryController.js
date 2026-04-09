const { PurchaseHistory, Vendor, Inventory, InventoryCategory, DrinksPurchaseHistory, DrinksInventory } = require('../../models');
const ExcelJS = require('exceljs');
const { Op } = require('sequelize');
const fs = require('fs');
const csv = require('csv-parser');
const multer = require('multer');
// const { Sequelize } = require('sequelize');
const { sequelize } = require("../../models");
// Multer config
const excelupload = multer({ dest: 'uploads/excel-uploads/inventory-purchases/' });
// Optimized Controller with Pagination Support

const getPurchaseHistory = async (req, res) => {
  try {
    // 🔹 Pagination setup
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 15;
    const offset = (page - 1) * limit;

    // 🔹 Filters
    const { startDate, endDate, vendorName, approved } = req.query;

    // Build date range filter (if provided)
    const dateFilter =
      startDate && endDate
        ? { createdAt: { [Op.between]: [new Date(startDate), new Date(endDate)] } }
        : {};

    // Build approval filter
    const approvalFilter =
      approved !== undefined ? { approved: approved === 'true' } : {};

    // Vendor filter
    const vendorFilter = vendorName
      ? {
          include: [
            {
              model: Vendor,
              as: 'vendor',
              attributes: ['name'],
              where: { name: { [Op.iLike]: `%${vendorName}%` } },
            },
          ],
        }
      : {
          include: [
            {
              model: Vendor,
              as: 'vendor',
              attributes: ['name'],
            },
          ],
        };

    // 🔹 Fetch both purchase sources in parallel
    const [foodHistory, drinkHistory] = await Promise.all([
      PurchaseHistory.findAll({
        ...vendorFilter,
        where: { ...dateFilter, ...approvalFilter },
        order: [['createdAt', 'DESC']],
      }),
      DrinksPurchaseHistory.findAll({
        ...vendorFilter,
        where: { ...dateFilter, ...approvalFilter },
        order: [['createdAt', 'DESC']],
      }),
    ]);

    // 🔹 Add "type" field to each record
    const foodWithType = foodHistory.map((item) => ({
      ...item.toJSON(),
      type: 'food',
    }));

    const drinksWithType = drinkHistory.map((item) => ({
      ...item.toJSON(),
      type: 'drinks',
    }));

    // 🔹 Combine and sort by date (descending)
    const combined = [...foodWithType, ...drinksWithType].sort(
      (a, b) => new Date(b.createdAt) - new Date(a.createdAt)
    );

    // 🔹 Paginate the combined list
    const totalItems = combined.length;
    const totalPages = Math.ceil(totalItems / limit);
    const paginatedData = combined.slice(offset, offset + limit);

    // 🔹 Send response
    res.status(200).json({
      currentPage: page,
      totalPages,
      totalItems,
      pageSize: limit,
      data: paginatedData,
    });
  } catch (error) {
    console.error('❌ Error fetching purchase history:', error);
    res.status(500).json({
      message: 'Error fetching purchase history',
      error: error.message,
    });
  }
};



// Get single item by ID
const getItemById = async (req, res) => {
  const item = await PurchaseHistory.findByPk(req.params.id);
  if (!item) return res.status(404).json({ message: 'Item not found' });
  res.json(item);
};



const createPurchase = async (req, res) => {
  try {
    const { vendor_id, amount, date, notes, title } = req.body;

    const imagePath = req.files?.receipt_image?.[0]
      ? `/uploads/purchase_receipts/${req.files.receipt_image[0].filename}`
      : null;

    let parsedItems = [];

    // Parse JSON items or Excel file
    if (req.body.items && typeof req.body.items === 'string') {
      parsedItems = JSON.parse(req.body.items);
    } else if (Array.isArray(req.body.items)) {
      parsedItems = req.body.items;
    }

    const excelFile = req.files?.excel_file?.[0];
    if (excelFile) {
      // Same Excel parsing logic as before
      const workbook = new ExcelJS.Workbook();
      await workbook.xlsx.readFile(excelFile.path);
      const worksheet = workbook.getWorksheet('Inventory Purchases') || workbook.worksheets[0];

      const inventories = await Inventory.findAll({ raw: true });
      const nameToInventory = Object.fromEntries(inventories.map(i => [i.itemName.trim(), i]));
      const categories = await InventoryCategory.findAll({ raw: true });
      const categoryMap = Object.fromEntries(categories.map(c => [c.categoryName.trim(), c.id]));

      for (let i = 2; i <= worksheet.rowCount; i++) {
        const row = worksheet.getRow(i);
        const itemName = row.getCell(1).value?.toString().trim();
        const qty = parseFloat(row.getCell(2).value);
        const unit = row.getCell(3).value?.toString().trim();
        const categoryName = row.getCell(4).value?.toString().trim();

        if (!itemName || isNaN(qty) || !unit) continue;

        let categoryId = categoryMap[categoryName];
        if (!categoryId && categoryName) {
          const newCat = await InventoryCategory.create({ categoryName });
          categoryId = newCat.id;
          categoryMap[categoryName] = categoryId;
        }

        parsedItems.push({ itemName, qty, unit, categoryId });
      }

      fs.unlinkSync(excelFile.path);
    }

    if (!parsedItems.length) {
      return res.status(400).json({ message: 'No purchase items provided.' });
    }

    // ✅ Save purchase with approved=false by default
    const newPurchase = await PurchaseHistory.create({
      vendor_id,
      amount,
      date,
      notes,
      receipt_image: imagePath,
      items: parsedItems,
      title,
      approved: false,
    });

    return res.status(201).json({
      message: 'Purchase created successfully and pending approval.',
      purchase: newPurchase,
    });
  } catch (error) {
    console.error('Error creating purchase:', error);
    return res.status(500).json({ message: 'Error saving purchase', error: error.message });
  }
};





// ✅ Mark a purchase as complete and update inventory by item ID
const approvePurchase = async (req, res) => {
  const { id } = req.params; // Purchase ID
  const { type } = req.body; // "food" or "drink"
  const t = await sequelize.transaction();

  try {
    if (!type) {
      await t.rollback();
      return res.status(400).json({ message: "Missing type (food or drink)" });
    }

    // ✅ Select model based on type
    const PurchaseModel = type === "drink" ? DrinksPurchaseHistory : PurchaseHistory;
    const InventoryModel = type === "drink" ? DrinksInventory : Inventory;

    // ✅ Find purchase record
    const purchase = await PurchaseModel.findByPk(id, { transaction: t });
    if (!purchase) {
      await t.rollback();
      return res.status(404).json({ message: `${type} purchase not found` });
    }

    if (purchase.approved) {
      await t.rollback();
      return res.status(400).json({ message: `${type} purchase already approved` });
    }

    // ✅ Safely parse items
    let items = [];
    try {
      items = Array.isArray(purchase.items)
        ? purchase.items
        : JSON.parse(purchase.items || "[]");
    } catch (err) {
      await t.rollback();
      return res.status(400).json({ message: "Invalid items format in purchase" });
    }

    // ✅ Update the appropriate inventory table
    for (const item of items) {
      const { id: itemId, name: itemName, qty, unit, categoryId } = item;
      if (!itemId || !qty) {
        console.warn(`⚠️ Skipping invalid item: ${JSON.stringify(item)}`);
        continue;
      }

      const quantityToAdd = parseFloat(qty) || 0;
      if (quantityToAdd <= 0) continue;

      let inventoryItem = await InventoryModel.findOne({
        where: { id: itemId },
        transaction: t,
      });

      if (inventoryItem) {
        // ✅ Update existing item
        inventoryItem.quantity = parseFloat(inventoryItem.quantity) + quantityToAdd;
        await inventoryItem.save({ transaction: t });
        console.log(`✅ Updated ${type} inventory for item ID ${itemId} (${itemName})`);
      } else {
        // ✅ Create new record with shared structure
        const newItemData = {
          id: itemId,
          itemName: itemName || `Item-${itemId}`,
          quantity: quantityToAdd,
          unit: unit || "Unit",
          categoryId: categoryId || null,
        };

        // For drinks, ensure required fields exist
        if (type === "drink") {
          newItemData.minimumQuantity = 0;
          newItemData.minimumQuantity_unit = unit || "Unit";
          newItemData.price = 0;
          newItemData.bottleSize = item.bottleSize || 750;
        }

        await InventoryModel.create(newItemData, { transaction: t });
        console.log(`🆕 Added new ${type} inventory item ID ${itemId} (${itemName})`);
      }
    }

    // ✅ Mark as approved
    purchase.approved = true;
    await purchase.save({ transaction: t });

    await t.commit();
    return res.status(200).json({
      message: `✅ ${type === "drinks" ? "Drinks" : "Food"} purchase approved and inventory updated successfully`,
      purchase,
    });
  } catch (error) {
    await t.rollback();
    console.error("❌ Error approving purchase:", error);
    return res.status(500).json({
      message: "Server error while approving purchase",
      error: error.message,
    });
  }
};


// ✅ Update an existing purchase (food or drinks)
const updateItem = async (req, res) => {
  try {
    const { id } = req.params;
    const {
      vendor_id,
      amount,
      date,
      notes,
      items,
      delivery_status,
      payment_status,
      payment_method,
      type='food', // ✅ "food" or "drink"
    } = req.body;

    

    // ✅ Choose model dynamically
    const PurchaseModel =
      type === "drink" ? DrinksPurchaseHistory : PurchaseHistory;

    // ✅ Find the purchase record
    const purchase = await PurchaseModel.findByPk(id);
    if (!purchase) {
      return res
        .status(404)
        .json({ message: `${type} purchase with ID ${id} not found` });
    }

    // ✅ Parse items if necessary
    let parsedItems;
    try {
      parsedItems =
        typeof items === "string"
          ? JSON.parse(items)
          : Array.isArray(items)
          ? items
          : purchase.items;
    } catch (error) {
      return res
        .status(400)
        .json({ message: "Invalid items format", error: error.message });
    }

    // ✅ Update fields safely
    purchase.vendor_id = vendor_id ?? purchase.vendor_id;
    purchase.amount = amount ?? purchase.amount;
    purchase.date = date ?? purchase.date;
    purchase.notes = notes ?? purchase.notes;
    purchase.delivery_status = delivery_status ?? purchase.delivery_status;
    purchase.payment_status = payment_status ?? purchase.payment_status;
    purchase.payment_method = payment_method ?? purchase.payment_method;
    purchase.items = parsedItems ?? purchase.items;

    // ✅ Handle image update
    if (req.file) {
      const imagePath = `/uploads/receipts/${req.file.filename}`;
      purchase.receipt_image = imagePath;
    }

    // ✅ Save updates
    await purchase.save();

    return res.status(200).json({
      message: `${type === "drink" ? "Drink" : "Food"} purchase updated successfully`,
      updatedPurchase: purchase,
    });
  } catch (error) {
    console.error("❌ Error updating purchase:", error);
    return res.status(500).json({
      message: "Server error while updating purchase",
      error: error.message,
    });
  }
};


// Delete inventory item
const deleteItem = async (req, res) => {
  const item = await PurchaseHistory.findByPk(req.params.id);
  if (!item) return res.status(404).json({ message: 'Item not found' });
  await item.destroy();
  res.json({ message: 'Item deleted Successfully' });
};



// Download inventory as Excel
const downloadPurchaseHistory = async (req, res) => {
  try {
    const purchaseHistory = await PurchaseHistory.findAll({
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

    // Define columns
    worksheet.columns = [
      { header: 'ID', key: 'id', width: 10 },
      { header: 'Purchase Date', key: 'date', width: 20 },
      { header: 'Vendor Name', key: 'vendorName', width: 25 },
      { header: 'Amount (₹)', key: 'amount', width: 15 },
      { header: 'Items', key: 'items', width: 60 },
      { header: 'Notes', key: 'notes', width: 30 },
    ];

    // Style the header row
    worksheet.getRow(1).font = { bold: true };

    // Enable text wrapping and alignment
    worksheet.getColumn('items').alignment = { wrapText: true, vertical: 'top' };
    ['vendorName', 'amount', 'notes', 'date'].forEach((key) => {
      worksheet.getColumn(key).alignment = { vertical: 'top' };
    });

    // Add rows
    purchaseHistory.forEach((entry) => {
      const data = entry.toJSON();

      // Format items into multi-line string
      const formattedItems = (data.items || [])
        .map(
          (item) =>
            `${item.menuItem} ×${item.quantity} — ₹${item.totalAmount} @ ₹${item.pricePerUnit}`
        )
        .join('\n');

      // Format date: 23 Apr 2025
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

    // Set headers for file download
    res.setHeader(
      'Content-Type',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    );
    res.setHeader(
      'Content-Disposition',
      'attachment; filename=purchase_history.xlsx'
    );

    await workbook.xlsx.write(res);
    res.status(200).end();
  } catch (error) {
    console.error('Error downloading purchase history:', error);
    res.status(500).json({
      message: 'Error downloading purchase history',
      error: error.message,
    });
  }
};

// Get purchases with pending payment status
const getPendingPurchases = async (req, res) => {
  try {
    // Fetch pending purchases from PurchaseHistory
    const pendingPurchases = await PurchaseHistory.findAll({
      where: {
        payment_status: 'pending',
      },
      include: [
        {
          model: Vendor,
          as: 'vendor',
          attributes: ['name'],
        },
      ],
    });

    // Fetch pending purchases from DrinksPurchaseHistory
    const pendingDrinkPurchases = await DrinksPurchaseHistory.findAll({
      where: {
        payment_status: 'pending',
      },
      include: [
        {
          model: Vendor,
          as: 'vendor',
          attributes: ['name'],
        },
      ],
    });

    // Combine both arrays
    const combinedPendingPurchases = [...pendingPurchases, ...pendingDrinkPurchases];

    res.status(200).json(combinedPendingPurchases);
  } catch (error) {
    console.error('Error fetching pending purchases:', error);
    res.status(500).json({ message: 'Error fetching pending purchases', error: error.message });
  }
};


module.exports = {  
  getPurchaseHistory,
  getItemById, 
  createPurchase, 
  updateItem, 
  deleteItem, 
  downloadPurchaseHistory,
  getPendingPurchases,
  excelupload,
  approvePurchase,
};

