const { Inventory, InventoryCategory } = require('../../models');
const ExcelJS = require('exceljs'); 
const fs = require('fs');
const csv = require('csv-parser');
const multer = require('multer');
const { Sequelize } = require('sequelize');
const bwipjs = require('bwip-js'); // npm install bwip-js

// Multer config
const upload = multer({ dest: 'uploads/excel-uploads/inventory-purchases/' });

const bulkUploadInventoryPurchases = async (req, res) => {
  const filePath = req.file.path;
  const added = [];
  const errors = [];

  try {
    const workbook = new ExcelJS.Workbook();
    await workbook.xlsx.readFile(filePath);

    const worksheet = workbook.getWorksheet('Inventory Purchases') || workbook.worksheets[0];
    if (!worksheet) throw new Error('No worksheet found in the uploaded file.');

    // Fetch inventories and categories
    const inventories = await Inventory.findAll({ raw: true });
    const nameToInventory = Object.fromEntries(inventories.map(i => [i.itemName.trim(), i]));

    const categories = await InventoryCategory.findAll({ raw: true });
    const categoryMap = Object.fromEntries(categories.map(c => [c.categoryName.trim(), c.id]));

    const dataRows = [];
    worksheet.eachRow({ includeEmpty: false }, (row, rowNumber) => {
      if (rowNumber === 1) return; // skip header
      dataRows.push({ row, rowNumber });
    });

    for (const { row, rowNumber } of dataRows) {
      const itemName = row.getCell(1).value?.toString().trim();
      const quantityPurchased = parseFloat(row.getCell(2).value);
      const unit = row.getCell(3).value?.toString().trim();
      const categoryName = row.getCell(4).value?.toString().trim();

      // Validate required fields
      if (!itemName || isNaN(quantityPurchased) || !unit || !categoryName) {
        errors.push({
          row: rowNumber,
          message: 'Missing or invalid required fields.',
          rawData: { itemName, quantityPurchased, unit, categoryName }
        });
        continue;
      }

      const existingItem = nameToInventory[itemName];

      // Validate inventory exists
      if (!existingItem) {
        errors.push({
          row: rowNumber,
          message: `Inventory item "${itemName}" does not exist.`,
        });
        continue;
      }

      // Validate unit matches
      if (existingItem.unit !== unit) {
        errors.push({
          row: rowNumber,
          message: `Unit mismatch for "${itemName}". Expected "${existingItem.unit}", got "${unit}".`,
        });
        continue;
      }

      // Validate category matches
      const expectedCategoryName = categories.find(c => c.id === existingItem.categoryId)?.categoryName;
      if (expectedCategoryName !== categoryName) {
        errors.push({
          row: rowNumber,
          message: `Category mismatch for "${itemName}". Expected "${expectedCategoryName}", got "${categoryName}".`,
        });
        continue;
      }

      try {
        // Update existing item
        await Inventory.update({
          quantity: existingItem.quantity + quantityPurchased,
        }, {
          where: { id: existingItem.id }
        });

        added.push({ itemName, addedQuantity: quantityPurchased });
      } catch (err) {
        errors.push({ row: rowNumber, message: err.message });
      }
    }

    res.status(200).json({
      message: 'Inventory upload completed.',
      addedCount: added.length,
      skippedCount: errors.length,
      errors
    });

  } catch (err) {
    console.error('Inventory upload failed:', err);
    res.status(500).json({ message: 'Inventory upload failed', error: err.message });
  } finally {
    fs.unlinkSync(filePath);
  }
};




