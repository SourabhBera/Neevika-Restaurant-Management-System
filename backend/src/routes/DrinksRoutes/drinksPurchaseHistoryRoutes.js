const express = require('express');
const {
  getPurchaseHistory,
  getItemById,
  createPurchase,
  updateItem,
  deleteItem,
  downloadPurchaseHistory,
  approvePurchase
} = require('../../controllers/DrinksController/drinksPurchaseHistoryController');

const { uploadFields } = require('../../middlewares/multerUpload'); // Combined multer middleware


const router = express.Router();

// Route for getting all purchase history
router.get('/', getPurchaseHistory);

// Route for downloading purchase history as Excel
router.get('/download', downloadPurchaseHistory);

// Route for creating a new purchase with file upload
router.post('/', uploadFields, createPurchase); // Use fileUpload middleware and call createPurchase

// Route for getting a single purchase history item by ID
router.get('/:id', getItemById);

// Route for updating a purchase history item by ID
router.put('/:id', uploadFields, updateItem); // Assuming you want to handle file upload here too

// Route for deleting a purchase history item by ID
router.delete('/:id', deleteItem);

// ✅ Approve drinks purchase
router.post('/:id/approve', approvePurchase);

module.exports = router;
