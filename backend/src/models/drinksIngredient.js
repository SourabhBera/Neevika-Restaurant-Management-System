// models/DrinksInventory.js
module.exports = (sequelize, DataTypes) => {
  const DrinksInventory = sequelize.define('DrinksInventory', {
    itemName: {
      type: DataTypes.STRING,
      allowNull: false,
    },
    quantity: {
      type: DataTypes.INTEGER,  // Quantity in number of bottles
      allowNull: false,
      defaultValue: 0,
    },
    price: {
      type: DataTypes.DECIMAL,
      allowNull: false,
    },
    unit: {
      type: DataTypes.STRING,  // Can be "bottle", "ml", etc.
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
      type: DataTypes.FLOAT,  // Size of the bottle in ml (e.g., 720, 360, 1000)
      allowNull: true,
    },
  });

  // Adding associations
  DrinksInventory.associate = (models) => {
    // Many-to-many relationship with DrinksMenu through DrinksMenuIngredient
    DrinksInventory.belongsToMany(models.DrinksMenu, {
      through: models.DrinksMenuIngredient, // This is the junction table
      as: 'menus', // The alias for the relationship
      foreignKey: 'inventoryId',  // The foreign key in the junction table
    });
  };

  return DrinksInventory;
};