const exportInventoryTemplateToExcel = async (req, res) => {
  try {
    const inventories = await Inventory.findAll({
      attributes: ['itemName', 'unit', 'categoryId'],
      include: [{
        model: InventoryCategory,
        as: 'category',
        attributes: ['categoryName'],
      }],
      raw: true,
      nest: true,
      order: [['categoryId', 'ASC']] // Sort by categoryId
    });

    const categories = await InventoryCategory.findAll({
      attributes: ['categoryName', 'id'],
      raw: true
    });

    const workbook = new ExcelJS.Workbook();
    const mainSheet = workbook.addWorksheet('Inventory Purchases');

    // Define only required columns
    mainSheet.columns = [
      { header: 'Inventory Name', key: 'itemName', width: 30 },
      { header: 'Quantity Purchased', key: 'quantity', width: 20 },
      { header: 'Unit', key: 'unit', width: 15 },
      { header: 'Category', key: 'categoryName', width: 30 },
    ];

    // Prepare rows
    const totalRows = 100;
    const transformedRows = inventories.slice(0, totalRows).map(item => ({
      itemName: item.itemName,
      quantity: '',
      unit: item.unit,
      categoryName: item.category?.categoryName || '',
    }));

    while (transformedRows.length < totalRows) {
      transformedRows.push({ itemName: '', quantity: '', unit: '', categoryName: '' });
    }

    mainSheet.addRows(transformedRows);

    // Create hidden sheet for dropdowns
    const hiddenSheet = workbook.addWorksheet('ReferenceData', { state: 'veryHidden' });
    hiddenSheet.getColumn('A').values = ['Inventory Names', ...inventories.map(i => i.itemName)];
    hiddenSheet.getColumn('B').values = ['Categories', ...categories.map(c => c.categoryName)];

    const inventoryNameRange = `ReferenceData!$A$2:$A$${inventories.length + 1}`;
    const categoryRange = `ReferenceData!$B$2:$B$${categories.length + 1}`;

    for (let i = 2; i <= totalRows + 1; i++) {
      mainSheet.getCell(`A${i}`).dataValidation = {
        type: 'list',
        formulae: [inventoryNameRange],
        allowBlank: false,
        showErrorMessage: true,
        errorStyle: 'error',
        errorTitle: 'Invalid Entry',
        error: 'Please select an inventory item from the list.'
      };

      mainSheet.getCell(`D${i}`).dataValidation = {
        type: 'list',
        formulae: [categoryRange],
        allowBlank: false,
        showErrorMessage: true,
        errorStyle: 'error',
        errorTitle: 'Invalid Entry',
        error: 'Please select a category from the list.'
      };

      // Lock Inventory Name, Unit, and Category
      mainSheet.getCell(`A${i}`).protection = { locked: true };
      mainSheet.getCell(`C${i}`).protection = { locked: true };
      mainSheet.getCell(`D${i}`).protection = { locked: true };

      // Unlock Quantity Purchased
      mainSheet.getCell(`B${i}`).protection = { locked: false };
    }

    // Protect sheet (only Quantity Purchased editable)
    await mainSheet.protect('your-password', {
      selectLockedCells: true,
      selectUnlockedCells: true,
      formatCells: false,
      insertColumns: false,
      insertRows: false,
      deleteColumns: false,
      deleteRows: false,
    });

    // Send the file
    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.setHeader('Content-Disposition', 'attachment; filename=inventory_template.xlsx');
    await workbook.xlsx.write(res);
    res.end();
  } catch (error) {
    console.error('Error exporting inventory template:', error);
    res.status(500).json({ message: 'Failed to export inventory template', error: error.message });
  }
};




// Get all inventory items
const getInventory = async (req, res) => {
  try {
    const inventory = await Inventory.findAll({
      include: [{
        model: InventoryCategory,
        as: 'category',
        attributes: ['categoryName'],
      }],
      order: [
        [
          // Custom ordering using CASE expression
          Sequelize.literal(`
            CASE
              WHEN quantity = 0 THEN 0
              WHEN quantity <= minimum_quantity THEN 1
              ELSE 2
            END
          `),
          'ASC'
        ],
        ['categoryId', 'ASC'] // Order by categoryId
      ]
    });

    res.status(200).json(inventory);
  } catch (error) {
    console.error('Error fetching inventory:', error);
    res.status(500).json({ message: 'Error fetching inventory', error: error.message });
  }
};


// Get single item by ID
const getItemById = async (req, res) => {
  const item = await Inventory.findByPk(req.params.id);
  if (!item) return res.status(404).json({ message: 'Item not found' });
  res.json(item);
};



