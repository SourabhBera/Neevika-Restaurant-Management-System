"use strict";

module.exports = {
  async up(queryInterface, Sequelize) {
    // Rename complimentary → complimentaryAmount
    await queryInterface.renameColumn("DaySummaries", "complimentary", "complimentaryAmount");

    // Change type to DECIMAL(10,2) since it's an amount
    await queryInterface.changeColumn("DaySummaries", "complimentaryAmount", {
      type: Sequelize.DECIMAL(10, 2),
      defaultValue: 0.0,
    });

    // Add complimentaryInvoice
    await queryInterface.addColumn("DaySummaries", "complimentaryInvoice", {
      type: Sequelize.STRING,
      defaultValue: "0-0",
    });

    // Add totalComplimentaryBills
    await queryInterface.addColumn("DaySummaries", "totalComplimentaryBills", {
      type: Sequelize.INTEGER,
      defaultValue: 0,
    });
  },

  async down(queryInterface, Sequelize) {
    // Revert complimentaryAmount → complimentary
    await queryInterface.renameColumn("DaySummaries", "complimentaryAmount", "complimentary");

    // Revert type to INTEGER (original definition)
    await queryInterface.changeColumn("DaySummaries", "complimentary", {
      type: Sequelize.INTEGER,
      defaultValue: 0,
    });

    // Remove added fields
    await queryInterface.removeColumn("DaySummaries", "complimentaryInvoice");
    await queryInterface.removeColumn("DaySummaries", "totalComplimentaryBills");
  },
};
