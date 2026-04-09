'use strict';

module.exports = {
  async up(queryInterface, Sequelize) {
    await queryInterface.addColumn('Tables', 'lottery_discount_detail', {
      type: Sequelize.JSON,
      allowNull: true,
      defaultValue: null,
      comment: 'Stores lottery discount details like { "discount": 10, "source": "QR", "profile": 3 }',
    });
  },

  async down(queryInterface, Sequelize) {
    await queryInterface.removeColumn('Tables', 'lottery_discount_detail');
  },
};
