const { DrinksInventory, DrinksInventoryCategory } = require('../../models');
const ExcelJS = require('exceljs');
const fs = require('fs');
const multer = require('multer');
const { Sequelize } = require('sequelize');
const bwipjs = require('bwip-js'); // npm install bwip-js

// Multer config
const upload = multer({ dest: 'uploads/excel-uploads/drinks-inventory-purchases/' });

const bulkUploadInventoryPurchases = async (req, res) => {
  const filePath = req.file.path;
  const added = [];
  const errors = [];

  try {
    const workbook = new ExcelJS.Workbook();
    await workbook.xlsx.readFile(filePath);

    const worksheet = workbook.getWorksheet('Drinks Inventory Purchases') || workbook.worksheets[0];
    if (!worksheet) throw new Error('No worksheet found in the uploaded file.');

    // Fetch all existing inventories and categories
    const inventories = await DrinksInventory.findAll({ raw: true });
    const nameToInventory = Object.fromEntries(inventories.map(i => [i.itemName.trim(), i]));

    const categories = await DrinksInventoryCategory.findAll({ raw: true });
    const categoryMap = Object.fromEntries(categories.map(c => [c.categoryName.trim(), c.id]));

    const dataRows = [];
    worksheet.eachRow({ includeEmpty: false }, (row, rowNumber) => {
      if (rowNumber === 1) return; // Skip header
      dataRows.push({ row, rowNumber });
    });

    for (const { row, rowNumber } of dataRows) {
      const itemName = row.getCell(1).value?.toString().trim();
      const quantityPurchased = parseFloat(row.getCell(2).value);
      const unit = row.getCell(3).value?.toString().trim();
      const bottleSize = parseFloat(row.getCell(4).value);
      const categoryName = row.getCell(5).value?.toString().trim();
      const minQtyRaw = parseFloat(row.getCell(6).value);
      const minQtyUnit = row.getCell(7).value?.toString().trim() || unit;
      const priceRaw = parseFloat(row.getCell(8).value);
      const price = isNaN(priceRaw) ? 0 : priceRaw;

      // Validate required fields
      if (!itemName || isNaN(quantityPurchased) || !unit || isNaN(price)) {
        errors.push({
          row: rowNumber,
          message: 'Missing or invalid required fields',
          rawData: { itemName, quantityPurchased, unit, price, categoryName }
        });
        continue;
      }

      // Set minimum quantity, default is 5
      const minimumQuantity = isNaN(minQtyRaw) ? 5 : minQtyRaw;

      // Check if the category exists, create it if not
      let categoryId = null;
      if (categoryName) {
        categoryId = categoryMap[categoryName];
        if (!categoryId) {
          try {
            const newCategory = await DrinksInventoryCategory.create({ categoryName });
            categoryId = newCategory.id;
            categoryMap[categoryName] = categoryId;
            console.log(`New category created: ${categoryName}, ID: ${categoryId}`);
          } catch (err) {
            errors.push({ row: rowNumber, message: `Error creating category: ${err.message}` });
            continue;
          }
        }
      }

      const existingItem = nameToInventory[itemName];

      try {
        if (existingItem) {
      await DrinksInventory.update({
        quantity: existingItem.quantity + quantityPurchased
      }, {
        where: { id: existingItem.id }
      });

      added.push({ itemName, addedQuantity: quantityPurchased });
    }else {
          await DrinksInventory.create({
            itemName,
            quantity: quantityPurchased,
            unit,
            minimumQuantity,
            minimumQuantity_unit: minQtyUnit,
            categoryId,
            bottleSize,
            price,
          });

          added.push({ itemName, addedQuantity: quantityPurchased });
        }
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
    if (fs.existsSync(filePath)) fs.unlinkSync(filePath); // Clean up uploaded file
  }
};



// const exportInventoryTemplateToExcel = async (req, res) => {
//   try {
//     const inventories = await DrinksInventory.findAll({
//       attributes: ['itemName', 'unit', 'bottleSize', 'categoryId'],
//       include: [
//         {
//           model: DrinksInventoryCategory,
//           as: 'category',
//           attributes: ['categoryName'],
//         }
//       ],
//       raw: true,
//       nest: true
//     });

//     const categories = await DrinksInventoryCategory.findAll({
//       attributes: ['categoryName', 'id'],
//       raw: true
//     });

//     const workbook = new ExcelJS.Workbook();
//     const mainSheet = workbook.addWorksheet('Drinks Inventory Purchases');

//     mainSheet.columns = [
//       { header: 'Inventory Name', key: 'itemName', width: 30 },
//       { header: 'Quantity Purchased', key: 'quantity', width: 20 },
//       { header: 'Unit', key: 'unit', width: 15 },
//       { header: 'Bottle Size', key: 'bottleSize', width: 15 },
//       { header: 'Category Name', key: 'categoryName', width: 30 },
//       { header: 'Minimum Quantity', key: 'minimumQuantity', width: 20 },
//       { header: 'Minimum Quantity Unit', key: 'minimumQuantity_unit', width: 25 },
//       { header: 'Price', key: 'price', width: 15 },
//     ];

//     const transformedRows = inventories.slice(0, 100).map(item => ({
//       itemName: item.itemName,
//       quantity: '',
//       unit: item.unit,
//       bottleSize: item.bottleSize,
//       categoryName: item.category?.categoryName || '',
//       minimumQuantity: '',
//       minimumQuantity_unit: item.unit,
//       price: '',
//     }));

//     const totalRows = 100;
//     while (transformedRows.length < totalRows) {
//       transformedRows.push({
//         itemName: '', quantity: '', unit: '', bottleSize: '', categoryName: '', minimumQuantity: '', minimumQuantity_unit: '', price: ''
//       });
//     }

//     mainSheet.addRows(transformedRows);

//     mainSheet.addTable({
//       name: 'InventoryUploadTable',
//       ref: 'A1',
//       headerRow: true,
//       style: {
//         theme: 'TableStyleMedium9',
//         showRowStripes: true,
//       },
//       columns: mainSheet.columns.map(col => ({ name: col.header })),
//       rows: transformedRows.map(r => [
//         r.itemName,
//         r.quantity,
//         r.unit,
//         r.bottleSize,
//         r.categoryName,
//         r.minimumQuantity,
//         r.minimumQuantity_unit,
//         r.price,
//       ])
//     });

//     const hiddenSheet = workbook.addWorksheet('ReferenceData', { state: 'veryHidden' });

//     // Reference data: Inventory Names (A), Categories (B), Beer Sizes (C), Other Sizes (D)
//     hiddenSheet.getColumn('A').values = ['Inventory Names', ...inventories.map(i => i.itemName)];
//     hiddenSheet.getColumn('B').values = ['Inventory Categories', ...categories.map(c => c.categoryName)];
//     hiddenSheet.getColumn('C').values = ['BeerSizes', 330, 650];
//     hiddenSheet.getColumn('D').values = ['OtherSizes', 90, 180, 360, 750, 1000, 1500, 2000];

//     const inventoryNameRange = `ReferenceData!$A$2:$A$${inventories.length + 1}`;
//     const categoryRange = `ReferenceData!$B$2:$B$${categories.length + 1}`;
//     const beerSizeRange = 'ReferenceData!$C$2:$C$3';
//     const otherSizeRange = 'ReferenceData!$D$2:$D$8';

//     for (let i = 2; i <= totalRows + 1; i++) {
//       mainSheet.getCell(`A${i}`).dataValidation = {
//         type: 'list',
//         formulae: [inventoryNameRange],
//         allowBlank: true,
//       };

//       mainSheet.getCell(`E${i}`).dataValidation = {
//         type: 'list',
//         formulae: [categoryRange],
//         allowBlank: true,
//       };

//       // Conditional dropdown for Bottle Size (Column D)
//       mainSheet.getCell(`D${i}`).dataValidation = {
//         type: 'list',
//         formulae: [`IF(E${i}="beer", ${beerSizeRange}, ${otherSizeRange})`],
//         allowBlank: true,
//       };
//     }

//     res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
//     res.setHeader('Content-Disposition', 'attachment; filename=drinks_inventory_upload_template.xlsx');

//     await workbook.xlsx.write(res);
//     res.end();
//   } catch (error) {
//     console.error('Error exporting inventory template:', error);
//     res.status(500).json({ message: 'Failed to export inventory template', error: error.message });
//   }
// };


const exportInventoryTemplateToExcel = async (req, res) => {
  try {
    // 1. Fetch inventories and categories (without bottleSize)
    const inventories = await DrinksInventory.findAll({
      attributes: ['itemName', 'unit', 'categoryId'],
      include: [
        {
          model: DrinksInventoryCategory,
          as: 'category',
          attributes: ['categoryName'],
        }
      ],
      order: [['categoryId', 'ASC']],
      raw: true,
      nest: true
    });

    const categories = await DrinksInventoryCategory.findAll({
      attributes: ['categoryName', 'id'],
      raw: true
    });

    const workbook = new ExcelJS.Workbook();
    const mainSheet = workbook.addWorksheet('Drinks Inventory Purchases');

    // 2. Define columns (4 columns only)
    mainSheet.columns = [
      { header: 'Inventory Name', key: 'itemName', width: 30 },
      { header: 'Quantity Purchased', key: 'quantity', width: 20 },
      { header: 'Unit', key: 'unit', width: 15 },
      { header: 'Category', key: 'categoryName', width: 30 },
    ];

    const totalRows = 100;

    // 3. Prepare and pad rows
    const transformedRows = inventories.slice(0, totalRows).map(item => ({
      itemName: item.itemName,
      quantity: '',
      unit: item.unit,
      categoryName: item.category?.categoryName || '',
    }));

    while (transformedRows.length < totalRows) {
      transformedRows.push({
        itemName: '', quantity: '', unit: '', categoryName: ''
      });
    }

    mainSheet.addRows(transformedRows);

    // Style header
    const headerRow = mainSheet.getRow(1);
    headerRow.font = { bold: true };
    headerRow.fill = {
      type: 'pattern',
      pattern: 'solid',
      fgColor: { argb: 'FFD9E1F2' }
    };

    // 4. Hidden sheet for dropdowns
    const hiddenSheet = workbook.addWorksheet('ReferenceData', { state: 'veryHidden' });
    hiddenSheet.getColumn('A').values = ['Inventory Names', ...inventories.map(i => i.itemName)];
    hiddenSheet.getColumn('B').values = ['Categories', ...categories.map(c => c.categoryName)];

    const inventoryNameRange = `ReferenceData!$A$2:$A$${inventories.length + 1}`;
    const categoryRange = `ReferenceData!$B$2:$B$${categories.length + 1}`;

    // 5. Apply data validation and protection
    for (let i = 2; i <= totalRows + 1; i++) {
      // Inventory Name dropdown (A)
      mainSheet.getCell(`A${i}`).dataValidation = {
        type: 'list',
        formulae: [inventoryNameRange],
        allowBlank: false,
        showErrorMessage: true,
        errorTitle: 'Invalid Entry',
        error: 'Select inventory name from the list only.'
      };

      // Category dropdown (D)
      mainSheet.getCell(`D${i}`).dataValidation = {
        type: 'list',
        formulae: [categoryRange],
        allowBlank: false,
        showErrorMessage: true,
        errorTitle: 'Invalid Entry',
        error: 'Select category from the list only.'
      };

      // Lock all cells except Quantity (B)
      mainSheet.getCell(`A${i}`).protection = { locked: true };
      mainSheet.getCell(`B${i}`).protection = { locked: false }; // Editable
      mainSheet.getCell(`C${i}`).protection = { locked: true };
      mainSheet.getCell(`D${i}`).protection = { locked: true };
    }

    // 6. Protect the sheet
    await mainSheet.protect('drinks123', {
      selectLockedCells: true,
      selectUnlockedCells: true,
      formatCells: false,
      insertColumns: false,
      insertRows: false,
      deleteColumns: false,
      deleteRows: false,
    });

    // 7. Send Excel file
    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.setHeader('Content-Disposition', 'attachment; filename=drinks_inventory_upload_template.xlsx');

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
    const inventory = await DrinksInventory.findAll({
      order: [
        // Create a custom sorting logic using CASE WHEN
        [Sequelize.literal(`
          CASE
            WHEN quantity = 0 THEN 0
            WHEN quantity <= "minimumQuantity" THEN 1
            ELSE 2
          END
        `), 'ASC'],
        ['categoryId', 'ASC'] // secondary sort
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
  const item = await DrinksInventory.findByPk(req.params.id);
  if (!item) return res.status(404).json({ message: 'Item not found' });
  res.json(item);
};

// Add a new inventory item
const addItem = async (req, res) => {
  try {
    const {
      itemName,
      quantity,
      price,
      unit,
      minimumQuantity,
      minimumQuantity_unit
    } = req.body;

    if (!itemName || quantity == null || !unit || price == null || minimumQuantity == null || !minimumQuantity_unit) {
      return res.status(400).json({ message: 'Missing required fields' });
    }

    const item = await DrinksInventory.create({
      itemName,
      quantity,
      price,
      unit,
      minimumQuantity,
      minimumQuantity_unit
    });

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
    const {
      itemName,
      quantity,
      price,
      unit,
      minimumQuantity,
      minimumQuantity_unit
    } = req.body;

    const item = await DrinksInventory.findByPk(id);
    if (!item) {
      return res.status(404).json({ message: 'Item not found' });
    }

    item.itemName = itemName ?? item.itemName;
    item.quantity = quantity ?? item.quantity;
    item.price = price ?? item.price;
    item.unit = unit ?? item.unit;
    item.minimumQuantity = minimumQuantity ?? item.minimumQuantity;
    item.minimumQuantity_unit = minimumQuantity_unit ?? item.minimumQuantity_unit;

    await item.save();

    res.status(200).json(item);
  } catch (error) {
    console.error('Error updating item:', error);
    res.status(500).json({ message: 'Error updating item', error: error.message });
  }
};

// Delete inventory item
const deleteItem = async (req, res) => {
  const item = await DrinksInventory.findByPk(req.params.id);
  if (!item) return res.status(404).json({ message: 'Item not found' });
  await item.destroy();
  res.json({ message: 'Item deleted' });
};

// Download inventory as Excel
const downloadInventory = async (req, res) => {
  try {
    const inventory = await DrinksInventory.findAll();

    const workbook = new ExcelJS.Workbook();
    const worksheet = workbook.addWorksheet('Drinks Inventory');

    // 🧾 Define headers
    worksheet.columns = [
      { header: 'Item Name', key: 'itemName', width: 25 },
      { header: 'Quantity', key: 'quantity', width: 15 },
      { header: 'Unit', key: 'unit', width: 15 },
      { header: 'Minimum Quantity', key: 'minimumQuantity', width: 20 },
      { header: 'Minimum Quantity Unit', key: 'minimumQuantity_unit', width: 25 },
      { header: 'QR Code', key: 'qr', width: 20 },
    ];

    // 💄 Style header row
    const headerRow = worksheet.getRow(1);
    headerRow.font = { bold: true };
    headerRow.fill = {
      type: 'pattern',
      pattern: 'solid',
      fgColor: { argb: 'FFD9E1F2' },
    };

    // 📌 Freeze header row
    worksheet.views = [{ state: 'frozen', ySplit: 1 }];

    let rowIndex = 2;

    for (const item of inventory) {
      const row = worksheet.addRow({
        itemName: item.itemName,
        quantity: item.quantity,
        unit: item.unit,
        minimumQuantity: item.minimumQuantity,
        minimumQuantity_unit: item.minimumQuantity_unit,
        qr: '',
      });

      // 📏 Set row height to fit barcode image
      row.height = 50;

      const barcodeText = `${item.id}#1#${item.unit}`;

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

      worksheet.addImage(imageId, {
        tl: { col: 5, row: rowIndex - 1 }, // Column G (0-based index)
        ext: { width: 100, height: 40 },
      });

      rowIndex++;
    }

    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.setHeader('Content-Disposition', 'attachment; filename=DrinksInventory.xlsx');

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
  bulkUploadInventoryPurchases,
  exportInventoryTemplateToExcel,
};
