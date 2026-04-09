'use strict';

module.exports = {
  up: async (queryInterface, Sequelize) => {
    await queryInterface.addColumn('OrderItems', 'categoryId', {
      type: Sequelize.INTEGER,
      allowNull: true, // or false if required
      references: {
        model: 'Categories', // name of the related table
        key: 'id'
      },
      onUpdate: 'CASCADE',
      onDelete: 'SET NULL' // or 'CASCADE' based on your need
    });
  },

  down: async (queryInterface, Sequelize) => {
    await queryInterface.removeColumn('OrderItems', 'categoryId');
  }
};
