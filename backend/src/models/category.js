'use strict';
const {Model} = require('sequelize');
module.exports = (sequelize, DataTypes) => {
  class Category extends Model {
    static associate(models) {
      // define association here
    }
  }
  Category.init({
    name: DataTypes.STRING,
    description: DataTypes.TEXT
  }, {
    sequelize,
    modelName: 'Category',
    indexes: [
      {
        fields: ['name'],
        name: 'category_name_idx'
      }
    ]
  });
  return Category;
};