// Add a new inventory item
const addItem = async (req, res) => {
  try {
    const { itemName, quantity, unit, expiryDate, barcode, minimum_quantity, minimum_quantity_unit } = req.body;

    // Ensure required fields are provided
    if (!itemName || !quantity || !unit) {
      return res.status(400).json({ message: 'Item name, quantity, and metric are required' });
    }

    console.log(req.body);

    const item = await Inventory.create({
      itemName,
      quantity,
      unit,
      expiryDate,
      barcode,
      minimum_quantity, 
      minimum_quantity_unit
    });

    console.log('Saved item:', item.toJSON());

    res.status(201).json(item);
  } catch (error) {
    console.error('Error adding item:', error);
    res.status(500).json({ message: 'Error adding item', error: error.message });
  }
};



// Update inventory item
const updateItem = async (req, res) => {
  try {
    const { id } = req.params;
    const { itemName, quantity, metric, expiryDate, barcode, categoryId } = req.body;
    console.log('Update request body:', req.body);
    // Check if the item exists
    const item = await Inventory.findByPk(id);
    if (!item) {
      return res.status(404).json({ message: 'Item not found' });
    }

    // Update item properties
    item.itemName = itemName || item.itemName;
    item.quantity = quantity || item.quantity;
    item.metric = metric || item.metric; // 🎯 Ensure metric is included
    item.expiryDate = expiryDate || item.expiryDate;
    item.barcode = barcode || item.barcode;
    item.categoryId = categoryId || item.categoryId;

    // Save the updated item
    await item.save();

    res.status(200).json(item);
  } catch (error) {
    console.error('Error updating item:', error);
    res.status(500).json({ message: 'Error updating item', error: error.message });
  }
};


// Delete inventory item
const deleteItem = async (req, res) => {
  const item = await Inventory.findByPk(req.params.id);
  if (!item) return res.status(404).json({ message: 'Item not found' });
  await item.destroy();
  res.json({ message: 'Item deleted' });
};



const downloadInventory = async (req, res) => {
  try {
    const inventory = await Inventory.findAll();

    const workbook = new ExcelJS.Workbook();
    const worksheet = workbook.addWorksheet('Inventory');

    worksheet.columns = [
      { header: 'Item Name', key: 'itemName', width: 25 },
      { header: 'Total Quantity', key: 'quantity', width: 15 },
      { header: 'Unit', key: 'unit', width: 15 },
      { header: 'Barcode Units', key: 'barcode', width: 20 },
      { header: 'Minimum Quantity', key: 'minimum_quantity', width: 20 },
      { header: 'Minimum Quantity Unit', key: 'minimum_quantity_unit', width: 25 },
      { header: 'QR', key: 'qr', width: 30 } // 7th column
    ];

    let rowIndex = 2;

    for (const item of inventory) {
      const row = worksheet.addRow(item.toJSON());

      // Optional: Set row height for better QR display
      row.height = 50;

      const barcodeText = `${item.id || 'NA'}#${item.barcode || 'NA'}#${item.unit || 'NA'}`;

      try {
        const pngBuffer = await bwipjs.toBuffer({
          bcid: 'code128',
          text: barcodeText,
          scale: 3,
          height: 10,
          includetext: false,
        });

        const imageId = workbook.addImage({
          buffer: pngBuffer,
          extension: 'png',
        });

        // Place image in column G (6 = zero-based index)
        worksheet.addImage(imageId, {
          tl: { col: 6, row: rowIndex - 1 },
          ext: { width: 150, height: 50 },
        });

      } catch (barcodeErr) {
        console.warn(`Barcode generation failed for row ${rowIndex}: ${barcodeErr.message}`);
      }

      rowIndex++;
    }

    res.setHeader(
      'Content-Type',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    );
    res.setHeader(
      'Content-Disposition',
      'attachment; filename=inventory.xlsx'
    );

    await workbook.xlsx.write(res);
    res.status(200).end();
  } catch (error) {
    console.error('Error downloading inventory:', error);
    res.status(500).json({ message: 'Error downloading inventory', error: error.message });
  }
};


module.exports = { 
  getInventory, 
  getItemById, 
  addItem, 
  updateItem, 
  deleteItem, 
  downloadInventory,
  upload, 
  exportInventoryTemplateToExcel, 
  bulkUploadInventoryPurchases,
 };
