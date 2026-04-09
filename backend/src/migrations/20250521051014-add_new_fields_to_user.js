'use strict';

/** @type {import('sequelize').Migration} */
module.exports = {
  async up(queryInterface, Sequelize) {
    await queryInterface.addColumn('Users', 'aadhar_card', {
      type: Sequelize.STRING,
      allowNull: true,
      unique: true,  // Aadhar Card should be unique
    });

    await queryInterface.addColumn('Users', 'pan_card', {
      type: Sequelize.STRING,
      allowNull: true,
      unique: true,  // PAN Card should be unique
    });

    await queryInterface.addColumn('Users', 'address', {
      type: Sequelize.TEXT,
      allowNull: true,
    });

    await queryInterface.addColumn('Users', 'aadhar_card_path', {
      type: Sequelize.STRING,
      allowNull: true,
    });
    await queryInterface.addColumn('Users', 'pan_card_path', {
      type: Sequelize.STRING,
      allowNull: true,
    });
    await queryInterface.addColumn('Users', 'photograph_path', {
      type: Sequelize.STRING,
      allowNull: true,
    });

    await queryInterface.addColumn('Users', 'appointment_letter_path', {
      type: Sequelize.STRING,
      allowNull: true,
    });

    await queryInterface.addColumn('Users', 'leave_letter_path', {
      type: Sequelize.STRING,
      allowNull: true,
    });
  },

  async down(queryInterface, Sequelize) {
    await queryInterface.removeColumn('Users', 'aadhar_card');
    await queryInterface.removeColumn('Users', 'pan_card');
    await queryInterface.removeColumn('Users', 'address');
    await queryInterface.removeColumn('Users', 'aadhar_card_path');
    await queryInterface.removeColumn('Users', 'pan_card_path');
    await queryInterface.removeColumn('Users', 'photograph_path');
    await queryInterface.removeColumn('Users', 'appointment_letter_path');
    await queryInterface.removeColumn('Users', 'leave_letter_path');
  }
};
