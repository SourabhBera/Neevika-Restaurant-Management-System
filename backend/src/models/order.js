// backend/src/models/order.js

'use strict';

module.exports = (sequelize, DataTypes) => {
  const Order = sequelize.define('Order', {
    userId: {
      type: DataTypes.INTEGER,
      allowNull: false,
    },
    menuId: {
      type: DataTypes.INTEGER,
      allowNull: true,
      references: {
        model: 'Menus',
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
    table_number: {
      type: DataTypes.INTEGER,
      allowNull: true,
    },
    section_number: {
      type: DataTypes.INTEGER,
      allowNull: true,
    },
    restaurent_table_number: {
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

    // merge metadata
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

  Order.associate = (models) => {
    Order.belongsTo(models.Menu, {
      foreignKey: 'menuId',
      as: 'menu',
    });

    Order.belongsTo(models.Table, {
      foreignKey: 'table_number',
      as: 'table',
    });

    Order.belongsTo(models.User, {
      foreignKey: 'userId',
      as: 'user',
    });

    Order.belongsTo(models.Section, {
      foreignKey: 'section_number',
      as: 'section',
    });

    Order.hasMany(models.OrderItem, {
      foreignKey: 'orderId',
      as: 'orderItems',
    });
  };

  return Order;
};
