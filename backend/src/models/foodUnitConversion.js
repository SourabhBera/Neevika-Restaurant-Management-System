// models/FoodUnitConversion.js
module.exports = (sequelize, DataTypes) => {
  const FoodUnitConversion = sequelize.define('FoodUnitConversion', {
    inventoryId: {
      type: DataTypes.INTEGER,
      allowNull: false,
      references: {
        model: 'KitchenInventories',
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

  FoodUnitConversion.associate = (models) => {
    FoodUnitConversion.belongsTo(models.KitchenInventory, {
      foreignKey: 'kitchenInventoryId',
      as: 'foodInventory',
    });
  };

  return FoodUnitConversion;
};
