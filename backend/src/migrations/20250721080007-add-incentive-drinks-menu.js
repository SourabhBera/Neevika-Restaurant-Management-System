'use strict';

module.exports = {
  up: async (queryInterface, Sequelize) => {
    await queryInterface.addColumn('DrinksMenus', 'isOffer', {
      type: Sequelize.BOOLEAN,
      defaultValue: false,
    });
    await queryInterface.addColumn('DrinksMenus', 'offerPrice', {
      type: Sequelize.FLOAT,
      allowNull: true,
    });
    await queryInterface.addColumn('DrinksMenus', 'waiterCommission', {
      type: Sequelize.FLOAT,
      allowNull: true,
    });
    await queryInterface.addColumn('DrinksMenus', 'commissionType', {
      type: Sequelize.ENUM('flat', 'percentage'),
      allowNull: true,
    });
  },

  down: async (queryInterface, Sequelize) => {
    await queryInterface.removeColumn('DrinksMenus', 'isOffer');
    await queryInterface.removeColumn('DrinksMenus', 'offerPrice');
    await queryInterface.removeColumn('DrinksMenus', 'waiterCommission');
    await queryInterface.removeColumn('DrinksMenus', 'commissionType');
  },
};
