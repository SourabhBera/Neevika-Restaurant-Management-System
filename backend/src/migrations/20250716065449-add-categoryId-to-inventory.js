module.exports = {
  up: async (queryInterface, Sequelize) => {
    await queryInterface.addColumn('Inventories', 'categoryId', {
      type: Sequelize.INTEGER,
      references: {
        model: 'InventoryCategories', // Table name
        key: 'id',
      },
      onUpdate: 'CASCADE',
      onDelete: 'SET NULL', // Optional: you can decide the behavior here
    });
  },

  down: async (queryInterface, Sequelize) => {
    await queryInterface.removeColumn('Inventories', 'categoryId');
  },
};
