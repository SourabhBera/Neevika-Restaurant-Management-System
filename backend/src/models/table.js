// models/table.js

'use strict';

module.exports = (sequelize, DataTypes) => {
  const Table = sequelize.define('Table', {
    status: {
      type: DataTypes.STRING,
      defaultValue: 'free',
    },
    seatingCapacity: {
      type: DataTypes.INTEGER,
      defaultValue: 4,
    },
    seatingTime: {
      type: DataTypes.DATE,
      allowNull: true,
      defaultValue: null,
    },
    
    merged_with: {
      type: DataTypes.JSONB,
      allowNull: true,
      defaultValue: [],
    },

    food_bill_id: {
      type: DataTypes.INTEGER,
      allowNull: true,
    },

    bill_discount_details: {
      type: DataTypes.JSON,
      allowNull: true,
      defaultValue: null,
      comment: 'Stores discount info like { "type": "percent", "value": 10 } or { "type": "flat", "value": 200 }',
    },

    lottery_discount_detail: {
      type: DataTypes.JSON,
      allowNull: true,
      defaultValue: null,
      comment: 'Stores lottery discount details like { "discount": 10, "source": "QR", "profile": 3 }',
    },

    customer_id: {
      type: DataTypes.INTEGER,
      allowNull: true,
    },

    is_split: {
      type: DataTypes.BOOLEAN,
      allowNull: false,
      defaultValue: false,
    },
    parent_table_id: {
      type: DataTypes.INTEGER,
      allowNull: true,
    },
    split_name: {
      type: DataTypes.STRING,
      allowNull: true,
    },
    isComplimentary: {
      type: DataTypes.BOOLEAN,
      allowNull: false,
      defaultValue: false,
    },

    merged_at: {
      type: DataTypes.DATE,
      allowNull: true,
      defaultValue: null,
    },

    // NEW FIELD
    display_number: {
      type: DataTypes.INTEGER,
      allowNull: false,
    },
  });

  Table.associate = (models) => {
    Table.belongsTo(models.Section, {
      foreignKey: 'sectionId',
      as: 'section',
    });

    Table.hasMany(models.Table, {
      foreignKey: 'parent_table_id',
      as: 'splits',
    });

    Table.hasMany(models.Order, {
      foreignKey: 'table_number',
      as: 'orders',
    });

    Table.hasMany(models.DrinksOrder, {
      foreignKey: 'table_number',
      as: 'drinksOrders',
    });

    Table.hasMany(models.Bill, {
      foreignKey: 'table_number',
      sourceKey: 'id',
      as: 'bills',
    });
  };

  return Table;
};
