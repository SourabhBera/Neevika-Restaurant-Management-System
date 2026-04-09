"use strict";

module.exports = {
  async up(queryInterface, Sequelize) {
    // 1️⃣ Make menuId nullable
    await queryInterface.changeColumn("CanceledFoodOrders", "menuId", {
      type: Sequelize.INTEGER,
      allowNull: true,
      references: {
        model: "Menus",
        key: "id",
      },
    });

    // 2️⃣ Add is_custom field
    await queryInterface.addColumn("CanceledFoodOrders", "is_custom", {
      type: Sequelize.BOOLEAN,
      allowNull: false,
      defaultValue: false,
    });

    // 3️⃣ Add customName field
    await queryInterface.addColumn("CanceledFoodOrders", "customName", {
      type: Sequelize.STRING,
      allowNull: true,
    });
  },

  async down(queryInterface, Sequelize) {
    // Rollback changes
    await queryInterface.changeColumn("CanceledFoodOrders", "menuId", {
      type: Sequelize.INTEGER,
      allowNull: false,
      references: {
        model: "Menus",
        key: "id",
      },
    });

    await queryInterface.removeColumn("CanceledFoodOrders", "is_custom");
    await queryInterface.removeColumn("CanceledFoodOrders", "customName");
  },
};
