const { ProfitLoss, Bill, Expense, Payroll, PurchaseHistory } = require('../../models');
const { Op, fn, col } = require('sequelize');
const ExcelJS = require('exceljs');

module.exports = {
  // GET all profit & loss summaries
  async getAll(req, res) {
    try {
      const summaries = await ProfitLoss.findAll({ order: [['date', 'DESC']] });
      res.status(200).json(summaries);
    } catch (err) {
      console.error('Error fetching profit/loss:', err);
      res.status(500).json({ error: 'Internal Server Error' });
    }
  },

  // GET single entry by date (YYYY-MM)
  async getByDate(req, res) {
    const { date } = req.params; // e.g., '2025-05'
    try {
      const entry = await ProfitLoss.findOne({ where: { date } });
      if (!entry) return res.status(404).json({ error: 'Not found' });
      res.status(200).json(entry);
    } catch (err) {
      console.error('Error fetching entry:', err);
      res.status(500).json({ error: 'Internal Server Error' });
    }
  },

  // CREATE or RE-GENERATE a summary for a month
  async generateMonthly(req, res) {
    const { date } = req.body; // 'YYYY-MM'

    if (!date) return res.status(400).json({ error: 'Missing date in format YYYY-MM' });

    try {
      // Remove existing
      await ProfitLoss.destroy({ where: { date } });

      const [year, month] = date.split('-').map(Number);
      const startOfMonth = new Date(`${year}-${String(month).padStart(2, '0')}-01T00:00:00Z`);
      const endOfMonth = new Date(new Date(startOfMonth).setMonth(startOfMonth.getMonth() + 1));
      endOfMonth.setMilliseconds(-1);

      const [salesResult] = await Bill.findAll({
        where: { createdAt: { [Op.between]: [startOfMonth, endOfMonth] } },
        attributes: [[fn('SUM', col('final_amount')), 'total_sales']],
        raw: true
      });

      const [expenseResult] = await Expense.findAll({
        where: { date: { [Op.between]: [startOfMonth, endOfMonth] } },
        attributes: [[fn('SUM', col('amount')), 'total_expenses']],
        raw: true
      });

      const [purchaseResult] = await PurchaseHistory.findAll({
        where: { date: { [Op.between]: [startOfMonth, endOfMonth] } },
        attributes: [[fn('SUM', col('amount')), 'purchase_amount']],
        raw: true
      });

      const payrollResult = await Payroll.findAll({
        where: {
            month: `${year}-${String(month).padStart(2, '0')}`, // match exact month string
        },
        attributes: [[fn('SUM', col('net_salary')), 'payroll_amount']],
        raw: true
      });

      const totalSales = parseFloat(salesResult.total_sales || 0);
      const totalExpenses = parseFloat(expenseResult.total_expenses || 0);
      const purchaseAmount = parseFloat(purchaseResult.purchase_amount || 0);
      const payrollAmount = parseFloat(payrollResult.payroll_amount || 0);

      const totalCost = totalExpenses + purchaseAmount + payrollAmount;
      const profit = totalSales - totalCost;

      const summary = await ProfitLoss.create({
        date,
        total_sales: totalSales,
        total_expenses: totalExpenses + payrollAmount, // include payroll in expenses
        purchase_amount: purchaseAmount,
        profit,
        status: profit >= 0 ? 'Profit' : 'Loss',
      });

      res.status(201).json(summary);
    } catch (err) {
      console.error('Error generating summary:', err);
      res.status(500).json({ error: 'Internal Server Error' });
    }
  },

  // DELETE by date
  async delete(req, res) {
    const { date } = req.params;
    try {
      const deleted = await ProfitLoss.destroy({ where: { date } });
      if (!deleted) return res.status(404).json({ error: 'Not found' });
      res.status(200).json({ message: 'Deleted successfully' });
    } catch (err) {
      console.error('Error deleting entry:', err);
      res.status(500).json({ error: 'Internal Server Error' });
    }
  },

  // DOWNLOAD as Excel
  async downloadExcel(req, res) {
    try {
      const summaries = await ProfitLoss.findAll({ order: [['date', 'DESC']] });

      const workbook = new ExcelJS.Workbook();
      const worksheet = workbook.addWorksheet('ProfitLoss');

      worksheet.columns = [
        { header: 'Date', key: 'date', width: 15 },
        { header: 'Total Sales', key: 'total_sales', width: 15 },
        { header: 'Total Expenses', key: 'total_expenses', width: 18 },
        { header: 'Purchase Amount', key: 'purchase_amount', width: 18 },
        { header: 'Profit', key: 'profit', width: 15 },
        { header: 'Status', key: 'status', width: 12 },
        { header: 'Created At', key: 'createdAt', width: 20 },
      ];

      summaries.forEach(entry => {
        worksheet.addRow(entry.toJSON());
      });

      res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      res.setHeader('Content-Disposition', 'attachment; filename=profit_loss.xlsx');
      await workbook.xlsx.write(res);
      res.status(200).end();
    } catch (error) {
      console.error('Error exporting profit/loss:', error);
      res.status(500).json({ message: 'Error exporting', error: error.message });
    }
  }
};
