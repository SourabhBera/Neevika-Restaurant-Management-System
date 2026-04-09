// models/drinksMenu.js

module.exports = (sequelize, DataTypes) => {
  const DrinksMenu = sequelize.define(
    "DrinksMenu",
    {
      name: {
        type: DataTypes.STRING,
        allowNull: false,
      },
      price: {
        type: DataTypes.FLOAT,
        allowNull: false,
      },
      drinksCategoryId: {
        type: DataTypes.INTEGER,
        allowNull: false,
        references: {
          model: "DrinksCategories",
          key: "id",
        },
      },
      isOffer: {
        type: DataTypes.BOOLEAN,
        defaultValue: false,
      },
      isUrgent: {
        type: DataTypes.BOOLEAN,
        defaultValue: false,
      },
      isOutOfStock: {
        type: DataTypes.BOOLEAN,
        defaultValue: false,
      },
      applyVAT: {
        type: DataTypes.BOOLEAN,
        defaultValue: false,
      },
      offerPrice: {
        type: DataTypes.FLOAT,
        allowNull: true,
      },
      waiterCommission: {
        type: DataTypes.FLOAT,
        allowNull: true,
      },
      commissionType: {
        type: DataTypes.ENUM("flat", "percentage"),
        allowNull: true,
      },
    },
    {
      indexes: [
        { fields: ["drinksCategoryId"], name: "drinks_menu_category_id_idx" },
        { fields: ["isUrgent", "id"], name: "drinks_menu_urgent_id_idx" },
        { fields: ["isOffer"], name: "drinks_menu_is_offer_idx" },
        {
          fields: [sequelize.fn("LOWER", sequelize.col("name"))],
          name: "drinks_menu_name_lower_idx",
        },
      ],
    }
  );

  DrinksMenu.associate = (models) => {
    DrinksMenu.belongsTo(models.DrinksCategory, {
      foreignKey: "drinksCategoryId",
      as: "category",
    });

    DrinksMenu.hasMany(models.DrinksOrder, {
      foreignKey: "drinksMenuId",
      as: "orders",
    });

    DrinksMenu.hasMany(models.DrinksMenuIngredient, {
      foreignKey: "MenuId",
      as: "ingredients",
    });
  };

  return DrinksMenu;
};
