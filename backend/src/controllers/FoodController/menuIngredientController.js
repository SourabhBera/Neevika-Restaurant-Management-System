const { MenuIngredient, Menu, Inventory, KitchenInventory } = require('../../models');
const fs = require('fs');
const csv = require('csv-parser');
const multer = require('multer');
const ExcelJS = require('exceljs');

// Multer config
const upload = multer({ dest: 'uploads/excel-uploads/menu-ingredients/' });
const bulkUploadMenuIngredients = async (req, res) => {
  const filePath = req.file.path;
  const inserted = [];
  const errors = [];

  try {
    const workbook = new ExcelJS.Workbook();
    await workbook.xlsx.readFile(filePath);

    const worksheet = workbook.getWorksheet('Menu Ingredients') || workbook.worksheets[0];
    if (!worksheet) {
      throw new Error('No worksheet found in the uploaded file.');
    }

    // Preload menu and inventory mappings
    const menus = await Menu.findAll({ attributes: ['id', 'name'], raw: true });
    const inventories = await Inventory.findAll({ attributes: ['id', 'itemName'], raw: true });

    const nameToMenuId = Object.fromEntries(menus.map(m => [m.name.trim(), m.id]));
    const nameToInventoryId = Object.fromEntries(inventories.map(i => [i.itemName.trim(), i.id]));

    const dataRows = [];
    worksheet.eachRow({ includeEmpty: false }, (row, rowNumber) => {
      if (rowNumber === 1) return; // Skip header
      dataRows.push({ row, rowNumber });
    });

    // ❗ Delete all existing MenuIngredient records
    await MenuIngredient.destroy({ where: {} });

    // Insert new records
    for (const { row, rowNumber } of dataRows) {
      const menuName = row.getCell(1).value?.toString().trim();
      const inventoryName = row.getCell(2).value?.toString().trim();
      const quantityRequired = parseFloat(row.getCell(3).value);
      const unit = row.getCell(4).value?.toString().trim();

      const MenuId = nameToMenuId[menuName];
      const inventoryId = nameToInventoryId[inventoryName];

      if (!MenuId || !inventoryId || isNaN(quantityRequired) || !unit) {
        errors.push({
          row: rowNumber,
          message: 'Missing or invalid data',
          rawData: { menuName, inventoryName, quantityRequired, unit }
        });
        continue;
      }

      try {
        await MenuIngredient.create({
          MenuId,
          inventoryId,
          quantityRequired,
          unit
        });

        inserted.push({ MenuId, inventoryId });
      } catch (err) {
        errors.push({ row: rowNumber, message: err.message });
      }
    }

    res.status(200).json({
      message: 'Bulk upload completed. All previous entries were replaced.',
      insertedCount: inserted.length,
      skippedCount: errors.length,
      errors
    });

  } catch (err) {
    console.error('Bulk upload failed:', err);
    res.status(500).json({ message: 'Bulk upload failed', error: err.message });
  } finally {
    fs.unlinkSync(filePath); // Delete temp file
  }
};




const exportMenuIngredientsToExcel = async (req, res) => {
  try {
    // Fetch data
    const menuIngredients = await MenuIngredient.findAll({
      attributes: ['MenuId', 'inventoryId', 'quantityRequired', 'unit'],
      raw: true
    });

    const menus = await Menu.findAll({ attributes: ['id', 'name'], raw: true });
    const inventories = await Inventory.findAll({ attributes: ['id', 'itemName'], raw: true });

    // Maps for name lookup
    const menuMap = Object.fromEntries(menus.map(m => [m.id, m.name]));
    const inventoryMap = Object.fromEntries(inventories.map(i => [i.id, i.itemName]));

    // Setup workbook and worksheet
    const workbook = new ExcelJS.Workbook();
    const mainSheet = workbook.addWorksheet('Menu Ingredients');

    // Define columns
    mainSheet.columns = [
      { header: 'Menu Name', key: 'menuName', width: 30 },
      { header: 'Inventory Name', key: 'inventoryName', width: 30 },
      { header: 'Quantity Required', key: 'quantityRequired', width: 20 },
      { header: 'Unit', key: 'unit', width: 15 },
    ];

    // Prepare actual data rows
    const transformedRows = menuIngredients.map(item => ({
      menuName: menuMap[item.MenuId] || `Unknown (${item.MenuId})`,
      inventoryName: inventoryMap[item.inventoryId] || `Unknown (${item.inventoryId})`,
      quantityRequired: item.quantityRequired,
      unit: item.unit,
    }));

    // Pad to 100 rows
    const totalRows = 100;
    while (transformedRows.length < totalRows) {
      transformedRows.push({ menuName: '', inventoryName: '', quantityRequired: '', unit: '' });
    }

    // Add rows to worksheet
    mainSheet.addRows(transformedRows);

    // Format as Excel Table
    mainSheet.addTable({
      name: 'MenuIngredientsTable',
      ref: 'A1',
      headerRow: true,
      style: {
        theme: 'TableStyleMedium9',
        showRowStripes: true,
      },
      columns: mainSheet.columns.map(col => ({ name: col.header })),
      rows: transformedRows.map(r => [
        r.menuName,
        r.inventoryName,
        r.quantityRequired,
        r.unit
      ])
    });

    // Create hidden reference sheet for dropdowns
    const hiddenSheet = workbook.addWorksheet('ReferenceData', { state: 'veryHidden' });

    // Insert reference values
    hiddenSheet.getColumn('A').values = ['Menu Names', ...menus.map(m => m.name)];
    hiddenSheet.getColumn('C').values = ['Inventory Names', ...inventories.map(i => i.itemName)];

    const menuRange = `ReferenceData!$A$2:$A$${menus.length + 1}`;
    const inventoryRange = `ReferenceData!$C$2:$C$${inventories.length + 1}`;

    // Apply dropdowns to the first 100 rows
    for (let i = 2; i <= totalRows + 1; i++) {
      mainSheet.getCell(`A${i}`).dataValidation = {
        type: 'list',
        formulae: [menuRange],
        allowBlank: true,
        showErrorMessage: true,
      };
      mainSheet.getCell(`B${i}`).dataValidation = {
        type: 'list',
        formulae: [inventoryRange],
        allowBlank: true,
        showErrorMessage: true,
      };
    }

    // Set download headers
    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.setHeader('Content-Disposition', 'attachment; filename=menu_ingredients.xlsx');

    await workbook.xlsx.write(res);
    res.end();
  } catch (error) {
    console.error('Error exporting Excel:', error);
    res.status(500).json({ message: 'Failed to export Excel', error: error.message });
  }
};


