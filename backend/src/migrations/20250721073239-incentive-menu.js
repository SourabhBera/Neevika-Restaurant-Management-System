'use strict';

module.exports = {
  up: async (queryInterface, Sequelize) => {
    await queryInterface.addColumn('Menus', 'isOffer', {
      type: Sequelize.BOOLEAN,
      defaultValue: false,
    });
    await queryInterface.addColumn('Menus', 'offerPrice', {
      type: Sequelize.FLOAT,
      allowNull: true,
    });
    await queryInterface.addColumn('Menus', 'waiterCommission', {
      type: Sequelize.FLOAT,
      allowNull: true,
    });
    await queryInterface.addColumn('Menus', 'commissionType', {
      type: Sequelize.ENUM('flat', 'percentage'),
      allowNull: true,
    });
  },

  down: async (queryInterface, Sequelize) => {
    await queryInterface.removeColumn('Menus', 'isOffer');
    await queryInterface.removeColumn('Menus', 'offerPrice');
    await queryInterface.removeColumn('Menus', 'waiterCommission');
    await queryInterface.removeColumn('Menus', 'commissionType');
  },
};
