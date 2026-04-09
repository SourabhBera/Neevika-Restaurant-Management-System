'use strict';
const { Model } = require('sequelize');
module.exports = (sequelize, DataTypes) => {
  class Ingredient extends Model {
    /**
     * Helper method for defining associations.
     */
    static associate(models) {
      // Many-to-Many with Menu via MenuIngredient
      
      // Ingredient.belongsToMany(models.Menu, {
      //   through: models.MenuIngredient,
      //   as: 'menus',
      //   foreignKey: 'ingredientId',
      // });

      // KitchenInventory tracks available quantity
      Ingredient.hasMany(models.KitchenInventory, {
        foreignKey: 'inventoryId',
        as: 'kitchenInventory',
      });
    }
  }
  Ingredient.init(
    {
      itemName: {
        type: DataTypes.STRING,
        allowNull: false,
      },
      description: {
        type: DataTypes.STRING,
      },
    },
    {
      sequelize,
      modelName: 'Ingredient',
    }
  );
  return Ingredient;
};
