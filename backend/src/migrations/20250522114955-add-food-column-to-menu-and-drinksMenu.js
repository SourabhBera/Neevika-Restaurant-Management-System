module.exports = {
  up: async (queryInterface, Sequelize) => {
    // Add 'food' column to 'Menus'
    await queryInterface.addColumn('Menus', 'food', {
      type: Sequelize.BOOLEAN,
      allowNull: false,
      defaultValue: true, // Default value for Menu items (food)
    });

    // Add 'food' column to 'DrinksMenu'
    await queryInterface.addColumn('DrinksMenus', 'food', {
      type: Sequelize.BOOLEAN,
      allowNull: false,
      defaultValue: false, // Default value for DrinksMenu items (drinks)
    });
  },

  down: async (queryInterface, Sequelize) => {
    // Remove 'food' column from 'Menus'
    await queryInterface.removeColumn('Menus', 'food');

    // Remove 'food' column from 'DrinksMenus'
    await queryInterface.removeColumn('DrinksMenus', 'food');
  }
};
