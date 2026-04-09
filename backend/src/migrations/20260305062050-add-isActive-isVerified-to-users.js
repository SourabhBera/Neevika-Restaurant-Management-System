'use strict';

module.exports = {
  async up(queryInterface, Sequelize) {
    const tableDesc = await queryInterface.describeTable('Users');

    // ✅ isActive column
    if (!tableDesc.isActive) {
      await queryInterface.addColumn('Users', 'isActive', {
        type: Sequelize.BOOLEAN,
        allowNull: false,
        defaultValue: true,
      });
    } else {
      await queryInterface.changeColumn('Users', 'isActive', {
        type: Sequelize.BOOLEAN,
        allowNull: false,
        defaultValue: true,
      });
    }

    // ✅ isVerified column
    if (!tableDesc.isVerified) {
      await queryInterface.addColumn('Users', 'isVerified', {
        type: Sequelize.BOOLEAN,
        allowNull: false,
        defaultValue: false,
      });
    } else {
      await queryInterface.changeColumn('Users', 'isVerified', {
        type: Sequelize.BOOLEAN,
        allowNull: false,
        defaultValue: false,
      });
    }
  },

  async down(queryInterface, Sequelize) {
    const tableDesc = await queryInterface.describeTable('Users');

    if (tableDesc.isActive) {
      await queryInterface.removeColumn('Users', 'isActive');
    }

    if (tableDesc.isVerified) {
      await queryInterface.removeColumn('Users', 'isVerified');
    }
  },
};