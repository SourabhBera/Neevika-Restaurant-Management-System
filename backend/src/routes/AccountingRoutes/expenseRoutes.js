const express = require("express");
const router = express.Router();
const expenseController = require("../../controllers/AccountingController/expenseController");
const createUploadMiddleware = require('../../middlewares/imageUploadMiddleware');
const uploadReceiptImage = createUploadMiddleware('expense_receipts', 'receipt_image');

// Create
router.post("/expense/", uploadReceiptImage, expenseController.createExpense);

// Read
router.get("/expense/", expenseController.getExpenses);              // Optional query: ?from=2025-06-01&to=2025-06-26
router.get("/expense/:id", expenseController.getExpenseById);        // Get by ID

// Update
router.put("/expense/:id", uploadReceiptImage, expenseController.updateExpense);

// Delete
router.delete("/expense/:id", expenseController.deleteExpense);

module.exports = router;
