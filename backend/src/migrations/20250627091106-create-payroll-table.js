'use strict';
module.exports = {
  up: async (queryInterface, Sequelize) => {
    await queryInterface.createTable('Payrolls', {
      id: {
        allowNull: false,
        autoIncrement: true,
        primaryKey: true,
        type: Sequelize.INTEGER,
      },
      employee_id: {
        type: Sequelize.INTEGER,
        allowNull: false,
        references: {
          model: 'Users',
          key: 'id',
        },
        onDelete: 'CASCADE',
      },
      month: {
        type: Sequelize.STRING,
        allowNull: false,
      },
      base_salary: {
        type: Sequelize.FLOAT,
        allowNull: false,
        defaultValue: 0,
      },
      bonus: {
        type: Sequelize.FLOAT,
        allowNull: false,
        defaultValue: 0,
      },
      deductions: {
        type: Sequelize.FLOAT,
        allowNull: false,
        defaultValue: 0,
      },
      net_salary: {
        type: Sequelize.FLOAT,
        allowNull: false,
        defaultValue: 0,
      },
      payment_status: {
        type: Sequelize.ENUM('Pending', 'Paid'),
        allowNull: false,
        defaultValue: 'Pending',
      },
      payment_method: {
        type: Sequelize.ENUM('Cash', 'UPI', 'Bank', 'Cheque'),
        allowNull: true,
      },
      paid_at: {
        type: Sequelize.DATE,
        allowNull: true,
      },
      notes: {
        type: Sequelize.TEXT,
        allowNull: true,
      },
      receipt_image: {
        type: Sequelize.STRING,
        allowNull: true,
      },
      createdAt: {
        allowNull: false,
        type: Sequelize.DATE,
        defaultValue: Sequelize.literal('NOW()'),
      },
      updatedAt: {
        allowNull: false,
        type: Sequelize.DATE,
        defaultValue: Sequelize.literal('NOW()'),
      },
    });
  },

  down: async (queryInterface, Sequelize) => {
    await queryInterface.dropTable('Payrolls');
  },
};
