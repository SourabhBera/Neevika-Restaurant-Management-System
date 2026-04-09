'use strict';

module.exports = {
  up: async (queryInterface, Sequelize) => {
    return queryInterface.renameColumn('DrinksMenuIngredients', 'ingredientId', 'inventoryId');
  },

  down: async (queryInterface, Sequelize) => {
    return queryInterface.renameColumn('DrinksMenuIngredients', 'inventoryId', 'ingredientId');
  }
};
