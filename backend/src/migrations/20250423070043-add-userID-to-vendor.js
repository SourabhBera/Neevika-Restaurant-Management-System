'use strict';
/** @type {import('sequelize-cli').Migration} */
module.exports = {
  async up(queryInterface, Sequelize) {
    // Add the userId foreign key to Vendor table
    await queryInterface.addColumn('Vendors', 'userId', {
      type: Sequelize.INTEGER,
      references: {
        model: 'Users', // reference the Users table
        key: 'id', // the id in the Users table
      },
      allowNull: false,
    });
  },

  async down(queryInterface, Sequelize) {
    // Remove the userId foreign key from Vendor table
    await queryInterface.removeColumn('Vendors', 'userId');
  }
};
