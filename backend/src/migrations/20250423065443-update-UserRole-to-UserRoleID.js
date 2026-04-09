'use strict';
/** @type {import('sequelize-cli').Migration} */
module.exports = {
  async up(queryInterface, Sequelize) {
    // Add the roleId column to the Users table
    await queryInterface.addColumn('Users', 'roleId', {
      type: Sequelize.INTEGER,
      allowNull: false,
      references: {
        model: 'User_roles', // references User_roles table
        key: 'id', // the primary key of the User_roles table
      },
      defaultValue: 1, // Default to the first role (admin)
    });

    // Optional: Remove the old role column if you no longer need it
    await queryInterface.removeColumn('Users', 'role');
  },

  async down(queryInterface, Sequelize) {
    // Remove the roleId column
    await queryInterface.removeColumn('Users', 'roleId');

    // Recreate the old role column (if needed)
    await queryInterface.addColumn('Users', 'role', {
      type: Sequelize.STRING,
    });
  }
};
