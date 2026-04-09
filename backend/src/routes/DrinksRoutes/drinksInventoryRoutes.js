const express = require('express');
const {
  getInventory,
  getItemById,
  addItem,
  updateItem,
  deleteItem,
  downloadInventory,
  exportInventoryTemplateToExcel,
} = require('../../controllers/DrinksController/drinksInventoryController');
const router = express.Router();
const {upload, bulkUploadInventoryPurchases} = require('../../controllers/DrinksController/drinksInventoryController');

const {
  getAllCategories,
  createCategory,
  updateCategory
} = require('../../controllers/DrinksController/drinksInventoryCategoryController');

// Inventory Category routes
router.get('/drinks-inventoryCategory', getAllCategories);
router.post('/drinks-inventoryCategory', createCategory);
router.put('/drinks-inventoryCategory/:id', updateCategory);



router.get('/', getInventory);
router.get('/export-excel', exportInventoryTemplateToExcel);
router.get('/download', downloadInventory);
router.get('/:id', getItemById);
router.post('/', addItem);
router.post('/bulk-upload', upload.single('file'), bulkUploadInventoryPurchases);
router.put('/:id', updateItem);
router.delete('/:id', deleteItem);

module.exports = router;
