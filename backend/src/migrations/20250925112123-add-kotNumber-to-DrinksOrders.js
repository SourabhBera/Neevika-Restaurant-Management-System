'use strict';

module.exports = {
  up: async (queryInterface, Sequelize) => {
    await queryInterface.addColumn('DrinksOrders', 'kotNumber', {
      type: Sequelize.INTEGER,
      allowNull: true, // or false if required
    });
  },

  down: async (queryInterface, Sequelize) => {
    await queryInterface.removeColumn('DrinksOrders', 'kotNumber');
  },
};
