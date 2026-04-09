const express = require('express');
const {
  transferToKitchen,
  getKitchenInventory,
  clearKitchenInventory,
  downloadKitchenInventory,
  getTransferHistory,
  transferViaBarcode

} = require('../../controllers/FoodController/kitchenController');
const router = express.Router();

// Transfer ingredients to kitchen inventory
router.post('/transfer', transferToKitchen);
router.post('/scan-barcode-transfer', transferViaBarcode);

// Get kitchen inventory
router.get('/inventory', getKitchenInventory);

// Clear kitchen inventory
router.delete('/clear', clearKitchenInventory);

//Download Kitchen incentory
router.get('/download', downloadKitchenInventory);

//Get Transfer History
router.get('/transfer-history', getTransferHistory )

module.exports = router;
