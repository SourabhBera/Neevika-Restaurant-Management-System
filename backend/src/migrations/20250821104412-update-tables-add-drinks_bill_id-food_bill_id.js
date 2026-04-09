'use strict';

module.exports = {
  up: async (queryInterface, Sequelize) => {
    // Rename 'bill_id' to 'food_bill_id'
    await queryInterface.renameColumn('Tables', 'bill_id', 'food_bill_id');

    // Add 'drinks_bill_id'
    await queryInterface.addColumn('Tables', 'drinks_bill_id', {
      type: Sequelize.INTEGER,
      allowNull: true,
    });
  },

  down: async (queryInterface, Sequelize) => {
    // Revert 'food_bill_id' back to 'bill_id'
    await queryInterface.renameColumn('Tables', 'food_bill_id', 'bill_id');

    // Remove 'drinks_bill_id'
    await queryInterface.removeColumn('Tables', 'drinks_bill_id');
  },
};
