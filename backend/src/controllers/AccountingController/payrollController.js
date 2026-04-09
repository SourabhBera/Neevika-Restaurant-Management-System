const { Payroll, User, Attendance } = require('../../models');
const { Op } = require('sequelize');
const moment = require('moment');
const { createLog } = require('../LogsController/logsController');
  
// 📌 Create payroll entries for all employees for a given month

exports.createPayrollForMonth = async (req, res) => {
  try {
    const { month } = req.body;

    if (!month) {
      return res.status(400).json({ error: 'Month is required (format: YYYY-MM)' });
    }

    const existingPayrolls = await Payroll.findAll({ where: { month } });

    if (existingPayrolls.length > 0) {
      return res.status(409).json({ error: 'Payroll already generated for this month' });
    }

    const employees = await User.findAll();

    const startDate = moment(month, 'YYYY-MM').startOf('month').toDate();
    const endDate = moment(month, 'YYYY-MM').endOf('month').toDate();
    const totalDaysInMonth = moment(month, 'YYYY-MM').daysInMonth();

    const payrollData = [];

    for (const emp of employees) {
      const base = emp.salary || 0;

      // Get 'present' attendance records for this employee for the month
      const presentDays = await Attendance.count({
        where: {
          employee_id: emp.id,
          status: 'present',
          date: {
            [Op.between]: [startDate, endDate]
          }
        }
      });

      const absentDays = totalDaysInMonth - presentDays;
      const perDaySalary = base / totalDaysInMonth;
      const deduction = perDaySalary * absentDays;

      payrollData.push({
        employee_id: emp.id,
        month,
        base_salary: base,
        bonus: 0,
        deductions: deduction,
        net_salary: base - deduction,
        payment_status: 'Pending'
      });
    }

    await Payroll.bulkCreate(payrollData);

    res.status(201).json({ message: 'Payroll generated for all employees with attendance deductions.' });

  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Error generating payroll.' });
  }
};

// 📌 Get all payrolls (optionally filtered by month or employee)
exports.getPayrolls = async (req, res) => {
  try {
    const { month, employee_id } = req.query;
    const where = {};

    if (month) where.month = month;
    if (employee_id) where.employee_id = employee_id;

    const payrolls = await Payroll.findAll({
      where,
      include: [{ model: User, as: 'employee' }],
      order: [['month', 'DESC']]
    });

    res.json(payrolls);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Error fetching payrolls.' });
  }
};


// 📌 Update payroll record (bonus, deductions, status, payment details)
exports.updatePayroll = async (req, res) => {
  try {
    const { id } = req.params;
    const {
      bonus,
      deductions,
      payment_status,
      payment_method,
      paid_at,
      notes,
      receipt_image,
      userId
    } = req.body;

    const payroll = await Payroll.findByPk(id);
    if (!payroll) return res.status(404).json({ error: 'Payroll not found' });

    // Fetch user details for logging
    const user = await User.findByPk(userId);
    if (!user) {
      return res.status(404).json({ message: 'User not found' });
    }

    // Capture old values before update
    const oldPayroll = {
      bonus: payroll.bonus,
      deductions: payroll.deductions,
      net_salary: payroll.net_salary,
      payment_status: payroll.payment_status,
      payment_method: payroll.payment_method,
      paid_at: payroll.paid_at,
      notes: payroll.notes,
      receipt_image: payroll.receipt_image
    };

    // Update fields if provided
    if (bonus !== undefined) payroll.bonus = bonus;
    if (deductions !== undefined) payroll.deductions = deductions;
    payroll.net_salary = (payroll.base_salary || 0) + (payroll.bonus || 0) - (payroll.deductions || 0);

    if (payment_status) payroll.payment_status = payment_status;
    if (payment_method) payroll.payment_method = payment_method;
    if (paid_at) payroll.paid_at = paid_at;
    if (notes) payroll.notes = notes;
    if (receipt_image) payroll.receipt_image = receipt_image;

    await payroll.save();

    // Log the action: User updated a payroll record
    await createLog(
      'Updated payroll record',                // Action description
      userId,                                  // User ID who performed the action
      user.role,                               // User role (e.g., "admin", "manager")
      'payroll',                               // Affected entity
      JSON.stringify(oldPayroll),              // Old value (before update)
      JSON.stringify({
        bonus: payroll.bonus,
        deductions: payroll.deductions,
        net_salary: payroll.net_salary,
        payment_status: payroll.payment_status,
        payment_method: payroll.payment_method,
        paid_at: payroll.paid_at,
        notes: payroll.notes,
        receipt_image: payroll.receipt_image
      }) // New value (after update)
    );

    res.json({ message: 'Payroll updated', payroll });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Error updating payroll.' });
  }
};

// 📌 Delete a payroll record (optional)
exports.deletePayroll = async (req, res) => {
  try {
    const { id } = req.params;

    const deleted = await Payroll.destroy({ where: { id } });
    if (!deleted) return res.status(404).json({ error: 'Payroll not found' });

    res.json({ message: 'Payroll record deleted.' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Error deleting payroll.' });
  }
};
