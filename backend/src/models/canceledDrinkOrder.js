// models/canceledDrinkOrder.js
module.exports = (sequelize, DataTypes) => {
  const CanceledDrinkOrder = sequelize.define(
    "CanceledDrinkOrder",
    {
      drinksMenuId: {
        type: DataTypes.INTEGER,
        allowNull: true, // changed to nullable
        references: {
          model: "DrinksMenus",
          key: "id",
        },
      },
      count: {
        type: DataTypes.INTEGER,
        allowNull: false,
        defaultValue: 0,
      },
      userId: {
        type: DataTypes.INTEGER,
        allowNull: false,
        references: {
          model: "Users",
          key: "id",
        },
      },
      tableNumber: {
        type: DataTypes.INTEGER,
        allowNull: false,
        defaultValue: 0,
      },
      section_number: {
        type: DataTypes.INTEGER,
        allowNull: true,
      },
      restaurent_table_number: {
        type: DataTypes.INTEGER,
        allowNull: true,
      },
      remarks: {
        type: DataTypes.STRING,
        allowNull: true,
      },
      isApproved: {
        type: DataTypes.BOOLEAN,
        allowNull: false,
        defaultValue: false,
      },
      deletedBy: {
        type: DataTypes.INTEGER,
        allowNull: true,
        references: {
          model: "Users",
          key: "id",
        },
      },
      // ✅ New fields
      is_custom: {
        type: DataTypes.BOOLEAN,
        allowNull: false,
        defaultValue: false,
      },
      customName: {
        type: DataTypes.STRING,
        allowNull: true,
      },
    },
    {
      tableName: "CanceledDrinkOrders",
      timestamps: true,
    }
  );

  CanceledDrinkOrder.associate = (models) => {
    CanceledDrinkOrder.belongsTo(models.User, {
      foreignKey: "userId",
      as: "user",
    });

    CanceledDrinkOrder.belongsTo(models.DrinksMenu, {
      foreignKey: "drinksMenuId",
      as: "menu",
    });

    CanceledDrinkOrder.belongsTo(models.User, {
      foreignKey: "deletedBy",
      as: "deletedByUser",
    });
  };

  return CanceledDrinkOrder;
};
