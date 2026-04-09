// models/drinksOrder.js
'use strict';

module.exports = (sequelize, DataTypes) => {
  const DrinksOrder = sequelize.define('DrinksOrder', {
    userId: {
      type: DataTypes.INTEGER,
      allowNull: false,
    },
    drinksMenuId: {
      type: DataTypes.INTEGER,
      allowNull: true,
      references: {
        model: 'DrinksMenus',
        key: 'id',
      },
    },
    item_desc: {
      type: DataTypes.STRING,
      allowNull: true,
    },
    quantity: {
      type: DataTypes.INTEGER,
      allowNull: false,
    },
    status: {
      type: DataTypes.STRING,
      defaultValue: 'pending',
    },
    amount: {
      type: DataTypes.FLOAT,
      allowNull: false,
    },

    applyVAT: {
      type: DataTypes.BOOLEAN,
      defaultValue: false,
    },

    table_number: {
      type: DataTypes.INTEGER,
      allowNull: true,
    },
    section_number: {
      type: DataTypes.INTEGER,
      allowNull: true,
    },
    restaurant_table_number: {
      type: DataTypes.STRING,
      allowNull: true,
    },
    is_custom: {
      type: DataTypes.BOOLEAN,
      defaultValue: false,
    },
    kotNumber: {
      type: DataTypes.STRING,
      allowNull: true,
    },

    merged_from_table: {
      type: DataTypes.INTEGER,
      allowNull: true,
      defaultValue: null,
    },

    shifted_from_table: {
      type: DataTypes.STRING,
      allowNull: true,
      defaultValue: null,
    },
  });

  DrinksOrder.associate = (models) => {
    DrinksOrder.belongsTo(models.DrinksMenu, {
      foreignKey: 'drinksMenuId',
      as: 'drink',
    });

    DrinksOrder.belongsTo(models.User, {
      foreignKey: 'userId',
      as: 'user',
    });

    DrinksOrder.belongsTo(models.Table, {
      foreignKey: 'table_number',
      as: 'table',
    });

    DrinksOrder.belongsTo(models.Section, {
      foreignKey: 'section_number',
      as: 'section',
    });
  };

  return DrinksOrder;
};