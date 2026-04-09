module.exports = {
  up: async (queryInterface, Sequelize) => {
    await queryInterface.createTable('Bills', {
      id: {
        allowNull: false,
        autoIncrement: true,
        primaryKey: true,
        type: Sequelize.INTEGER,
      },
      waiter_id: {
        type: Sequelize.INTEGER,
        allowNull: false,
      },
      table_number: {
        type: Sequelize.INTEGER,
        allowNull: false,
      },
      customerDetails_id: {
        type: Sequelize.INTEGER,
        allowNull: false,
        references: {
          model: 'CustomerDetails',
          key: 'id',
        },
        onUpdate: 'CASCADE',
        onDelete: 'CASCADE',
      },
      order_details: {
        type: Sequelize.JSONB,
        allowNull: false,
      },
      total_amount: {
        type: Sequelize.FLOAT,
        allowNull: false,
      },
      discount_amount: {
        type: Sequelize.FLOAT,
        allowNull: true,
      },
      service_charge_amount: {
        type: Sequelize.FLOAT,
        allowNull: true,
      },
      final_amount: {
        type: Sequelize.FLOAT,
        allowNull: false,
      },
      time_of_bill: {
        type: Sequelize.DATE,
        allowNull: false,
        defaultValue: Sequelize.NOW,
      },
      createdAt: {
        allowNull: false,
        type: Sequelize.DATE,
        defaultValue: Sequelize.NOW,
      },
      updatedAt: {
        allowNull: false,
        type: Sequelize.DATE,
        defaultValue: Sequelize.NOW,
      },
    });
  },
  down: async (queryInterface, Sequelize) => {
    await queryInterface.dropTable('Bills');
  },
};
