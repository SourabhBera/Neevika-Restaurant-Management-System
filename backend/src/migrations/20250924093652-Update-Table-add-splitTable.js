// migrations/xxxxxx-add-split-fields-to-table.js
module.exports = {
  up: async (queryInterface, Sequelize) => {
    await queryInterface.addColumn('Tables', 'is_split', {
      type: Sequelize.BOOLEAN,
      defaultValue: false,
      allowNull: false,
    });

    await queryInterface.addColumn('Tables', 'parent_table_id', {
      type: Sequelize.INTEGER,
      allowNull: true,
    });

    await queryInterface.addColumn('Tables', 'split_name', {
      type: Sequelize.STRING,
      allowNull: true,
    });

    // (Optional) add an index for parent_table_id for fast lookup
    await queryInterface.addIndex('Tables', ['parent_table_id']);
  },

  down: async (queryInterface) => {
    await queryInterface.removeIndex('Tables', ['parent_table_id']);
    await queryInterface.removeColumn('Tables', 'split_name');
    await queryInterface.removeColumn('Tables', 'parent_table_id');
    await queryInterface.removeColumn('Tables', 'is_split');
  },
};
