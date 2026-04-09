// src/models/attendance.js

'use strict';
const {Model} = require('sequelize');

module.exports = (sequelize, DataTypes) => {
  class Attendance extends Model {
    static associate(models) {
      // Associations can be defined here
      Attendance.belongsTo(models.User, {
        foreignKey: 'employee_id', 
        as: 'employee',
      });
      Attendance.belongsTo(models.User, {
        foreignKey: 'marked_by', 
        as: 'hr',
      });

    }
  }

  Attendance.init(
    {
      employee_id: {
        type: DataTypes.INTEGER,
        allowNull: false,
      },
      status: {
        type: DataTypes.STRING,
        allowNull: false,
      },
      date: {
        type: DataTypes.DATE,
        allowNull: false,
      },
      marked_by: {
        type: DataTypes.INTEGER,
        allowNull: false,
      },
    },
    {
      sequelize,
      modelName: 'Attendance',
      timestamps: true,  // Automatically adds `createdAt` and `updatedAt` columns
      // Optionally, you can also explicitly define `createdAt` and `updatedAt` column names like:
      // createdAt: 'created_at',
      // updatedAt: 'updated_at',
    }
  );

  return Attendance;
};
