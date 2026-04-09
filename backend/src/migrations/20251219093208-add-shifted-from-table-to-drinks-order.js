'use strict';

module.exports = {
  async up(queryInterface, Sequelize) {
    const tableDesc = await queryInterface.describeTable('DrinksOrders');

    // ✅ Column does NOT exist → ADD it
    if (!tableDesc.shifted_from_table) {
      await queryInterface.addColumn('DrinksOrders', 'shifted_from_table', {
        type: Sequelize.STRING,
        allowNull: true,
        defaultValue: null,
      });
    }
    // ✅ Column exists → ensure correct type
    else {
      await queryInterface.changeColumn('DrinksOrders', 'shifted_from_table', {
        type: Sequelize.STRING,
        allowNull: true,
        defaultValue: null,
      });
    }
  },

  async down(queryInterface, Sequelize) {
    const tableDesc = await queryInterface.describeTable('DrinksOrders');

    if (tableDesc.shifted_from_table) {
      await queryInterface.removeColumn('DrinksOrders', 'shifted_from_table');
    }
  },
};
