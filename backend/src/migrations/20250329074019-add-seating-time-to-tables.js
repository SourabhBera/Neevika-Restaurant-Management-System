'use strict';

module.exports = {
  async up(queryInterface, Sequelize) {
    const [columns] = await queryInterface.sequelize.query(`
      SELECT column_name FROM information_schema.columns WHERE table_name = 'Tables';
    `);

    const columnNames = columns.map(c => c.column_name);

    if (!columnNames.includes('seatingTime')) {
      await queryInterface.addColumn('Tables', 'seatingTime', {
        type: Sequelize.DATE,
        allowNull: true,
        defaultValue: null,
      });
    } else {
      console.log('Column "seatingTime" already exists. Skipping.');
    }

    if (!columnNames.includes('merged_with')) {
      await queryInterface.addColumn('Tables', 'merged_with', {
        type: Sequelize.INTEGER,
        allowNull: true,
        defaultValue: null,
      });
    } else {
      console.log('Column "merged_with" already exists. Skipping.');
    }
  },

  async down(queryInterface, Sequelize) {
    await queryInterface.removeColumn('Tables', 'seatingTime');
    await queryInterface.removeColumn('Tables', 'merged_with');
  },
};
