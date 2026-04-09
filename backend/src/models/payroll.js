'use strict';
module.exports = (sequelize, DataTypes) => {
  const Payroll = sequelize.define('Payroll', {
    employee_id: {
      type: DataTypes.INTEGER,
      allowNull: false,
    },
    month: {
      type: DataTypes.STRING, // format: "YYYY-MM"
      allowNull: false,
    },
    base_salary: {
      type: DataTypes.FLOAT,
      allowNull: false,
      defaultValue: 0,
    },
    bonus: {
      type: DataTypes.FLOAT,
      allowNull: false,
      defaultValue: 0,
    },
    deductions: {
      type: DataTypes.FLOAT,
      allowNull: false,
      defaultValue: 0,
    },
    net_salary: {
      type: DataTypes.FLOAT,
      allowNull: false,
      defaultValue: 0,
    },
    payment_status: {
      type: DataTypes.ENUM('Pending', 'Paid'),
      allowNull: false,
      defaultValue: 'Pending',
    },
    payment_method: {
      type: DataTypes.ENUM('Cash', 'UPI', 'Bank', 'Cheque'),
      allowNull: true,
    },
    paid_at: {
      type: DataTypes.DATE,
      allowNull: true,
    },
    notes: {
      type: DataTypes.TEXT,
      allowNull: true,
    },
    receipt_image: {
      type: DataTypes.STRING,
      allowNull: true,
    }
  }, {
    tableName: 'Payrolls'
  });

  Payroll.associate = function(models) {
    Payroll.belongsTo(models.User, {
        foreignKey: 'employee_id',
        as: 'employee',
        onDelete: 'CASCADE'
    });

  };

  return Payroll;
};
