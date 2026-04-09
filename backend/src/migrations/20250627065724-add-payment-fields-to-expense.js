'use strict';

module.exports = {
  up: async (queryInterface, Sequelize) => {
    await queryInterface.addColumn('Expenses', 'payment_method', {
      type: Sequelize.STRING,
      allowNull: true,
    });

    await queryInterface.addColumn('Expenses', 'payment_status', {
      type: Sequelize.STRING,
      allowNull: true,
    });
  },

  down: async (queryInterface, Sequelize) => {
    await queryInterface.removeColumn('Expenses', 'payment_method');
    await queryInterface.removeColumn('Expenses', 'payment_status');
  }
};
