const express = require('express');
const router = express.Router();
const payrollController = require('../../controllers/AccountingController/payrollController');

router.post('/generate', payrollController.createPayrollForMonth);
router.get('/', payrollController.getPayrolls);
router.put('/:id', payrollController.updatePayroll);
router.delete('/:id', payrollController.deletePayroll); // optional

module.exports = router;
