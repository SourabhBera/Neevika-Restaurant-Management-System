const express = require('express');
const router = express.Router();
const customerDetailsController = require('../../controllers/CrmController/customerDetailsController');

router.get('/customers-details', customerDetailsController.getAllCustomerDetails);
router.get('/Qr-customers-details', customerDetailsController.getAllQrCustomerDetails);
router.get('/download', customerDetailsController.downloadCustomerDetials);

module.exports = router;
