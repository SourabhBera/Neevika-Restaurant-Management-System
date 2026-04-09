'use strict';
const { Model } = require('sequelize');
module.exports = (sequelize, DataTypes) => {
  class Inventory extends Model {
    static associate(models) {
      // Each Inventory item belongs to one InventoryCategory
      Inventory.belongsTo(models.InventoryCategory, {
        foreignKey: 'categoryId',
        as: 'category',
      });
    }
  }

  Inventory.init(
    {
      itemName: DataTypes.STRING,
      quantity: DataTypes.FLOAT,
      unit: DataTypes.STRING,
      expiryDate: DataTypes.DATE,
      barcode: DataTypes.STRING,
      minimum_quantity: DataTypes.FLOAT,
      minimum_quantity_unit: DataTypes.STRING,
      categoryId: {
        type: DataTypes.INTEGER,
        references: {
          model: 'InventoryCategories', // Table name
          key: 'id',
        },
      },
    },
    {
      sequelize,
      modelName: 'Inventory',
    }
  );

  return Inventory;
};
