'use strict';
module.exports = (sequelize, DataTypes) => {
  const DrinksPurchaseHistory = sequelize.define('DrinksPurchaseHistory', {
    date: {
      type: DataTypes.DATE,
      allowNull: false,
    },
    title: {
      type: DataTypes.STRING,
      allowNull: true
    },
    amount: {
      type: DataTypes.DECIMAL(10, 2),
      allowNull: false,
    },
    receipt_image: {
      type: DataTypes.STRING,
      allowNull: true,
    },
    items: {
      type: DataTypes.JSON,
      allowNull: false,
    },
    notes: {
      type: DataTypes.TEXT,
      allowNull: true,
    },
    delivery_status: {
      type: DataTypes.ENUM('pending', 'complete'),
      allowNull: false,
      defaultValue: 'pending',
    },
    payment_status: {
      type: DataTypes.ENUM('pending', 'complete'),
      allowNull: false,
      defaultValue: 'pending',
    },
    payment_type: {
      type: DataTypes.ENUM('Cash', 'UPI', 'Cheque', 'Netbanking', 'Card'),
      allowNull: false,
      defaultValue: 'Cash',
    },
    approved: {              // ✅ New approval field
      type: DataTypes.BOOLEAN,
      allowNull: false,
      defaultValue: false,
    },
  }, {
    tableName: 'DrinksPurchaseHistories'
  });

  DrinksPurchaseHistory.associate = function(models) {
    DrinksPurchaseHistory.belongsTo(models.Vendor, {
      foreignKey: 'vendor_id',
      as: 'vendor',
      onDelete: 'SET NULL',
      onUpdate: 'CASCADE'
    });
  };

  return DrinksPurchaseHistory;
};
