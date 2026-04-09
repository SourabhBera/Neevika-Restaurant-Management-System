'use strict';

/**
 * Migration: add merged_from_table to Orders & DrinksOrders, and merged_at to Tables
 */
module.exports = {
  up: async (queryInterface, Sequelize) => {
    // Orders: add merged_from_table
    await queryInterface.addColumn('Orders', 'merged_from_table', {
      type: Sequelize.INTEGER,
      allowNull: true,
      defaultValue: null,
    });

    // DrinksOrders: add merged_from_table
    await queryInterface.addColumn('DrinksOrders', 'merged_from_table', {
      type: Sequelize.INTEGER,
      allowNull: true,
      defaultValue: null,
    });

    // Tables: add merged_at timestamp
    await queryInterface.addColumn('Tables', 'merged_at', {
      type: Sequelize.DATE,
      allowNull: true,
      defaultValue: null,
    });
  },

  down: async (queryInterface, Sequelize) => {
    // rollback in reverse order
    await queryInterface.removeColumn('Tables', 'merged_at');
    await queryInterface.removeColumn('DrinksOrders', 'merged_from_table');
    await queryInterface.removeColumn('Orders', 'merged_from_table');
  },
};
