module.exports = (sequelize, DataTypes) => {
  const DrinksInventory = sequelize.define("DrinksInventory", {
    itemName: {
      type: DataTypes.STRING,

      allowNull: false,
    },

    quantity: {
      type: DataTypes.INTEGER, // Quantity in number of bottles

      allowNull: false,

      defaultValue: 0,
    },

    price: {
      type: DataTypes.DECIMAL,

      allowNull: false,

      defaultValue: 0,
    },

    unit: {
      type: DataTypes.STRING, // Can be "bottle", "ml", etc.

      allowNull: false,
    },

    minimumQuantity: {
      type: DataTypes.INTEGER,

      allowNull: false,
    },

    minimumQuantity_unit: {
      type: DataTypes.STRING,

      allowNull: false,
    },

    bottleSize: {
      type: DataTypes.FLOAT, // Size of the bottle in ml (e.g., 720, 360, 1000)

      allowNull: true,
    },
  });

  // ✅ Add this associate method

  DrinksInventory.associate = (models) => {
    DrinksInventory.belongsTo(models.DrinksInventoryCategory, {
      foreignKey: "categoryId",

      as: "category",
    });

    DrinksInventory.hasMany(models.DrinksKitchenInventory, {
      foreignKey: "inventoryId",

      as: "kitchenInventories",
    });
  };

  return DrinksInventory;
};
