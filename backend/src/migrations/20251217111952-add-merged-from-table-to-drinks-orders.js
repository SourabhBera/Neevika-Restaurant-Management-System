'use strict';

module.exports = {
  async up(queryInterface, Sequelize) {
    const tableDesc = await queryInterface.describeTable('DrinksOrders');

    // ✅ Only add column if it does NOT exist
    if (!tableDesc.merged_from_table) {
      await queryInterface.addColumn('DrinksOrders', 'merged_from_table', {
        type: Sequelize.INTEGER,
        allowNull: true,
        defaultValue: null,
        comment: 'ID of the table this order was originally from before merge',
      });
    }
  },

  async down(queryInterface, Sequelize) {
    const tableDesc = await queryInterface.describeTable('DrinksOrders');

    // ✅ Only remove column if it exists
    if (tableDesc.merged_from_table) {
      await queryInterface.removeColumn('DrinksOrders', 'merged_from_table');
    }
  },
};
