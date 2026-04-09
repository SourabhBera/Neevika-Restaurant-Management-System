'use strict';

module.exports = {
  up: async (queryInterface, Sequelize) => {
    await queryInterface.addColumn('PurchaseHistories', 'delivery_status', {
      type: Sequelize.ENUM('pending', 'complete'),
      allowNull: false,
      defaultValue: 'pending'
    });

    await queryInterface.addColumn('PurchaseHistories', 'payment_status', {
      type: Sequelize.ENUM('pending', 'complete'),
      allowNull: false,
      defaultValue: 'pending'
    });

    await queryInterface.addColumn('PurchaseHistories', 'payment_type', {
      type: Sequelize.ENUM('Cash', 'UPI', 'Cheque', 'Netbanking', 'Card'),
      allowNull: false,
      defaultValue: 'Cash'
    });
  },

  down: async (queryInterface, Sequelize) => {
    await queryInterface.removeColumn('PurchaseHistories', 'delivery_status');
    await queryInterface.removeColumn('PurchaseHistories', 'payment_status');
    await queryInterface.removeColumn('PurchaseHistories', 'payment_type');

    // Drop ENUM types explicitly to avoid issues during re-migration
    await queryInterface.sequelize.query('DROP TYPE IF EXISTS "enum_PurchaseHistories_delivery_status";');
    await queryInterface.sequelize.query('DROP TYPE IF EXISTS "enum_PurchaseHistories_payment_status";');
    await queryInterface.sequelize.query('DROP TYPE IF EXISTS "enum_PurchaseHistories_payment_type";');
  }
};
