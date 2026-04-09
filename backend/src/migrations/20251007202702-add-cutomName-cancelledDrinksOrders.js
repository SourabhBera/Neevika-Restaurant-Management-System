"use strict";

module.exports = {
  async up(queryInterface, Sequelize) {
    // 1️⃣ Make drinksMenuId nullable
    await queryInterface.changeColumn("CanceledDrinkOrders", "drinksMenuId", {
      type: Sequelize.INTEGER,
      allowNull: true,
      references: {
        model: "DrinksMenus",
        key: "id",
      },
      onUpdate: "CASCADE",
      onDelete: "SET NULL",
    });

    // 2️⃣ Add is_custom
    await queryInterface.addColumn("CanceledDrinkOrders", "is_custom", {
      type: Sequelize.BOOLEAN,
      allowNull: false,
      defaultValue: false,
    });

    // 3️⃣ Add customName
    await queryInterface.addColumn("CanceledDrinkOrders", "customName", {
      type: Sequelize.STRING,
      allowNull: true,
    });
  },

  async down(queryInterface, Sequelize) {
    await queryInterface.changeColumn("CanceledDrinkOrders", "drinksMenuId", {
      type: Sequelize.INTEGER,
      allowNull: false,
      references: {
        model: "DrinksMenus",
        key: "id",
      },
      onUpdate: "CASCADE",
      onDelete: "CASCADE",
    });

    await queryInterface.removeColumn("CanceledDrinkOrders", "is_custom");
    await queryInterface.removeColumn("CanceledDrinkOrders", "customName");
  },
};
