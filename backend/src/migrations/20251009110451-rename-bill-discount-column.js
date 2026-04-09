
'use strict';

/** @type {import('sequelize-cli').Migration} */
module.exports = {
  async up(queryInterface, Sequelize) {
    // First, check if the old column exists before removing (for safety)
    const tableDesc = await queryInterface.describeTable('Tables');

    if (tableDesc.bill_discount_percent) {
      await queryInterface.removeColumn('Tables', 'bill_discount_percent');
    }

    // Add the new JSON column
    await queryInterface.addColumn('Tables', 'bill_discount_details', {
      type: Sequelize.JSON,
      allowNull: true,
      defaultValue: null,
      comment: 'Stores discount info like { "type": "percent", "value": 10 } or { "type": "flat", "value": 200 }',
    });
  },

  async down(queryInterface, Sequelize) {
    // Revert: remove the JSON column and restore the old integer column
    const tableDesc = await queryInterface.describeTable('Tables');

    if (tableDesc.bill_discount_details) {
      await queryInterface.removeColumn('Tables', 'bill_discount_details');
    }

    await queryInterface.addColumn('Tables', 'bill_discount_percent', {
      type: Sequelize.INTEGER,
      allowNull: true,
    });
  },
};
