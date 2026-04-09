module.exports = (sequelize, DataTypes) => {
  const Bill = sequelize.define('Bill', {
    waiter_id: {
      type: DataTypes.INTEGER,
      allowNull: false,
    },
    table_number: {
      type: DataTypes.INTEGER,
      allowNull: false,
    },
    customerDetails_id: {
      type: DataTypes.INTEGER,
      allowNull: false,
    },
    order_details: {
      type: DataTypes.JSON,
      allowNull: false,
    },
    total_amount: {
      type: DataTypes.FLOAT,
      allowNull: false,
    },
    discount_amount: {
      type: DataTypes.FLOAT,
      allowNull: false,
    },
    service_charge_amount: {
      type: DataTypes.FLOAT,
      allowNull: false,
    },
    tax_amount: {
      type: DataTypes.FLOAT,
      allowNull: false,
      defaultValue: 0,
    },
    vat_amount: {
      type: DataTypes.FLOAT,
      allowNull: false,
      defaultValue: 0,
    },
    final_amount: {
      type: DataTypes.FLOAT,
      allowNull: false,
    },
    time_of_bill: {
      type: DataTypes.DATE,
      allowNull: false,
      defaultValue: DataTypes.NOW,
    },
    payment_breakdown: {
      type: DataTypes.JSON,
      allowNull: false,
      defaultValue: {},
    },
    tip_amount: {
      type: DataTypes.FLOAT,
      allowNull: false,
      defaultValue: 0,
    },
    generated_at: {
      type: DataTypes.DATE,
      allowNull: false,
      defaultValue: DataTypes.NOW,
    },
    is_locked: {
      type: DataTypes.BOOLEAN,
      allowNull: false,
      defaultValue: false,
    },
    isComplimentary: {
      type: DataTypes.BOOLEAN,
      allowNull: false,
      defaultValue: false,
    },
    remark: {
      type: DataTypes.TEXT,
      allowNull: true,
    },

    // ➕ Newly added fields
    food_discount_percentage: {
      type: DataTypes.FLOAT,
      allowNull: false,
      defaultValue: 0,
    },
    drink_discount_percentage: {
      type: DataTypes.FLOAT,
      allowNull: false,
      defaultValue: 0,
    },
    food_discount_flat_amount: {
      type: DataTypes.FLOAT,
      allowNull: false,
      defaultValue: 0,
    },
    drink_discount_flat_amount: {
      type: DataTypes.FLOAT,
      allowNull: false,
      defaultValue: 0,
    },
    round_off: {
      type: DataTypes.TEXT,
      allowNull: true,
      defaultValue: "0",
    },

    // ✅ New field added for complimentary profile
    complimentary_profile_id: {
      type: DataTypes.INTEGER,
      allowNull: true,
      references: {
        model: 'ComplimentaryProfiles', // Table name
        key: 'id',
      },
      onUpdate: 'CASCADE',
      onDelete: 'SET NULL',
    },
  });

  Bill.associate = (models) => {
    Bill.belongsTo(models.CustomerDetails, {
      foreignKey: 'customerDetails_id',
      as: 'customerDetails',
    });

    Bill.belongsTo(models.Table, {
      foreignKey: 'table_number',
      targetKey: 'id',
      as: 'table',
    });

    Bill.belongsTo(models.User, {
      foreignKey: 'waiter_id',
      as: 'waiter',
    });

    // ✅ Complimentary Profile association
    Bill.belongsTo(models.ComplimentaryProfile, {
      foreignKey: 'complimentary_profile_id',
      as: 'complimentaryProfile',
    });
  };

  return Bill;
};
