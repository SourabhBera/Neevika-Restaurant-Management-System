module.exports = (sequelize, DataTypes) => {
  const CustomerDetails = sequelize.define(
    'CustomerDetails',
    {
      customer_name: {
        type: DataTypes.STRING,
        allowNull: false,
      },
      customer_phoneNumber: {
        type: DataTypes.STRING,
        allowNull: false,
      },
      total_amount: {
        type: DataTypes.FLOAT,
        allowNull: false,
      },
      time_of_bill: {
        type: DataTypes.DATE,
        defaultValue: DataTypes.NOW,
      },
      user_id: {
        type: DataTypes.INTEGER,
        references: {
          model: 'Users', // Assuming waiter details are in 'Users' table
          key: 'id',
        },
      },
      table_number: {
        type: DataTypes.INTEGER,
        allowNull: false,
      },
      payment_method: {
        type: DataTypes.ENUM('cash', 'card', 'upi'),
        allowNull: false,
      },
    },
    {
      tableName: 'CustomerDetails',
    }
  );

  // Associations
  CustomerDetails.associate = (models) => {
    CustomerDetails.belongsTo(models.User, { foreignKey: 'user_id', as: 'waiter' });
    CustomerDetails.belongsTo(models.Table, { foreignKey: 'table_number', as: 'table' });
  };

  return CustomerDetails;
};
