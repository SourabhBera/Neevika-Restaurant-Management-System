const express = require('express');
const {
  getPurchaseHistory,
  getItemById,
  createPurchase,
  updateItem,
  deleteItem,
  downloadPurchaseHistory,
  getPendingPurchases,
  approvePurchase
} = require('../../controllers/FoodController/purchaseHistoryController');
const { uploadFields } = require('../../middlewares/multerUpload'); // Combined multer middleware

const router = express.Router();

// Use the combined Multer middleware for the POST route
router.post('/', uploadFields, createPurchase);

// Other routes remain unchanged
router.get('/', getPurchaseHistory);
router.get('/download', downloadPurchaseHistory);
router.get('/purchases/pending', getPendingPurchases);
router.get('/:id', getItemById);
router.put('/:id', uploadFields, updateItem);  // Keep the upload for updates as well
router.delete('/:id', deleteItem);

// ✅ Route to complete a purchase
router.post('/:id/complete', approvePurchase);

module.exports = router;
