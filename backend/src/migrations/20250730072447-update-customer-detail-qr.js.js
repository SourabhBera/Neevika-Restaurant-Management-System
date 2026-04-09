'use strict';

module.exports = {
  async up(queryInterface, Sequelize) {
    await queryInterface.addColumn('customerDetailQRs', 'offerId', {
      type: Sequelize.INTEGER,
      references: {
        model: 'QrOffers',
        key: 'id'
      },
      onUpdate: 'CASCADE',
      onDelete: 'SET NULL',
      allowNull: true
    });
  },

  async down(queryInterface, Sequelize) {
    await queryInterface.removeColumn('customerDetailQRs', 'offerId');
  }
};
