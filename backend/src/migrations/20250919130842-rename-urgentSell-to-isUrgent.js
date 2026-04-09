"use strict";

module.exports = {
  async up(queryInterface, Sequelize) {
    await queryInterface.renameColumn("DrinksMenus", "urgentSell", "isUrgent");
  },

  async down(queryInterface, Sequelize) {
    await queryInterface.renameColumn("DrinksMenus", "isUrgent", "urgentSell");
  },
};
