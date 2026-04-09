'use strict';

module.exports = {
  up: async (queryInterface, Sequelize) => {
    return queryInterface.addColumn('Tables', 'display_number', {
      type: Sequelize.INTEGER,
      allowNull: false,
      defaultValue: 0, // Temporary default to avoid errors for existing rows
    });
  },

  down: async (queryInterface, Sequelize) => {
    return queryInterface.removeColumn('Tables', 'display_number');
  }
};
