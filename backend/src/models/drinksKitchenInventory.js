// models/DrinksKitchenInventory.js
'use strict';
const { Model } = require('sequelize');
module.exports = (sequelize, DataTypes) => {
  class DrinksKitchenInventory extends Model {
    static associate(models) {
      DrinksKitchenInventory.belongsTo(models.DrinksInventory, {
        foreignKey: 'inventoryId',
        as: 'drinksInventory', // ✅ Correct alias
      });
    }
  }

  DrinksKitchenInventory.init(
    {
      inventoryId: {
        type: DataTypes.INTEGER,
        references: {
          model: 'DrinksInventories',  // Referencing DrinksInventories table
          key: 'id',
        },
      },
      quantity: {
        type: DataTypes.INTEGER,  // Quantity in ml (amount of liquid in the kitchen)
        allowNull: false,
      },
      totalQuantityRemaining: {
        type: DataTypes.INTEGER,  
        allowNull: false,
      },
      unit: {
        type: DataTypes.STRING,
        allowNull: false,
      },
      bottleSize: {
        type: DataTypes.FLOAT,  // Size of the bottle in ml (e.g., 720ml, 360ml, etc.)
        allowNull: true, // Optional field
      },
    },
    {
      sequelize,
      modelName: 'DrinksKitchenInventory',
    }
  );

  return DrinksKitchenInventory;
};
