// migrations/YYYYMMDDHHMMSS-add-bottle-size-to-drinks-inventory.js

module.exports = {
  up: async (queryInterface, Sequelize) => {
    // Add the bottleSize column to the existing DrinksInventories table
    await queryInterface.addColumn('DrinksInventories', 'bottleSize', {
      type: Sequelize.FLOAT,
      allowNull: true,  // This is optional; can be set to false if required
    });
  },

  down: async (queryInterface, Sequelize) => {
    // Remove the bottleSize column if the migration is rolled back
    await queryInterface.removeColumn('DrinksInventories', 'bottleSize');
  },
};
