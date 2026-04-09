// models/DaySummary.js
module.exports = (sequelize, DataTypes) => {
  const DaySummary = sequelize.define("DaySummary", {
    date: {
      type: DataTypes.DATEONLY,
      unique: true,
      allowNull: false,
    },
    orderCount: {
      type: DataTypes.INTEGER,
      defaultValue: 0,
    },
    subTotal: {
      type: DataTypes.DECIMAL(10, 2),
      defaultValue: 0.0,
    },
    discount: {
      type: DataTypes.DECIMAL(10, 2),
      defaultValue: 0.0,
    },
    serviceCharges: {
      type: DataTypes.DECIMAL(10, 2),
      defaultValue: 0.0,
    },
    complimentaryAmount: {   // renamed field
      type: DataTypes.DECIMAL(10, 2),
      defaultValue: 0.0,
    },
    complimentaryInvoice: {  // new field
      type: DataTypes.STRING,
      defaultValue: "0-0",
    },
    totalComplimentaryBills: { // new field
      type: DataTypes.INTEGER,
      defaultValue: 0,
    },
    invoices: {
      type: DataTypes.STRING,
      defaultValue: "0-0",
    },
    totalBills: {
      type: DataTypes.INTEGER,
      defaultValue: 0,
    },
    tax: {
      type: DataTypes.DECIMAL(10, 2),
      defaultValue: 0.0,
    },
    roundOff: {
      type: DataTypes.DECIMAL(10, 2),
      defaultValue: 0.0,
    },
    grandTotal: {
      type: DataTypes.DECIMAL(10, 2),
      defaultValue: 0.0,
    },
    grandTotalPercentType: {
      type: DataTypes.STRING,
      allowNull: true,
    },
    grandTotalPercent: {
      type: DataTypes.FLOAT,
      allowNull: true,
    },
    netSales: {
      type: DataTypes.DECIMAL(10, 2),
      defaultValue: 0.0,
    },
    cash: {
      type: DataTypes.DECIMAL(10, 2),
      defaultValue: 0.0,
    },
    card: {
      type: DataTypes.DECIMAL(10, 2),
      defaultValue: 0.0,
    },
    upi: {
      type: DataTypes.DECIMAL(10, 2),
      defaultValue: 0.0,
    },
  });

  return DaySummary;
};
