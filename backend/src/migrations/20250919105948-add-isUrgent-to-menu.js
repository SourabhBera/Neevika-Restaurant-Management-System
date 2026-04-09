"use strict";

/** @type {import('sequelize-cli').Migration} */
module.exports = {
  up: async (queryInterface, Sequelize) => {
    await queryInterface.addColumn("Menus", "isUrgent", {
      type: Sequelize.BOOLEAN,
      defaultValue: false, // Default value for existing records
      allowNull: false, // Set as NOT NULL (optional, can be true if you'd prefer nullable)
    });
  },

  down: async (queryInterface, Sequelize) => {
    await queryInterface.removeColumn("Menus", "isUrgent");
  },
};
