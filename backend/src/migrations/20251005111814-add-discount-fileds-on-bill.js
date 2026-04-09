'use strict';

module.exports = {
  async up(queryInterface, Sequelize) {
    await queryInterface.addColumn('Bills', 'food_discount_percentage', {
      type: Sequelize.FLOAT,
      allowNull: false,
      defaultValue: 0,
    });
    await queryInterface.addColumn('Bills', 'drink_discount_percentage', {
      type: Sequelize.FLOAT,
      allowNull: false,
      defaultValue: 0,
    });
    await queryInterface.addColumn('Bills', 'food_discount_flat_amount', {
      type: Sequelize.FLOAT,
      allowNull: false,
      defaultValue: 0,
    });
    await queryInterface.addColumn('Bills', 'drink_discount_flat_amount', {
      type: Sequelize.FLOAT,
      allowNull: false,
      defaultValue: 0,
    });
  },

  async down(queryInterface, Sequelize) {
    await queryInterface.removeColumn('Bills', 'food_discount_percentage');
    await queryInterface.removeColumn('Bills', 'drink_discount_percentage');
    await queryInterface.removeColumn('Bills', 'food_discount_flat_amount');
    await queryInterface.removeColumn('Bills', 'drink_discount_flat_amount');
  }
};
