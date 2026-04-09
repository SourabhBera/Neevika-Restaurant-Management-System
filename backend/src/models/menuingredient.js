'use strict';
const { Model } = require('sequelize');

module.exports = (sequelize, DataTypes) => {
  class MenuIngredient extends Model {
    static associate(models) {
      // ✅ Belongs to Menu
      MenuIngredient.belongsTo(models.Menu, {
        foreignKey: 'MenuId',
        as: 'menu',
      });

      // ✅ Belongs to Ingredient
      MenuIngredient.belongsTo(models.Inventory, {
        foreignKey: 'inventoryId',
        as: 'ingredient',
      });
    }
  }

  MenuIngredient.init(
    {
    id: {
      type: DataTypes.INTEGER,
      autoIncrement: true,
      primaryKey: true,
    },
      MenuId: {
        type: DataTypes.INTEGER,
        allowNull: false,
        references: {
          model: 'Menus',
          key: 'id',
        },
      },
      inventoryId: {
        type: DataTypes.INTEGER,
        allowNull: false,
        references: {
          model: 'Inventories',
          key: 'id',
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
      modelName: 'MenuIngredient',
    }
  );

  return MenuIngredient;
};
