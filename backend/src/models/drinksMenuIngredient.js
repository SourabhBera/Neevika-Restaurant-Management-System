"use strict";

const { Model } = require("sequelize");

module.exports = (sequelize, DataTypes) => {
  class DrinksMenuIngredient extends Model {
    static associate(models) {
      // ✅ Belongs to DrinksMenu

      DrinksMenuIngredient.belongsTo(models.DrinksMenu, {
        foreignKey: "MenuId", // 👈 must match DB

        as: "menu",
      });

      DrinksMenuIngredient.belongsTo(models.DrinksInventory, {
        foreignKey: "inventoryId",

        as: "inventory",
      });
    }
  }

  DrinksMenuIngredient.init(
    {
      id: {
        type: DataTypes.INTEGER,

        autoIncrement: true,

        primaryKey: true,
      },

      MenuId: {
        // 👈 must match DB exactly

        type: DataTypes.INTEGER,

        allowNull: false,

        references: {
          model: "DrinksMenus",

          key: "id",
        },
      },

      inventoryId: {
        type: DataTypes.INTEGER,

        allowNull: false,

        references: {
          model: "DrinksInventories",

          key: "id",
        },
      },

      quantityRequired: {
        type: DataTypes.FLOAT,

        allowNull: false,
      },

      unit: {
        type: DataTypes.STRING,

        allowNull: false,
      },
    },

    {
      sequelize,

      modelName: "DrinksMenuIngredient",
    }
  );

  return DrinksMenuIngredient;
};
