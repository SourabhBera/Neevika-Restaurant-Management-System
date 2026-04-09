'use strict';
module.exports = (sequelize, DataTypes) => {
  const DrinksTransferHistory = sequelize.define('DrinksTransferHistory', {
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
    tableName: 'DrinksTransferHistories',
    timestamps: false
  });

  // ✅ Fix here: use DrinksTransferHistory instead of Order
  DrinksTransferHistory.associate = (models) => {
    DrinksTransferHistory.belongsTo(models.User, {
      foreignKey: 'userId',
      as: 'user',
    });
  };

  return DrinksTransferHistory;
};
