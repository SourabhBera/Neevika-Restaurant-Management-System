'use strict';

module.exports = {
  up: async (queryInterface, Sequelize) => {
    // 1. Make menuId nullable
    await queryInterface.changeColumn('Orders', 'menuId', {
      type: Sequelize.INTEGER,
      allowNull: true,
      references: {
        model: 'Menus',
        key: 'id',
      },
    });

    // 2. Add is_custom column
    await queryInterface.addColumn('Orders', 'is_custom', {
      type: Sequelize.BOOLEAN,
      allowNull: false,
      defaultValue: false,
    });
  },

  down: async (queryInterface, Sequelize) => {
    // 1. Revert menuId to NOT NULL
    await queryInterface.changeColumn('Orders', 'menuId', {
      type: Sequelize.INTEGER,
      allowNull: false,
      references: {
        model: 'Menus',
        key: 'id',
      },
    });

    // 2. Remove is_custom column
    await queryInterface.removeColumn('Orders', 'is_custom');
  }
};
