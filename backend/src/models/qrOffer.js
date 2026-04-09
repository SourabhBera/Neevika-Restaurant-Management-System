module.exports = (sequelize, DataTypes) => {
  const QrOffer = sequelize.define("QrOffer", {
    offer_code: { type: DataTypes.STRING, unique: true, allowNull: false },
    offer_type: {
      type: DataTypes.ENUM("percent", "cash"),
      allowNull: false
    },
    offer_value: { type: DataTypes.FLOAT, allowNull: false }
  });

  return QrOffer;
};
