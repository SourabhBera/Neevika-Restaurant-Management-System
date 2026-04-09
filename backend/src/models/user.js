'use strict';
const { Model } = require('sequelize');

module.exports = (sequelize, DataTypes) => {
  class User extends Model {
    static associate(models) {
      User.hasMany(models.OrderItem, {
        foreignKey: 'userId',  // For waiters and users taking orders
        as: 'orderItems',
      });
      
      User.hasMany(models.Order, {
        foreignKey: 'userId',
        as: 'orders',
      });

      // Define the association with User_role
      User.belongsTo(models.User_role, {
        foreignKey: 'roleId', // roleId will be the foreign key
        as: 'role', // Alias for the relationship
      });

      User.hasMany(models.Attendance, {
        foreignKey: 'employee_id', // This should reference the foreign key in Attendance
        as: 'attendances',         // Alias for relationship in User model
      });

      User.hasMany(models.Payroll, {
        foreignKey: 'employee_id',
        as: 'payrolls'
      });

    }
  }
  User.init(
    {
      name: DataTypes.STRING,
      email: {
        type: DataTypes.STRING,
        allowNull: false,
        unique: true,
      },
      phone_number: {
        type: DataTypes.STRING,
        allowNull: true,
        unique: false,
      },
      fcm_token: {
        type: DataTypes.TEXT,
        allowNull: true,
        unique: false,
      },
      password: DataTypes.STRING,
      roleId: { // role is now replaced by roleId to reference the User_role table
        type: DataTypes.INTEGER,
        allowNull: false,
        references: {
          model: 'User_roles', // reference the User_role table
          key: 'id', // the id in the User_roles table
        },
        defaultValue: 1, // default to the first role, which you can define as 'customer'
      },
      aadhar_card: {
        type: DataTypes.STRING,
        allowNull: true,
        unique: true,  // Assuming Aadhar Card is unique for each user
      },
      pan_card: {
        type: DataTypes.STRING,
        allowNull: true,
        unique: true,  // Assuming PAN Card is unique for each user
      },
      address: {
        type: DataTypes.TEXT,
        allowNull: true,
      },
      aadhar_card_path: {
        type: DataTypes.STRING,
        allowNull: true, // Assuming it's the path to the user's photo
      },
      pan_card_path: {
        type: DataTypes.STRING,
        allowNull: true, // Assuming it's the path to the user's photo
      },
      photograph_path: {
        type: DataTypes.STRING,
        allowNull: true, // Assuming it's the path to the user's photo
      },
      face_descriptor: {
        type: DataTypes.JSONB,
        allowNull: true, // initially null until face is registered
      },
      appointment_letter_path: {
        type: DataTypes.STRING,
        allowNull: true, // Assuming it's the path to the appointment letter
      },
      leave_letter_path: {
        type: DataTypes.STRING,
        allowNull: true, // Assuming it's the path to the leave letter
      },
      salary: {
        type: DataTypes.INTEGER,
        allowNull: false,
        defaultValue: 0,
      },

      isActive: {
        type: DataTypes.BOOLEAN,
        allowNull: false,
        defaultValue: true,
      },

      isVerified: {
        type: DataTypes.BOOLEAN,
        allowNull: false,
        defaultValue: false,
      },
    },
    {
      sequelize,
      modelName: 'User',
    }
  );
  return User;
};
