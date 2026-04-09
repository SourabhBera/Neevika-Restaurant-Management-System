'use strict';

module.exports = {
  async up(queryInterface, Sequelize) {
    await queryInterface.addColumn('Bills', 'complimentary_profile_id', {
      type: Sequelize.INTEGER,
      allowNull: true,
      references: {
        model: 'ComplimentaryProfiles', // name of the target table
        key: 'id',
      },
      onUpdate: 'CASCADE',
      onDelete: 'SET NULL',
    });
  },

  async down(queryInterface, Sequelize) {
    await queryInterface.removeColumn('Bills', 'complimentary_profile_id');
  },
};
