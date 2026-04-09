'use strict';

module.exports = {
  async up(queryInterface, Sequelize) {
    await queryInterface.addColumn('DrinksInventories', 'baseUnitQuantity', {
      type: Sequelize.FLOAT,
      allowNull: false,
      defaultValue: 0
    });

    await queryInterface.addColumn('DrinksKitchenInventories', 'baseUnitQuantity', {
      type: Sequelize.FLOAT,
      allowNull: false,
      defaultValue: 0
    });
  },

  async down(queryInterface, Sequelize) {
    await queryInterface.removeColumn('DrinksInventories', 'baseUnitQuantity');
    await queryInterface.removeColumn('DrinksKitchenInventories', 'baseUnitQuantity');
  }
};
