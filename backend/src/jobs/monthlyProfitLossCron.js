const cron = require('node-cron');
const { Op, fn, col } = require('sequelize');
const { ProfitLoss, Bill, Expense, PurchaseHistory, Payroll } = require('../models');

const IST_OFFSET = 5.5 * 60; // IST offset in minutes

const generateMonthlyProfitLoss = async () => {
  try {
    const now = new Date();
    const nowUTC = new Date(now.getTime() + now.getTimezoneOffset() * 60000);
    const nowIST = new Date(nowUTC.getTime() + IST_OFFSET * 60000);

    // Get the previous month (in case cron runs on 1st)
    const year = nowIST.getMonth() === 0 ? nowIST.getFullYear() - 1 : nowIST.getFullYear();
    const month = nowIST.getMonth() === 0 ? 12 : nowIST.getMonth(); // 1–12

    const summaryDate = `${year}-${String(month).padStart(2, '0')}`; // e.g., "2025-05"

    const startOfMonth = new Date(`${summaryDate}-01T00:00:00.000Z`);
    const endOfMonth = new Date(new Date(startOfMonth).setMonth(startOfMonth.getMonth() + 1));

    const exists = await ProfitLoss.findOne({ where: { date: summaryDate } });
    if (exists) {
      console.log(`📌 Profit & Loss for ${summaryDate} already exists.`);
      return;
    }

    // Total Sales
    const billResult = await Bill.findAll({
      where: { time_of_bill: { [Op.between]: [startOfMonth, endOfMonth] } },
      attributes: [[fn('SUM', col('final_amount')), 'total_sales']],
      raw: true,
    });
    const totalSales = parseFloat(billResult[0].total_sales || 0);

    // Total Expenses
    const expenseResult = await Expense.findAll({
      where: {
        date: { [Op.between]: [startOfMonth, endOfMonth] }
      },
      attributes: [[fn('SUM', col('amount')), 'total_expenses']],
      raw: true,
    });
    const totalExpenses = parseFloat(expenseResult[0].total_expenses || 0);

    // Total Purchases
    const purchaseResult = await PurchaseHistory.findAll({
      where: {
        date: { [Op.between]: [startOfMonth, endOfMonth] },
        payment_status: 'complete'
      },
      attributes: [[fn('SUM', col('amount')), 'purchase_amount']],
      raw: true,
    });
    const purchaseAmount = parseFloat(purchaseResult[0].purchase_amount || 0);

    // Total Payroll
    const payrollResult = await Payroll.findAll({
      where: {
        month: summaryDate,
        payment_status: 'paid'
      },
      attributes: [[fn('SUM', col('net_salary')), 'payroll_amount']],
      raw: true,
    });
    const payrollAmount = parseFloat(payrollResult[0].payroll_amount || 0);

    const totalOutflow = totalExpenses + purchaseAmount + payrollAmount;
    const profit = totalSales - totalOutflow;
    const status = profit >= 0 ? 'Profit' : 'Loss';

    await ProfitLoss.create({
      date: summaryDate,
      total_sales: totalSales,
      total_expenses: totalExpenses,
      purchase_amount: purchaseAmount,
      payroll_amount: payrollAmount,
      profit,
      status,
    });

    console.log(`✅ Profit & Loss for ${summaryDate} saved: ₹${profit.toFixed(2)} (${status})`);
  } catch (err) {
    console.error('❌ Error generating monthly profit/loss:', err);
  }
};

// Run every day at 9:45 PM UTC (3:15 AM IST). Only generate if it's 1st IST.
cron.schedule('45 21 * * *', async () => {
  const now = new Date();
  const istTime = new Date(now.getTime() + (330 + now.getTimezoneOffset()) * 60000);
  if (istTime.getDate() === 1) {
    await generateMonthlyProfitLoss();
  }
});

module.exports = generateMonthlyProfitLoss;
