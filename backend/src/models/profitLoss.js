module.exports = (sequelize, DataTypes) => {
  const ProfitLoss = sequelize.define("ProfitLoss", {
    date: {
      type: DataTypes.DATEONLY,
      allowNull: false,
      unique: true, // One entry per day
    },
    total_sales: {
      type: DataTypes.FLOAT,
      allowNull: false,
      defaultValue: 0,
    },
    total_expenses: {
      type: DataTypes.FLOAT,
      allowNull: false,
      defaultValue: 0,
    },
    total_payroll_amount: {
      type: DataTypes.FLOAT,
      allowNull: false,
      defaultValue: 0,
    },
    profit: {
      type: DataTypes.FLOAT,
      allowNull: false,
      defaultValue: 0,
    },
    status: {
      type: DataTypes.STRING, // "Profit" or "Loss"
      allowNull: false,
    },
    purchase_amount: {
        type: DataTypes.FLOAT,
        allowNull: false,
        defaultValue: 0,
    },
    createdAt: {
      allowNull: false,
      type: DataTypes.DATE,
      defaultValue: DataTypes.NOW,
    },
    updatedAt: {
      allowNull: false,
      type: DataTypes.DATE,
      defaultValue: DataTypes.NOW,
    },
  });

  return ProfitLoss;
};
