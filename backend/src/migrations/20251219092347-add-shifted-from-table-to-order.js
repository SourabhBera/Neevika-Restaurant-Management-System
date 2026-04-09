'use strict';

module.exports = {
  async up(queryInterface, Sequelize) {
    const tableDesc = await queryInterface.describeTable('Orders');

    // ✅ Column does NOT exist → ADD it
    if (!tableDesc.shifted_from_table) {
      await queryInterface.addColumn('Orders', 'shifted_from_table', {
        type: Sequelize.STRING,
        allowNull: true,
        defaultValue: null,
      });
    }
    // ✅ Column exists → ensure correct type
    else {
      await queryInterface.changeColumn('Orders', 'shifted_from_table', {
        type: Sequelize.STRING,
        allowNull: true,
        defaultValue: null,
      });
    }
  },

  async down(queryInterface, Sequelize) {
    const tableDesc = await queryInterface.describeTable('Orders');

    if (tableDesc.shifted_from_table) {
      await queryInterface.removeColumn('Orders', 'shifted_from_table');
    }
  },
};
