'use strict';

module.exports = {
  up: async (queryInterface, Sequelize) => {
    // Add indexes to DrinksCategories table
    await queryInterface.addIndex('DrinksCategories', ['name'], {
      name: 'drinks_category_name_idx'
    });

    // Add indexes to DrinksMenus table
    await queryInterface.addIndex('DrinksMenus', ['drinksCategoryId'], {
      name: 'drinks_menu_category_id_idx'
    });

    await queryInterface.addIndex('DrinksMenus', ['isUrgent', 'id'], {
      name: 'drinks_menu_urgent_id_idx'
    });

    await queryInterface.addIndex('DrinksMenus', ['isOffer'], {
      name: 'drinks_menu_is_offer_idx'
    });

    // Optional: index for isOutOfStock if needed
    await queryInterface.addIndex('DrinksMenus', ['isOutOfStock'], {
      name: 'drinks_menu_out_of_stock_idx'
    });

    // For PostgreSQL: index on LOWER(name)
    await queryInterface.sequelize.query(
      'CREATE INDEX drinks_menu_name_lower_idx ON "DrinksMenus" (LOWER(name));'
    );

    // For MySQL use instead:
    // await queryInterface.sequelize.query(
    //   'CREATE INDEX drinks_menu_name_lower_idx ON DrinksMenus ((LOWER(name)));'
    // );
  },

  down: async (queryInterface, Sequelize) => {
    await queryInterface.removeIndex('DrinksCategories', 'drinks_category_name_idx');
    await queryInterface.removeIndex('DrinksMenus', 'drinks_menu_category_id_idx');
    await queryInterface.removeIndex('DrinksMenus', 'drinks_menu_urgent_id_idx');
    await queryInterface.removeIndex('DrinksMenus', 'drinks_menu_is_offer_idx');
    await queryInterface.removeIndex('DrinksMenus', 'drinks_menu_out_of_stock_idx');
    await queryInterface.removeIndex('DrinksMenus', 'drinks_menu_name_lower_idx');
  }
};
