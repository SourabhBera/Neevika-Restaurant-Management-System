'use strict';

module.exports = {
  async up(queryInterface, Sequelize) {
    await queryInterface.addColumn('Bills', 'round_off', {
      type: Sequelize.TEXT,
      allowNull: true,
      defaultValue: '0',
      after: 'drink_discount_flat_amount', // optional (MySQL only)
    });
  },

  async down(queryInterface, Sequelize) {
    await queryInterface.removeColumn('Bills', 'round_off');
  },
};
