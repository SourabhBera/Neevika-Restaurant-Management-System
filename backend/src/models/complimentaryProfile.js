'use strict';
module.exports = (sequelize, DataTypes) => {
  const ComplimentaryProfile = sequelize.define('ComplimentaryProfile', {
    name: {
      type: DataTypes.STRING,
      allowNull: false,
    },
    description: {
      type: DataTypes.TEXT,
      allowNull: true,
    },
    icon: {
      type: DataTypes.STRING,
      allowNull: true,
      comment: 'Icon name or URL for UI display',
    },
    color: {
      type: DataTypes.STRING,
      allowNull: true,
      comment: 'Hex color code or theme color for the profile',
    },
    active: {
      type: DataTypes.BOOLEAN,
      allowNull: false,
      defaultValue: true,
    },
  });

  ComplimentaryProfile.associate = (models) => {
    ComplimentaryProfile.hasMany(models.Bill, {
      foreignKey: 'complimentaryProfileId',
      as: 'bills',
    });
  };

  return ComplimentaryProfile;
};
