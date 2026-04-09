'use strict';
module.exports = (sequelize, DataTypes) => {
  const TransferHistory = sequelize.define('TransferHistory', {
    date: {
      type: DataTypes.DATE,
      allowNull: false,
    },
    itemName: {
      type: DataTypes.STRING,
      allowNull: false
    },
    quantity: {
      type: DataTypes.FLOAT,
      allowNull: false,
    },
    unit: {
      type: DataTypes.STRING,
      allowNull: false,
    },
    userId: {
      type: DataTypes.INTEGER,
      allowNull: false,
    },
  }, {
    tableName: 'TransferHistories',
    timestamps: false
  });

  // ✅ Fix here: use TransferHistory instead of Order
  TransferHistory.associate = (models) => {
    TransferHistory.belongsTo(models.User, {
      foreignKey: 'userId',
      as: 'user',
    });
  };

  return TransferHistory;
};
