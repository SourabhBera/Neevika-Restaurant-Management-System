module.exports = {
  up: async (queryInterface, Sequelize) => {
    await queryInterface.sequelize.query(`
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM pg_type t
          JOIN pg_enum e ON t.oid = e.enumtypid
          WHERE t.typname = 'enum_Orders_status' AND e.enumlabel = 'accepted'
        ) THEN
          ALTER TYPE "enum_Orders_status" ADD VALUE 'accepted';
        END IF;
      END
      $$;
    `);
  },

  down: async (queryInterface, Sequelize) => {
    // PostgreSQL doesn't allow removing enum values easily
    console.warn('Manual rollback needed for removing ENUM values.');
  }
};
