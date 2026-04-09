module.exports = (sequelize, DataTypes) => {
  const DrinksCategory = sequelize.define(
    "DrinksCategory",
    {
      name: {
        type: DataTypes.STRING,
        allowNull: false,
      },
      description: {
        type: DataTypes.TEXT,
        allowNull: true,
      },
    },
    {
      indexes: [
        { fields: ["name"], name: "drinks_category_name_idx" }
      ]
    }
  );

  DrinksCategory.associate = (models) => {
    // A category has many drinks
    DrinksCategory.hasMany(models.DrinksMenu, {
      foreignKey: "drinksCategoryId",
      as: "drinksMenu",
    });
  };

  return DrinksCategory;
};
