'use strict';

module.exports = {
  up: async (queryInterface, Sequelize) => {
    await queryInterface.createTable('DrinksOrders', {
      id: {
        type: Sequelize.INTEGER,
        allowNull: false,
        autoIncrement: true,
        primaryKey: true,
      },
      userId: {
        type: Sequelize.INTEGER,
        allowNull: false,
        references: {
          model: 'Users', // Assuming you have a 'Users' table
          key: 'id',
        },
        onDelete: 'CASCADE',
      },
      drinksMenuId: {
        type: Sequelize.INTEGER,
        allowNull: false,
        references: {
          model: 'DrinksMenus', // Assuming you have a 'DrinksMenus' table
          key: 'id',
        },
        onDelete: 'CASCADE',
      },
      item_desc: {
        type: Sequelize.STRING,
        allowNull: true,
      },
      quantity: {
        type: Sequelize.INTEGER,
        allowNull: false,
      },
      status: {
        type: Sequelize.STRING,
        defaultValue: 'pending',
      },
      amount: {
        type: Sequelize.FLOAT,
        allowNull: false,
      },
      table_number: {
        type: Sequelize.INTEGER,
        allowNull: true,
      },
      section_number: {
        type: Sequelize.INTEGER,
        allowNull: true,
      },
      restaurant_table_number: {
        type: Sequelize.INTEGER,
        allowNull: true,
      },
      createdAt: {
        type: Sequelize.DATE,
        allowNull: false,
        defaultValue: Sequelize.fn('now'),
      },
      updatedAt: {
        type: Sequelize.DATE,
        allowNull: false,
        defaultValue: Sequelize.fn('now'),
      },
    });
  },

  down: async (queryInterface, Sequelize) => {
    await queryInterface.dropTable('DrinksOrders');
  },
};
