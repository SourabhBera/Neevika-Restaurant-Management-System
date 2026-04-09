module.exports = {
  up: async (queryInterface, Sequelize) => {
    await queryInterface.renameColumn('Tables', 'drinks_bill_id', 'bill_discount_percent');
  },

  down: async (queryInterface, Sequelize) => {
    await queryInterface.renameColumn('Tables', 'bill_discount_percent', 'drinks_bill_id');
  }
};
