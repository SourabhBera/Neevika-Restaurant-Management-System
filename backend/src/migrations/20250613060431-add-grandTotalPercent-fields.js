module.exports = {
  up: async (queryInterface, Sequelize) => {
    await queryInterface.addColumn('DaySummaries', 'grandTotalPercentType', {
      type: Sequelize.STRING,
      allowNull: true,
    });
    await queryInterface.addColumn('DaySummaries', 'grandTotalPercent', {
      type: Sequelize.FLOAT,
      allowNull: true,
    });
  },

  down: async (queryInterface, Sequelize) => {
    await queryInterface.removeColumn('DaySummaries', 'grandTotalPercentType');
    await queryInterface.removeColumn('DaySummaries', 'grandTotalPercent');
  },
};
