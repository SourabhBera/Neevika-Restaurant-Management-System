const express = require('express');
const router = express.Router();
const {
  getInventory,
  getItemById,
  addItem,
  updateItem,
  deleteItem,
  downloadInventory,
  exportInventoryTemplateToExcel,
  upload,
  bulkUploadInventoryPurchases
} = require('../../controllers/FoodController/inventoryController');

const {
  getAllCategories,
  createCategory,
  updateCategory
} = require('../../controllers/FoodController/inventoryCategoryController');

// Inventory Category routes
router.get('/inventoryCategory', getAllCategories);
router.post('/inventoryCategory', createCategory);
router.put('/inventoryCategory/:id', updateCategory);

// Inventory routes
router.get('/', getInventory);
router.get('/export-excel', exportInventoryTemplateToExcel);
router.get('/download', downloadInventory);
router.get('/:id', getItemById);
router.post('/', addItem);
router.post('/bulk-upload', upload.single('file'), bulkUploadInventoryPurchases);
router.put('/:id', updateItem);
router.delete('/:id', deleteItem);

module.exports = router;
