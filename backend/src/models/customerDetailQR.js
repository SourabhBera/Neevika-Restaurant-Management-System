module.exports = (sequelize, DataTypes) => {
  const customerDetailQR = sequelize.define("customerDetailQR", {
    phone: { type: DataTypes.STRING, allowNull: false, unique: true },
    name: { type: DataTypes.STRING, allowNull: false },
    gender: { type: DataTypes.STRING, allowNull: false },
    email: { type: DataTypes.STRING, allowNull: true },
    birthday: { type: DataTypes.DATEONLY, allowNull: true },
    anniversary: { type: DataTypes.DATEONLY, allowNull: true },
    address: { type: DataTypes.STRING, allowNull: true },

    // ✅ NEW FIELD: Foreign key to Table
    tableId: {
      type: DataTypes.INTEGER,
      allowNull: true,
      references: {
        model: 'Tables', // table name in DB
        key: 'id',
      },
    },

    // ✅ NEW FIELD: Offer Value (text)
    offerValue: {
      type: DataTypes.TEXT,
      allowNull: true,
    },
  });

  customerDetailQR.associate = (models) => {
    customerDetailQR.belongsTo(models.QrOffer, {
      foreignKey: 'offerId',
      as: 'offer',
    });

    // ✅ Association with Table
    customerDetailQR.belongsTo(models.Table, {
      foreignKey: 'tableId',
      as: 'table',
    });
  };

  return customerDetailQR;
};