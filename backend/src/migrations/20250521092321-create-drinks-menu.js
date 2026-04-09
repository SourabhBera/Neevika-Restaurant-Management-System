// migrations/XXXXXX-create-drinks-menu.js
module.exports = {
  up: async (queryInterface, Sequelize) => {
    await queryInterface.createTable('DrinksMenus', {
      id: {
        type: Sequelize.INTEGER,
        allowNull: false,
        autoIncrement: true,
        primaryKey: true,
      },
      name: {
        type: Sequelize.STRING,
        allowNull: false,
      },
      price: {
        type: Sequelize.DECIMAL,
        allowNull: false,
      },
      drinksCategoryId: {
        type: Sequelize.INTEGER,
        allowNull: false,
        references: {
          model: 'DrinksCategories', // This references the DrinksCategories table
          key: 'id',
        },
        onDelete: 'CASCADE', // Optional: cascade delete if category is deleted
      },
      createdAt: {
        type: Sequelize.DATE,
        allowNull: false,
      },
      updatedAt: {
        type: Sequelize.DATE,
        allowNull: false,
      },
    });
  },

  down: async (queryInterface, Sequelize) => {
    await queryInterface.dropTable('DrinksMenus');
  },
};
