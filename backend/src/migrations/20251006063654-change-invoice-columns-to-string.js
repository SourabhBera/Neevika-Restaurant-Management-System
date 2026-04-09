"use strict";

module.exports = {
  async up(queryInterface, Sequelize) {
    // Step 1: Change type only (no default yet)
    await queryInterface.changeColumn("DaySummaries", "invoices", {
      type: Sequelize.STRING,
      allowNull: false,
    });

    await queryInterface.changeColumn("DaySummaries", "complimentaryInvoice", {
      type: Sequelize.STRING,
      allowNull: false,
    });

    // Step 2: Update existing rows safely
    await queryInterface.sequelize.query(`
      UPDATE "DaySummaries"
      SET "invoices" = '0-0'
      WHERE "invoices" IS NULL OR "invoices" = '0';
    `);

    await queryInterface.sequelize.query(`
      UPDATE "DaySummaries"
      SET "complimentaryInvoice" = '0-0'
      WHERE "complimentaryInvoice" IS NULL OR "complimentaryInvoice" = '0';
    `);

    // Step 3: Add default value now that type is STRING
    await queryInterface.changeColumn("DaySummaries", "invoices", {
      type: Sequelize.STRING,
      allowNull: false,
      defaultValue: "0-0",
    });

    await queryInterface.changeColumn("DaySummaries", "complimentaryInvoice", {
      type: Sequelize.STRING,
      allowNull: false,
      defaultValue: "0-0",
    });
  },

  async down(queryInterface, Sequelize) {
    await queryInterface.changeColumn("DaySummaries", "invoices", {
      type: Sequelize.INTEGER,
      allowNull: false,
      defaultValue: 0,
    });

    await queryInterface.changeColumn("DaySummaries", "complimentaryInvoice", {
      type: Sequelize.INTEGER,
      allowNull: false,
      defaultValue: 0,
    });
  },
};
