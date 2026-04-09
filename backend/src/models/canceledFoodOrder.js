// models/canceledFoodOrder.js
module.exports = (sequelize, DataTypes) => {
  const CanceledFoodOrder = sequelize.define(
    "CanceledFoodOrder",
    {
      menuId: {
        type: DataTypes.INTEGER,
        allowNull: true, // <-- made nullable
        references: {
          model: "Menus",
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
      // 🆕 New fields for custom (open) food
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
      tableName: "CanceledFoodOrders",
      timestamps: true,
    }
  );

  CanceledFoodOrder.associate = (models) => {
    CanceledFoodOrder.belongsTo(models.User, {
      foreignKey: "userId",
      as: "user",
    });

    CanceledFoodOrder.belongsTo(models.Menu, {
      foreignKey: "menuId",
      as: "menu",
    });

    CanceledFoodOrder.belongsTo(models.User, {
      foreignKey: "deletedBy",
      as: "deletedByUser",
    });
  };

  return CanceledFoodOrder;
};
