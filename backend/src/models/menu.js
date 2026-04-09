// models/menu.js
module.exports = (sequelize, DataTypes) => {
  const Menu = sequelize.define(
    "Menu",
    {
      name: {
        type: DataTypes.STRING,
        allowNull: false,
      },
      description: {
        type: DataTypes.TEXT,
      },
      price: {
        type: DataTypes.FLOAT,
        allowNull: false,
      },
      veg: {
        type: DataTypes.BOOLEAN,
        allowNull: false,
      },
      categoryId: {
        type: DataTypes.INTEGER,
        references: {
          model: "Categories",
          key: "id",
        },
      },
      isUrgent: {
        type: DataTypes.BOOLEAN,
        defaultValue: false,
      },
      isOffer: {
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
      quantity: {
        type: DataTypes.INTEGER,
        allowNull: false,
        defaultValue: 0,
      },
      editedBy: {
        type: DataTypes.INTEGER,
        references: {
          model: "User_roles",
          key: "id",
        },
        allowNull: true,
      },
      kotCategory: {
        type: DataTypes.STRING,
        allowNull: true,
      },
    },
    {
      indexes: [
        {
          fields: ['categoryId'],
          name: 'menu_category_id_idx'
        },
        {
          fields: ['isUrgent', 'id'],
          name: 'menu_urgent_id_idx'
        },
        {
          fields: ['isOffer'],
          name: 'menu_is_offer_idx'
        },
        {
          fields: ['veg'],
          name: 'menu_veg_idx'
        },
        {
          fields: [sequelize.fn('LOWER', sequelize.col('name'))],
          name: 'menu_name_lower_idx'
        }
      ]
    }
  );

  Menu.associate = (models) => {
    Menu.belongsTo(models.Category, {
      foreignKey: "categoryId",
      as: "category",
    });

    Menu.belongsTo(models.User_role, {
      foreignKey: "editedBy",
      as: "editorRole",
    });
  };

  return Menu;
};