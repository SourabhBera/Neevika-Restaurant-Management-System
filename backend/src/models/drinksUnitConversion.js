// models/DrinkUnitConversion.js
module.exports = (sequelize, DataTypes) => {
  const DrinkUnitConversion = sequelize.define('DrinkUnitConversion', {
    inventoryId: {
      type: DataTypes.INTEGER,
      allowNull: false,
      references: {
        model: 'DrinksKitchenInventories',
        key: 'id',
      },
    },
    fromUnit: {
      type: DataTypes.STRING,
      allowNull: false
    },
    toUnit: {
      type: DataTypes.STRING,
      allowNull: false
    },
    conversionFactor: {
      type: DataTypes.FLOAT,
      allowNull: false
    }
  });

  DrinkUnitConversion.associate = (models) => {
    DrinkUnitConversion.belongsTo(models.DrinksKitchenInventory, {
      foreignKey: 'kitchenInventoryId',
      as: 'drinkInventory',
    });
  };

  return DrinkUnitConversion;
};
