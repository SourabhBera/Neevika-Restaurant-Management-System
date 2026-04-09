const { image } = require('pdfkit');
const { Expense, User } = require('../../models');
const { Op } = require("sequelize");
const { createLog } = require('../LogsController/logsController');

// ✅ Create new expense
exports.createExpense = async (req, res) => {
  try {
    const { type, amount, description, date, payment_method, payment_status, userId } = req.body;
    const imagePath = req.file ? `/uploads/expense_receipts/${req.file.filename}` : null;

    if (!type || !amount || !date) {
      return res.status(400).json({ error: "Type, amount, and date are required." });
    }

    // Create the new expense
    const expense = await Expense.create({
      type,
      amount,
      description,
      date,
      receipt_image_path: imagePath,
      payment_method,
      payment_status
    });

    res.status(201).json(expense);
  } catch (err) {
    console.error("Error creating expense:", err);
    res.status(500).json({ error: "Server error" });
  }
};


// ✅ Get all expenses (with optional date filter)
exports.getExpenses = async (req, res) => {
  try {
    const { from, to } = req.query;

    const where = {};
    if (from && to) {
      where.date = { [Op.between]: [from, to] };
    }

    const expenses = await Expense.findAll({
      where,
      order: [["date", "DESC"]],
    });

    res.json(expenses);
  } catch (err) {
    console.error("Error fetching expenses:", err);
    res.status(500).json({ error: "Server error" });
  }
};

// ✅ Get single expense by ID
exports.getExpenseById = async (req, res) => {
  try {
    const { id } = req.params;
    const expense = await Expense.findByPk(id);

    if (!expense) return res.status(404).json({ error: "Expense not found" });

    res.json(expense);
  } catch (err) {
    console.error("Error fetching expense:", err);
    res.status(500).json({ error: "Server error" });
  }
};


// ✅ Update expense by ID
exports.updateExpense = async (req, res) => {
  try {
    const { id } = req.params;
    const { type, amount, description, date, payment_method, payment_status, userId } = req.body;
    const imagePath = req.file ? `/uploads/expense_receipts/${req.file.filename}` : null;

    const expense = await Expense.findByPk(id);
    if (!expense) return res.status(404).json({ error: "Expense not found" });

    // Fetch user details for logging
    const user = await User.findByPk(userId);
    if (!user) {
      return res.status(404).json({ message: 'User not found' });
    }

    // Capture old values before the update
    const oldExpense = {
      type: expense.type,
      amount: expense.amount,
      description: expense.description,
      date: expense.date,
      payment_method: expense.payment_method,
      payment_status: expense.payment_status
    };

    // Update fields if provided
    expense.type = type ?? expense.type;
    expense.amount = amount ?? expense.amount;
    expense.description = description ?? expense.description;
    expense.date = date ?? expense.date;
    expense.payment_method = payment_method ?? expense.payment_method;
    expense.payment_status = payment_status ?? expense.payment_status;

    if (imagePath) {
      // Optional: Delete old image file if necessary
      expense.receipt_image_path = imagePath;
    }

    await expense.save();

    // Log the action: User updated the expense
    // await createLog(
    //   'Updated expense',                      // Action description
    //   userId,                                 // User ID who performed the action
    //   user.role,                              // User role (e.g., "admin", "manager")
    //   'expense',                              // Affected entity
    //   JSON.stringify(oldExpense),             // Old value (before the update)
    //   JSON.stringify({
    //     type: expense.type,
    //     amount: expense.amount,
    //     description: expense.description,
    //     date: expense.date,
    //     payment_method: expense.payment_method,
    //     payment_status: expense.payment_status
    //   }) // New value (after the update)
    // );

    res.json({ message: "Expense updated successfully", expense });
  } catch (err) {
    console.error("Error updating expense:", err);
    res.status(500).json({ error: "Server error" });
  }
};



// ✅ Delete expense by ID
exports.deleteExpense = async (req, res) => {
  try {
    const { id } = req.params;
    const expense = await Expense.findByPk(id);

    if (!expense) return res.status(404).json({ error: "Expense not found" });

    await expense.destroy();
    res.json({ message: "Expense deleted successfully" });
  } catch (err) {
    console.error("Error deleting expense:", err);
    res.status(500).json({ error: "Server error" });
  }
};
