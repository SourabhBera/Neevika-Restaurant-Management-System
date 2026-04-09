'use strict';
const { Model } = require('sequelize');
module.exports = (sequelize, DataTypes) => {
  class InventoryCategory extends Model {
    static associate(models) {
      // An InventoryCategory can have many Inventory items
      InventoryCategory.hasMany(models.Inventory, {
        foreignKey: 'categoryId',
        as: 'inventories',
      });
    }
  }

  InventoryCategory.init(
    {
      categoryName: DataTypes.STRING,
    },
    {
      sequelize,
      modelName: 'InventoryCategory',
    }
  );

  return InventoryCategory;
};
