const express = require('express');
const router = express.Router();
const profitLossController = require('../../controllers/AccountingController/profitLossController');

// GET all monthly summaries
router.get('/', profitLossController.getAll);

// GET single summary by month (e.g., '2025-05')
router.get('/:date', profitLossController.getByDate);

// POST generate monthly summary (body: { date: 'YYYY-MM' })
router.post('/generate', profitLossController.generateMonthly);

// DELETE summary by month
router.delete('/:date', profitLossController.delete);

// DOWNLOAD all profit & loss data as Excel
router.get('/download/excel', profitLossController.downloadExcel);

module.exports = router;
