'use strict';

module.exports = {
  up: async (queryInterface, Sequelize) => {
    // Add indexes to Categories table
    await queryInterface.addIndex('Categories', ['name'], {
      name: 'category_name_idx'
    });

    // Add indexes to Menus table
    await queryInterface.addIndex('Menus', ['categoryId'], {
      name: 'menu_category_id_idx'
    });

    await queryInterface.addIndex('Menus', ['isUrgent', 'id'], {
      name: 'menu_urgent_id_idx'
    });

    await queryInterface.addIndex('Menus', ['isOffer'], {
      name: 'menu_is_offer_idx'
    });

    await queryInterface.addIndex('Menus', ['veg'], {
      name: 'menu_veg_idx'
    });

    // For PostgreSQL use this:
    await queryInterface.sequelize.query(
      'CREATE INDEX menu_name_lower_idx ON "Menus" (LOWER(name));'
    );

    // For MySQL use this instead:
    // await queryInterface.sequelize.query(
    //   'CREATE INDEX menu_name_lower_idx ON Menus ((LOWER(name)));'
    // );
  },

  down: async (queryInterface, Sequelize) => {
    await queryInterface.removeIndex('Categories', 'category_name_idx');
    await queryInterface.removeIndex('Menus', 'menu_category_id_idx');
    await queryInterface.removeIndex('Menus', 'menu_urgent_id_idx');
    await queryInterface.removeIndex('Menus', 'menu_is_offer_idx');
    await queryInterface.removeIndex('Menus', 'menu_veg_idx');
    await queryInterface.removeIndex('Menus', 'menu_name_lower_idx');
  }
};