module.exports = (sequelize, DataTypes) => {
  const User_role = sequelize.define('User_role', {
    id: {
      type: DataTypes.INTEGER,
      primaryKey: true,
      autoIncrement: true,
    },
    name: {
      type: DataTypes.STRING,
      allowNull: false,
      unique: true,
    },
    createdAt: {
      type: DataTypes.DATE,
      allowNull: false,
    },
    updatedAt: {
      type: DataTypes.DATE,
      allowNull: false,
    },
  }, {
    tableName: 'User_roles', // Ensure the table name matches
    timestamps: true, // Enable timestamps as the table has createdAt and updatedAt
  });

  return User_role;
};
