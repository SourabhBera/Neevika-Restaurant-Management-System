module.exports = (sequelize, DataTypes) => {
  const Section = sequelize.define('Section', {
    name: DataTypes.STRING,
  });

  // Define associations
  Section.associate = (models) => {
    Section.hasMany(models.Table, {
      foreignKey: 'sectionId',
      as: 'tables',
    });
    Section.hasMany(models.Order, {
      foreignKey: 'section_number',
      as: 'orders',
    });
  };
  

  return Section;
};
