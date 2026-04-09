'use strict';

module.exports = {
  up: async (queryInterface, Sequelize) => {
    // 1. Remove old payment_method field
    await queryInterface.removeColumn('Bills', 'payment_method');

    // 2. Add new payment_breakdown JSON field
    await queryInterface.addColumn('Bills', 'payment_breakdown', {
      type: Sequelize.JSON,
      allowNull: false,
      defaultValue: {}, // e.g. { cash: 100, upi: 200 }
    });

    // 3. Add tip_amount field
    await queryInterface.addColumn('Bills', 'tip_amount', {
      type: Sequelize.FLOAT,
      allowNull: false,
      defaultValue: 0,
    });
  },

  down: async (queryInterface, Sequelize) => {
    // Revert the changes

    // 1. Add payment_method back
    await queryInterface.addColumn('Bills', 'payment_method', {
      type: Sequelize.ENUM('cash', 'card', 'upi'),
      allowNull: false,
      defaultValue: 'cash',
    });

    // 2. Remove payment_breakdown
    await queryInterface.removeColumn('Bills', 'payment_breakdown');

    // 3. Remove tip_amount
    await queryInterface.removeColumn('Bills', 'tip_amount');
  }
};
