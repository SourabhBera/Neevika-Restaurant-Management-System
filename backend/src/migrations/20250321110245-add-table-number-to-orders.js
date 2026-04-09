'use strict';

module.exports = {
  up: async (queryInterface, Sequelize) => {
    const [results] = await queryInterface.sequelize.query(`
      SELECT column_name
      FROM information_schema.columns
      WHERE table_name='Orders' AND column_name='table_number';
    `);

    if (results.length === 0) {
      await queryInterface.addColumn('Orders', 'table_number', {
        type: Sequelize.INTEGER,
        references: {
          model: 'Tables',
          key: 'id',
        },
        onUpdate: 'CASCADE',
        onDelete: 'SET NULL',
      });
    } else {
      console.log('Column "table_number" already exists. Skipping.');
    }
  },

  down: async (queryInterface, Sequelize) => {
    await queryInterface.removeColumn('Orders', 'table_number');
  },
};
