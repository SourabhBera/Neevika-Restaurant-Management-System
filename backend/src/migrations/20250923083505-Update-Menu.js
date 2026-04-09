'use strict';

module.exports = {
  up: async (queryInterface, Sequelize) => {
    await Promise.all([
      queryInterface.addColumn('Menus', 'quantity', {
        type: Sequelize.INTEGER,
        allowNull: false,
        defaultValue: 0,
      }),
      queryInterface.addColumn('Menus', 'editedBy', {
        type: Sequelize.INTEGER,
        allowNull: true,
        references: {
          model: 'User_roles', // matches the tableName in User_role model
          key: 'id',
        },
        onUpdate: 'CASCADE',
        onDelete: 'SET NULL',
      }),
      queryInterface.addColumn('Menus', 'kotCategory', {
        type: Sequelize.STRING,
        allowNull: true,
      }),
    ]);
  },

  down: async (queryInterface, Sequelize) => {
    await Promise.all([
      queryInterface.removeColumn('Menus', 'quantity'),
      queryInterface.removeColumn('Menus', 'editedBy'),
      queryInterface.removeColumn('Menus', 'kotCategory'),
    ]);
  },
};
