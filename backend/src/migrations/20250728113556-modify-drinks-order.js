'use strict';

module.exports = {
  up: async (queryInterface, Sequelize) => {
    await Promise.all([
      queryInterface.changeColumn('DrinksOrders', 'drinksMenuId', {
        type: Sequelize.INTEGER,
        allowNull: true,
        references: {
          model: 'DrinksMenus',
          key: 'id',
        },
      }),
      queryInterface.addColumn('DrinksOrders', 'is_custom', {
        type: Sequelize.BOOLEAN,
        allowNull: false,
        defaultValue: false,
      }),
    ]);
  },

  down: async (queryInterface, Sequelize) => {
    await Promise.all([
      queryInterface.changeColumn('DrinksOrders', 'drinksMenuId', {
        type: Sequelize.INTEGER,
        allowNull: false,
        references: {
          model: 'DrinksMenus',
          key: 'id',
        },
      }),
      queryInterface.removeColumn('DrinksOrders', 'is_custom'),
    ]);
  },
};
