'use strict';
const { Model } = require('sequelize');
module.exports = (sequelize, DataTypes) => {
  class DrinksInventoryCategory extends Model {
    static associate(models) {
      // An DrinksInventoryCategory can have many Inventory items
      DrinksInventoryCategory.hasMany(models.DrinksInventory, {
        foreignKey: 'categoryId',
        as: 'drinksInventories',
      });
    }
  }

  DrinksInventoryCategory.init(
    {
      categoryName: DataTypes.STRING,
    },
    {
      sequelize,
      modelName: 'DrinksInventoryCategory',
    }
  );

  return DrinksInventoryCategory;
};
