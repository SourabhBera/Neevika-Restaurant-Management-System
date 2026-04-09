// backend/src/models/orderitem.js

'use strict';
const { Model } = require('sequelize');

module.exports = (sequelize, DataTypes) => {
  class OrderItem extends Model {
    static associate(models) {
      // OrderItem belongs to an Order
      OrderItem.belongsTo(models.Order, {
        foreignKey: 'orderId',
        as: 'order'
      });

      OrderItem.belongsTo(models.DrinksOrder, {
        foreignKey: 'orderId',
        as: 'drinksOrder'
      });

      // OrderItem belongs to a User (for waiter/employee tracking)
      OrderItem.belongsTo(models.User, {
        foreignKey: 'userId',
        as: 'user'
      });

      // OrderItem belongs to a Menu
      OrderItem.belongsTo(models.Menu, {
        foreignKey: 'menuId',
        as: 'menu'
      });

      OrderItem.belongsTo(models.DrinksMenu, {
        foreignKey: 'menuId',
        as: 'drink',
      });

      OrderItem.belongsTo(models.Category, {
        foreignKey: 'categoryId',
        as: 'category'
      });

      OrderItem.belongsTo(models.DrinksCategory, {
        foreignKey: 'categoryId',
        as: 'drinksCategory'
      });
    }
  }

  OrderItem.init({
    food: DataTypes.BOOLEAN,
    userId: DataTypes.INTEGER,
    menuId: {
      type: DataTypes.INTEGER,
      allowNull: true
    },
    orderId: DataTypes.INTEGER,
    quantity: DataTypes.INTEGER,
    price: DataTypes.FLOAT,
    commissionTotal: DataTypes.FLOAT,
    categoryId: {
      type: DataTypes.INTEGER,
      allowNull: true
    },
    desc: {
      type: DataTypes.TEXT,
      allowNull: true
    },
    kotNumber: {                 // ✅ Added here
      type: DataTypes.INTEGER,
      allowNull: true,
    },
    createdAt: DataTypes.DATE
  }, {
    sequelize,
    modelName: 'OrderItem',
  });

  return OrderItem;
};
