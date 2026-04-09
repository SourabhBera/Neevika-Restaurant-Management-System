const cron = require('node-cron');
const { Op } = require('sequelize');
const moment = require('moment');
const { User, Attendance, Payroll } = require('../models'); // Adjust based on your structure

const IST_OFFSET = 5.5 * 60 * 60000; // IST in milliseconds

const generateMonthlyPayroll = async () => {
  try {
    // Get current UTC date/time
    const nowUTC = new Date();

    // Convert to IST
    const nowIST = new Date(nowUTC.getTime() + IST_OFFSET);

    // Get previous month in 'YYYY-MM' format
    const previousMonth = moment(nowIST).subtract(1, 'month').format('YYYY-MM');

    // Check if payroll already exists
    const existingPayrolls = await Payroll.findAll({ where: { month: previousMonth } });

    if (existingPayrolls.length > 0) {
      console.log(`⚠️ Payroll already exists for ${previousMonth}`);
      return;
    }

    const employees = await User.findAll();

    const startDate = moment(previousMonth, 'YYYY-MM').startOf('month').toDate();
    const endDate = moment(previousMonth, 'YYYY-MM').endOf('month').toDate();
    const totalDaysInMonth = moment(previousMonth, 'YYYY-MM').daysInMonth();

    const payrollData = [];

    for (const emp of employees) {
      const base = emp.salary || 0;

      const presentDays = await Attendance.count({
        where: {
          employee_id: emp.id,
          status: 'present',
          date: {
            [Op.between]: [startDate, endDate],
          },
        },
      });

      const absentDays = totalDaysInMonth - presentDays;
      const perDaySalary = base / totalDaysInMonth;
      const deduction = perDaySalary * absentDays;

      payrollData.push({
        employee_id: emp.id,
        month: previousMonth,
        base_salary: base,
        bonus: 0,
        deductions: deduction,
        net_salary: base - deduction,
        payment_status: 'Pending',
      });
    }

    await Payroll.bulkCreate(payrollData);

    console.log(`✅ Payroll generated for month: ${previousMonth}`);
  } catch (err) {
    console.error('❌ Error generating monthly payroll:', err);
  }
};

// Schedule to run at 3:00 AM IST on the 8th day of every month
cron.schedule('0 3 8 * *', () => {
  generateMonthlyPayroll();
}, {
  timezone: 'Asia/Kolkata'
});