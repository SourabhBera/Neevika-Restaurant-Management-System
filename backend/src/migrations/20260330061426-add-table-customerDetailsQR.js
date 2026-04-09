'use strict';

module.exports = {
  async up(queryInterface, Sequelize) {
    // ✅ Add tableId (Foreign Key)
    await queryInterface.addColumn('customerDetailQRs', 'tableId', {
      type: Sequelize.INTEGER,
      allowNull: true,
      references: {
        model: 'Tables', // make sure this matches your actual table name
        key: 'id',
      },
      onUpdate: 'CASCADE',
      onDelete: 'SET NULL',
    });

    // ✅ Add offerValue (TEXT)
    await queryInterface.addColumn('customerDetailQRs', 'offerValue', {
      type: Sequelize.TEXT,
      allowNull: true,
    });
  },

  async down(queryInterface, Sequelize) {
    // 🔻 Remove offerValue
    await queryInterface.removeColumn('customerDetailQRs', 'offerValue');

    // 🔻 Remove tableId
    await queryInterface.removeColumn('customerDetailQRs', 'tableId');
  },
};