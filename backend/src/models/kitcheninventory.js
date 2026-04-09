'use strict';
const { Model } = require('sequelize');
module.exports = (sequelize, DataTypes) => {
  class KitchenInventory extends Model {
    static associate(models) {
      KitchenInventory.belongsTo(models.Inventory, {
        foreignKey: 'inventoryId',
        as: 'inventory', // ✅ Correct alias
      });
    }
  }

  KitchenInventory.init(
    {
      inventoryId: {
        type: DataTypes.INTEGER,
        references: {
          model: 'Inventories',
          key: 'id',
        },
      },
      quantity: {
        type: DataTypes.FLOAT,
        allowNull: false,
      },
      unit: {
        type: DataTypes.STRING,
        allowNull: false,
      },
      totalQuantityRemaining: {
        type: DataTypes.INTEGER,  
        allowNull: false,
      },
      bagSize: {
        type: DataTypes.FLOAT,  // Size of the bottle in ml (e.g., 720ml, 360ml, etc.)
        allowNull: true, // Optional field
      },
    },
    
    {
      sequelize,
      modelName: 'KitchenInventory',
    }
  );

  return KitchenInventory;
};