// Get all menu ingredients
const getMenuIngredients = async (req, res) => {
    try {
      const menuIngredients = await MenuIngredient.findAll({
        attributes: ['id', 'MenuId', 'inventoryId', 'quantityRequired', 'unit' ],
        include: [
          { model: Menu, as: 'menu', attributes: ['name'] },
          { model: Inventory, as: 'ingredient', attributes: ['itemName'] },
        ],
      });
  
      res.json(menuIngredients);
    } catch (error) {
      console.error('Error fetching menu ingredients:', error);
      res.status(500).json({
        message: 'Error fetching menu ingredients',
        error: error.message,
      });
    }
  };

// Get menu ingredient by ID
const getMenuIngredientById = async (req, res) => {
  try {
    const menuIngredient = await MenuIngredient.findByPk(req.params.id, {
      include: [
        { model: Menu, as: 'menu', attributes: ['name'] },
        { model: Ingredient, as: 'ingredient', attributes: ['itemName'] },
      ],
    });
    if (!menuIngredient) {
      return res.status(404).json({ message: 'Menu ingredient not found' });
    }
    res.json(menuIngredient);
  } catch (error) {
    console.error('Error fetching menu ingredient by ID:', error);
    res.status(500).json({ message: 'Error fetching menu ingredient', error: error.message });
  }
};

// Create new menu ingredient
const createMenuIngredient = async (req, res) => {
  try {
    const { MenuId, inventoryId, quantityRequired, unit } = req.body;
    
    // Create the menu ingredient
    const menuIngredient = await MenuIngredient.create({
      MenuId,
      inventoryId,
      quantityRequired,
      unit,
    });

    res.status(201).json(menuIngredient);  // No need to return ingredientId
  } catch (error) {
    console.error('Error creating menu ingredient:', error);
    res.status(500).json({
      message: 'Error creating menu ingredient',
      error: error.message,
    });
  }
};

// Update menu ingredient
const updateMenuIngredient = async (req, res) => {
  try {
    const { id } = req.params;
    const { MenuId, inventoryId, quantityRequired, unit } = req.body;

    const menuIngredient = await MenuIngredient.findByPk(id);
    console.log('Trying to fetch ID:', id, 'Result:', menuIngredient);

    if (!menuIngredient) {
      console.warn(`No MenuIngredient found with ID: ${id}`);
      return res.status(404).json({ message: 'Menu ingredient not found' });
    }

    // Fetch inventory item
    const inventoryItem = await KitchenInventory.findByPk(inventoryId);
    if (!inventoryItem) {
      console.warn(`No Inventory found with ID: ${inventoryId}`);
      return res.status(400).json({ message: 'Invalid inventory ID' });
    }

    // Validate unit compatibility
    if (inventoryItem.unit === 'kg') {
      const allowedUnits = ['Gram (g)', 'Kilogram (Kg)'];
      if (!allowedUnits.includes(unit)) {
        return res.status(400).json({
          message: `Invalid unit. For inventory unit 'kg', allowed units are: ${allowedUnits.join(', ')}.`,
        });
      }
    }

    await menuIngredient.update({
      MenuId,
      inventoryId,
      quantityRequired,
      unit,
    });

    console.log('MenuIngredient updated:', menuIngredient.toJSON());
    res.json(menuIngredient);
  } catch (error) {
    console.error('Error updating menu ingredient:', error);
    res.status(500).json({ message: 'Error updating menu ingredient', error: error.message });
  }
};

// Delete menu ingredient
const deleteMenuIngredient = async (req, res) => {
  try {
    const { id } = req.params;
    const menuIngredient = await MenuIngredient.findByPk(id);
    if (!menuIngredient) {
      return res.status(404).json({ message: 'Menu ingredient not found' });
    }

    await menuIngredient.destroy();
    res.json({ message: 'Menu ingredient deleted successfully!' });
  } catch (error) {
    console.error('Error deleting menu ingredient:', error);
    res.status(500).json({ message: 'Error deleting menu ingredient', error: error.message });
  }
};

module.exports = {
  getMenuIngredients,
  getMenuIngredientById,
  createMenuIngredient,
  updateMenuIngredient,
  deleteMenuIngredient,
  upload,
  bulkUploadMenuIngredients,
  exportMenuIngredientsToExcel
};
