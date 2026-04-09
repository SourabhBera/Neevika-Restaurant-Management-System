const express = require('express');
const router = express.Router();
const controller = require('../../controllers/CrmController/customerDetailQRController');

router.post('/', controller.createCustomer);
router.get('/', controller.getAllCustomers);
router.post('/verify-phone', controller.getMultipleCustomersByPhones);
router.get('/:phone', controller.getCustomerByPhone);
router.put('/:phone', controller.updateCustomer);
router.delete('/:phone', controller.deleteCustomer);

module.exports = router;
