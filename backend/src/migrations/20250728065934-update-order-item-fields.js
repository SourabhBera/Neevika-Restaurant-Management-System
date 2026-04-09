'use strict';

module.exports = {
  async up(queryInterface, Sequelize) {
    await Promise.all([
      queryInterface.changeColumn('OrderItems', 'menuId', {
        type: Sequelize.INTEGER,
        allowNull: true
      }),
      queryInterface.changeColumn('OrderItems', 'categoryId', {
        type: Sequelize.INTEGER,
        allowNull: true
      }),
      queryInterface.addColumn('OrderItems', 'desc', {
        type: Sequelize.TEXT,
        allowNull: true
      })
    ]);
  },

  async down(queryInterface, Sequelize) {
    await Promise.all([
      queryInterface.changeColumn('OrderItems', 'menuId', {
        type: Sequelize.INTEGER,
        allowNull: false
      }),
      queryInterface.changeColumn('OrderItems', 'categoryId', {
        type: Sequelize.INTEGER,
        allowNull: false
      }),
      queryInterface.removeColumn('OrderItems', 'desc')
    ]);
  }
};
