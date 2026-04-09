"use strict";

module.exports = {
  async up(queryInterface, Sequelize) {
    // CanceledDrinkOrders
    await queryInterface.addColumn("CanceledDrinkOrders", "section_number", {
      type: Sequelize.INTEGER,
      allowNull: true,
    });

    await queryInterface.addColumn(
      "CanceledDrinkOrders",
      "restaurent_table_number",
      {
        type: Sequelize.INTEGER,
        allowNull: true,
      }
    );

    // CanceledFoodOrders
    await queryInterface.addColumn("CanceledFoodOrders", "section_number", {
      type: Sequelize.INTEGER,
      allowNull: true,
    });

    await queryInterface.addColumn(
      "CanceledFoodOrders",
      "restaurent_table_number",
      {
        type: Sequelize.INTEGER,
        allowNull: true,
      }
    );
  },

  async down(queryInterface, Sequelize) {
    // Rollback
    await queryInterface.removeColumn("CanceledDrinkOrders", "section_number");
    await queryInterface.removeColumn(
      "CanceledDrinkOrders",
      "restaurent_table_number"
    );

    await queryInterface.removeColumn("CanceledFoodOrders", "section_number");
    await queryInterface.removeColumn(
      "CanceledFoodOrders",
      "restaurent_table_number"
    );
  },
};
