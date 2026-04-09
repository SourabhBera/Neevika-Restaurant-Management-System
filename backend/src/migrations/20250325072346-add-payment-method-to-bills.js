'use strict';

module.exports = {
  up: async (queryInterface, Sequelize) => {
    const [results] = await queryInterface.sequelize.query(`
      SELECT column_name
      FROM information_schema.columns
      WHERE table_name='Bills' AND column_name='payment_method';
    `);

    if (results.length === 0) {
      await queryInterface.addColumn('Bills', 'payment_method', {
        type: Sequelize.ENUM('cash', 'card', 'upi'),
        allowNull: false,
        defaultValue: 'cash',
      });
    } else {
      console.log('Column "payment_method" already exists. Skipping.');
    }
  },

  down: async (queryInterface, Sequelize) => {
    await queryInterface.removeColumn('Bills', 'payment_method');
  },
};
