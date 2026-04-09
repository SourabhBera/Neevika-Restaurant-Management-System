'use strict';
module.exports = {
  async up(queryInterface, Sequelize) {
    await queryInterface.createTable('DaySummaries', {
      id: {
        allowNull: false,
        autoIncrement: true,
        primaryKey: true,
        type: Sequelize.INTEGER
      },
      date: {
        type: Sequelize.DATEONLY,
        unique: true,
        allowNull: false
      },
      orderCount: {
        type: Sequelize.INTEGER,
        defaultValue: 0
      },
      subTotal: {
        type: Sequelize.DECIMAL(10, 2),
        defaultValue: 0
      },
      discount: {
        type: Sequelize.DECIMAL(10, 2),
        defaultValue: 0
      },
      serviceCharges: {
        type: Sequelize.DECIMAL(10, 2),
        defaultValue: 0
      },
      tax: {
        type: Sequelize.DECIMAL(10, 2),
        defaultValue: 0
      },
      roundOff: {
        type: Sequelize.DECIMAL(10, 2),
        defaultValue: 0
      },
      grandTotal: {
        type: Sequelize.DECIMAL(10, 2),
        defaultValue: 0
      },
      netSales: {
        type: Sequelize.DECIMAL(10, 2),
        defaultValue: 0
      },
      cash: {
        type: Sequelize.DECIMAL(10, 2),
        defaultValue: 0
      },
      card: {
        type: Sequelize.DECIMAL(10, 2),
        defaultValue: 0
      },
      upi: {
        type: Sequelize.DECIMAL(10, 2),
        defaultValue: 0
      },
      createdAt: {
        allowNull: false,
        type: Sequelize.DATE,
        defaultValue: Sequelize.fn('NOW')
      },
      updatedAt: {
        allowNull: false,
        type: Sequelize.DATE,
        defaultValue: Sequelize.fn('NOW')
      }
    });
  },
  async down(queryInterface, Sequelize) {
    await queryInterface.dropTable('DaySummaries');
  }
};
