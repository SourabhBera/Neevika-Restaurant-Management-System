// models/incidentReport.js
module.exports = (sequelize, DataTypes) => {
  const IncidentReport = sequelize.define("IncidentReport", {
    id: {
      type: DataTypes.INTEGER,
      primaryKey: true,
      autoIncrement: true, // Auto increment instead of UUID
    },
    title: {
      type: DataTypes.STRING,
      allowNull: false,
    },
    description: {
      type: DataTypes.TEXT,
      allowNull: false,
    },
    images: {
      type: DataTypes.JSONB, // store array of image URLs
      allowNull: true,
      defaultValue: [],
    },
    incidentDate: {
      type: DataTypes.DATE,
      allowNull: false,
    },
    userId: {
      type: DataTypes.INTEGER,
      allowNull: false,
      references: {
        model: "Users", // assumes you already have Users table
        key: "id",
      },
      onUpdate: "CASCADE",
      onDelete: "SET NULL",
    },
  });

  IncidentReport.associate = (models) => {
    IncidentReport.belongsTo(models.User, { foreignKey: "userId" });
  };

  return IncidentReport;
};
