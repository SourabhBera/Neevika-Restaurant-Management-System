'use strict';

module.exports = (sequelize, DataTypes) => {
  const Log = sequelize.define('Log', {
    action: {
      type: DataTypes.STRING(255),
      allowNull: false,
    },
    user_id: {
      type: DataTypes.INTEGER,
      allowNull: false,
    },
    user_role: {
      type: DataTypes.STRING(50),
      allowNull: false,
    },
    timestamp: {
      type: DataTypes.DATE,
      defaultValue: sequelize.fn('now'),
    },
    affected_entity: {
      type: DataTypes.STRING(255),
      allowNull: false,
    },
    old_value: {
      type: DataTypes.TEXT,
      allowNull: true,
    },
    new_value: {
      type: DataTypes.TEXT,
      allowNull: true,
    },
  }, {});

  // Associations (if any)
  Log.associate = function(models) {
    // Log has a foreign key relationship with the User model
    Log.belongsTo(models.User, { foreignKey: 'user_id' });
  };

  return Log;
};
