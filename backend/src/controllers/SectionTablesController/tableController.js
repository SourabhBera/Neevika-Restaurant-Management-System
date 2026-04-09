const {
  Table,
  Section,
  Order,
  Menu,
  CustomerDetails,
  Bill,
  DrinksOrder,
  DrinksMenu,
  Category,
  User,
  DrinksCategory,
} = require("../../models");
const { sequelize } = require("../../models");
const { Op } = require('sequelize');


const cache = new Map();
const CACHE_TTL = 60000; // 1 minute

function getCached(key) {
  const item = cache.get(key);
  if (!item) return null;
  if (Date.now() - item.timestamp > CACHE_TTL) {
    cache.delete(key);
    return null;
  }
  return item.data;
}

function setCache(key, data) {
  cache.set(key, { data, timestamp: Date.now() });
}



const getTables = async (req, res) => {
  try {
    // Check cache first
    const cacheKey = 'all_tables';
    const cached = getCached(cacheKey);
    if (cached) {
      return res.status(200).json(cached);
    }

    // ✅ Single optimized query with proper includes
    const tables = await Table.findAll({
      attributes: [
        'id', 'sectionId', 'status', 'seatingCapacity',
        'seatingTime', 'display_number', 'parent_table_id',
        'is_split', 'split_name', 'merged_with'
      ],
      include: [
        {
          model: Section,
          as: 'section',
          attributes: ['id', 'name'],
        },
      ],
      order: [['display_number', 'ASC']],
    });

    // ✅ OPTIMIZATION: Batch fetch all orders for all tables
    const tableIds = tables.map(t => t.id);

    const [allOrders, allDrinks] = await Promise.all([
      Order.findAll({
        where: { table_number: tableIds },
        include: [
          { model: Menu, as: 'menu', attributes: ['id', 'name', 'price'] },
          { model: User, as: 'user', attributes: ['name'] },
        ],
        attributes: ['id', 'table_number', 'quantity', 'amount', 'status', 'is_custom', 'item_desc'],
      }),
      DrinksOrder.findAll({
        where: { table_number: tableIds },
        include: [
          { model: DrinksMenu, as: 'drink', attributes: ['id', 'name', 'price', 'applyVAT'] },
          { model: User, as: 'user', attributes: ['name'] },
        ],
        attributes: ['id', 'table_number', 'quantity', 'amount', 'status', 'is_custom', 'item_desc'],
      }),
    ]);

    // ✅ Group orders by table
    const ordersByTable = new Map();
    const drinksByTable = new Map();

    allOrders.forEach(order => {
      const tableId = order.table_number;
      if (!ordersByTable.has(tableId)) {
        ordersByTable.set(tableId, { pending: [], ongoing: [], complete: [] });
      }
      const groups = ordersByTable.get(tableId);
      if (order.status === 'pending') groups.pending.push(order);
      else if (order.status === 'accepted') groups.ongoing.push(order);
      else if (order.status === 'completed') groups.complete.push(order);
    });

    allDrinks.forEach(drink => {
      const tableId = drink.table_number;
      if (!drinksByTable.has(tableId)) {
        drinksByTable.set(tableId, { pending: [], ongoing: [], complete: [] });
      }
      const groups = drinksByTable.get(tableId);
      if (drink.status === 'pending') groups.pending.push(drink);
      else if (drink.status === 'accepted') groups.ongoing.push(drink);
      else if (drink.status === 'completed') groups.complete.push(drink);
    });

    // ✅ Build response efficiently
    const enrichedTables = tables.map(table => {
      const tableJson = table.toJSON();
      const orders = ordersByTable.get(table.id) || { pending: [], ongoing: [], complete: [] };
      const drinks = drinksByTable.get(table.id) || { pending: [], ongoing: [], complete: [] };

      // Calculate amounts
      const pendingAmount = orders.pending.reduce((sum, o) => sum + (o.amount || 0), 0);
      const ongoingAmount = orders.ongoing.reduce((sum, o) => sum + (o.amount || 0), 0);
      const completeAmount = orders.complete.reduce((sum, o) => sum + (o.amount || 0), 0);

      const pendingDrinksAmount = drinks.pending.reduce((sum, d) => sum + (d.amount || 0), 0);
      const ongoingDrinksAmount = drinks.ongoing.reduce((sum, d) => sum + (d.amount || 0), 0);
      const completeDrinksAmount = drinks.complete.reduce((sum, d) => sum + (d.amount || 0), 0);

      const totalAmount = Math.round(
        pendingAmount + ongoingAmount + completeAmount +
        pendingDrinksAmount + ongoingDrinksAmount + completeDrinksAmount
      );

      return {
        ...tableJson,
        orders: {
          pendingOrders: orders.pending,
          ongoingOrders: orders.ongoing,
          completeOrders: orders.complete,
        },
        drinksOrders: {
          pendingDrinksOrders: drinks.pending,
          ongoingDrinksOrders: drinks.ongoing,
          completeDrinksOrders: drinks.complete,
        },
        orderAmounts: {
          pendingAmount: Math.round(pendingAmount),
          ongoingAmount: Math.round(ongoingAmount),
          completeAmount: Math.round(completeAmount),
          pendingDrinksAmount: Math.round(pendingDrinksAmount),
          ongoingDrinksAmount: Math.round(ongoingDrinksAmount),
          completeDrinksAmount: Math.round(completeDrinksAmount),
          totalAmount,
        },
      };
    });

    // Cache results
    setCache(cacheKey, enrichedTables);

    return res.status(200).json(enrichedTables);
  } catch (error) {
    console.error('❌ Error in getTables:', error);
    return res.status(500).json({
      message: 'Error fetching tables',
      error: error.message
    });
  }
};


// Get table by ID
const getTableById = async (req, res) => {
  try {
    const { id } = req.params;

    const table = await Table.findByPk(id);
    if (!table) {
      return res.status(404).json({ message: "Table not found" });
    }

    const elapsedTime = table.seatingTime
      ? calculateElapsedTime(table.seatingTime)
      : "00:00:00";

    res.status(200).json({
      table: {
        id: table.id,
        status: table.status,
        seatingTime: table.seatingTime,
        elapsedTime,
      },
    });
  } catch (error) {
    console.error("Error fetching table details:", error);
    res
      .status(500)
      .json({ message: "Error fetching table details", error: error.message });
  }
};

// Create new table
const createTable = async (req, res) => {
  try {
    const { sectionId, status, seatingCapacity } = req.body;

    // Validate sectionId
    const section = await Section.findByPk(sectionId);
    if (!section) {
      return res.status(404).json({ message: "Section not found" });
    }

    // ✅ Get the next display number for this section
    const maxDisplayNumber = await Table.max('display_number', {
      where: { sectionId }
    });
    const nextDisplayNumber = (maxDisplayNumber || 0) + 1;

    const table = await Table.create({
      sectionId,
      status: status || "free",
      seatingCapacity: seatingCapacity || 4,
      display_number: nextDisplayNumber, // ✅ Add persistent display number
    });
    const io = req.app.get("io");
    if (io) {
      io.emit("table_created", {
        table: {
          id: table.id,
          sectionId: table.sectionId,
          display_number: table.display_number,
          status: table.status,
          seatingCapacity: table.seatingCapacity,
        },
        section: section ? { id: section.id, name: section.name } : null,
      });
    }
    res.status(201).json(table);
  } catch (error) {
    console.error("Error creating table:", error);
    res.status(500).json({ message: "Error creating table", error: error.message });
  }
};

// Update table
const updateTable = async (req, res) => {
  try {
    const { id } = req.params;
    const { status, seatingCapacity } = req.body;

    const table = await Table.findByPk(id);
    if (!table) return res.status(404).json({ message: "Table not found" });

    const oldStatus = table.status;

    await table.update({
      status: status || table.status,
      seatingCapacity: seatingCapacity || table.seatingCapacity,
    });

    const io = req.app.get("io");
    emitTableStatusChanged(io, table, oldStatus);

    res.status(200).json(table);
  } catch (error) {
    console.error("Error updating table:", error);
    res.status(500).json({ message: "Error updating table", error: error.message });
  }
};


// Delete table
const deleteTable = async (req, res) => {
  const transaction = await sequelize.transaction();
  try {
    const { id } = req.params;
    const tableId = Number(id);

    if (!Number.isInteger(tableId)) {
      await transaction.rollback();
      return res.status(400).json({ message: "Invalid table id" });
    }

    // Fetch the table (use transaction)
    const table = await Table.findByPk(tableId, { transaction });
    if (!table) {
      await transaction.rollback();
      return res.status(404).json({ message: "Table not found" });
    }

    // Snapshot table JSON for emit/response before destruction
    const tableSnapshot = table.toJSON();

    // 1) Delete any orders & drinks tied to this table (all statuses)
    // Defensive: remove any rows referencing this table number
    await Order.destroy({ where: { table_number: tableId }, transaction });
    await DrinksOrder.destroy({
      where: { table_number: tableId },
      transaction,
    });

    // 2) If this table is a parent (i.e. has splits), find and delete splits and their orders
    // We treat any row with parent_table_id === tableId as a split child
    const splitChildren = await Table.findAll({
      where: { parent_table_id: tableId },
      transaction,
    });

    const deletedSplitIds = [];
    if (splitChildren && splitChildren.length > 0) {
      for (const child of splitChildren) {
        const childId = child.id;

        // Defensive: clear orders for the split child
        await Order.destroy({ where: { table_number: childId }, transaction });
        await DrinksOrder.destroy({
          where: { table_number: childId },
          transaction,
        });

        // Destroy the split row
        await child.destroy({ transaction });
        deletedSplitIds.push(childId);
      }
    }

    // 3) Finally remove the main table row
    await table.destroy({ transaction });

    // Commit transaction
    await transaction.commit();

    // 4) Emit socket event so frontends can update their UI
    try {
      const io = req.app.get("io");
      if (io) {
        io.emit("delete_table", {
          tableId,
          sectionId: tableSnapshot.sectionId ?? null,
          parentTableId: tableSnapshot.parent_table_id ?? null,
          deletedTable: tableSnapshot,
          deletedSplitIds,
        });
      }
    } catch (emitErr) {
      // Do not fail the request on socket errors, but log them
      console.error("Socket emit error (delete_table):", emitErr);
    }

    // Respond
    return res.status(200).json({
      message: "Table deleted successfully",
      tableId,
      deletedSplits: deletedSplitIds,
      deletedTable: tableSnapshot,
    });
  } catch (error) {
    console.error("Error deleting table:", error);
    try {
      await transaction.rollback();
    } catch (rbErr) {
      console.error("Rollback error:", rbErr);
    }
    return res
      .status(500)
      .json({ message: "Error deleting table", error: error.message });
  }
};

// ✅ Get table info with ongoing orders and total amount
const getTableInfo = async (req, res) => {
  try {
    const { tableNumber } = req.params;
    // Fetch orders and drinks orders with proper includes
    const [
      pending_orders,
      ongoing_orders,
      complete_orders,
      pending_drinks,
      ongoing_drinks,
      complete_drinks,
    ] = await Promise.all([
      Order.findAll({
        where: { table_number: tableNumber, status: "pending" },
        include: [
          {
            model: Menu,
            as: "menu",
            attributes: ["name", "price"],
          },
          {
            model: User,
            as: "user",
            attributes: ["name"], // Include the user name here
          },
        ],
      }),
      Order.findAll({
        where: { table_number: tableNumber, status: "accepted" },
        include: [
          {
            model: Menu,
            as: "menu",
            attributes: ["name", "price"],
          },
          {
            model: User,
            as: "user",
            attributes: ["name"], // Include the user name here
          },
        ],
      }),
      Order.findAll({
        where: { table_number: tableNumber, status: "completed" },
        include: [
          {
            model: Menu,
            as: "menu",
            attributes: ["name", "price"],
          },
          {
            model: User,
            as: "user",
            attributes: ["name"], // Include the user name here
          },
        ],
      }),
      DrinksOrder.findAll({
        where: { table_number: tableNumber, status: "pending" },
        include: [
          {
            model: DrinksMenu,
            as: "drink", // ✅ Correct model and alias
            attributes: ["name", "price"],
          },
          {
            model: User,
            as: "user",
            attributes: ["name"], // Include the user name here
          },
        ],
      }),
      DrinksOrder.findAll({
        where: { table_number: tableNumber, status: "accepted" },
        include: [
          {
            model: DrinksMenu,
            as: "drink",
            attributes: ["name", "price"],
          },
          {
            model: User,
            as: "user",
            attributes: ["name"], // Include the user name here
          },
        ],
      }),
      DrinksOrder.findAll({
        where: { table_number: tableNumber, status: "completed" },
        include: [
          {
            model: DrinksMenu,
            as: "drink",
            attributes: ["name", "price"],
          },
          {
            model: User,
            as: "user",
            attributes: ["name"], // Include the user name here
          },
        ],
      }),
    ]);

    // Calculate totals
    const sum = (arr) => arr.reduce((total, o) => total + (o.amount || 0), 0);

    const pending_Amount = sum(pending_orders);
    const ongoing_Amount = sum(ongoing_orders);
    const complete_Amount = sum(complete_orders);
    const pending_Drinks_Amount = sum(pending_drinks);
    const ongoing_Drinks_Amount = sum(ongoing_drinks);
    const complete_Drinks_Amount = sum(complete_drinks);

    const total_Amount =
      pending_Amount +
      ongoing_Amount +
      complete_Amount +
      pending_Drinks_Amount +
      ongoing_Drinks_Amount +
      complete_Drinks_Amount;

    // Response
    res.status(200).json({
      tableNumber,
      pendingOrders: pending_orders,
      ongoingOrders: ongoing_orders,
      completeOrders: complete_orders,
      pendingDrinksOrders: pending_drinks,
      ongoingDrinksOrders: ongoing_drinks,
      completeDrinksOrders: complete_drinks,
      pendingAmount: pending_Amount,
      ongoingAmount: ongoing_Amount,
      completeAmount: complete_Amount,
      pendingDrinksAmount: pending_Drinks_Amount,
      ongoingDrinksAmount: ongoing_Drinks_Amount,
      completeDrinksAmount: complete_Drinks_Amount,
      totalAmount: total_Amount,
    });
  } catch (error) {
    console.error("Error fetching table info:", error);
    res.status(500).json({
      message: "Error fetching table information",
      error: error.message,
    });
  }
};



const transferTableOrders = async (req, res) => {
  const transaction = await sequelize.transaction();
  try {
    const { fromTableId, toTableId, fromSectionId, toSectionId } = req.body;

    // Parse section IDs
    const parsedFromSectionId = Number(fromSectionId);
    const parsedToSectionId = Number(toSectionId);

    // Parse display numbers (the visual table numbers shown to users)
    const fromDisplayNumber = Number(fromTableId);
    const toDisplayNumber = Number(toTableId);

    console.log("Transfer request:", {
      fromDisplayNumber,
      toDisplayNumber,
      fromSectionId: parsedFromSectionId,
      toSectionId: parsedToSectionId
    });

    // Validate inputs
    if (
      !Number.isInteger(fromDisplayNumber) ||
      !Number.isInteger(toDisplayNumber) ||
      !Number.isInteger(parsedFromSectionId) ||
      !Number.isInteger(parsedToSectionId)
    ) {
      await transaction.rollback();
      return res.status(400).json({
        message: "fromTableId, toTableId, fromSectionId, and toSectionId must be integers"
      });
    }

    if (fromDisplayNumber === toDisplayNumber && parsedFromSectionId === parsedToSectionId) {
      await transaction.rollback();
      return res.status(400).json({ message: "Cannot transfer table to itself" });
    }

    // ✅ Find tables by display_number + sectionId combination
    const fromTable = await Table.findOne({
      where: {
        display_number: fromDisplayNumber,
        sectionId: parsedFromSectionId
      },
      transaction,
      lock: transaction.LOCK.UPDATE,
    });

    const toTable = await Table.findOne({
      where: {
        display_number: toDisplayNumber,
        sectionId: parsedToSectionId
      },
      transaction,
      lock: transaction.LOCK.UPDATE,
    });

    if (!fromTable || !toTable) {
      await transaction.rollback();
      return res.status(404).json({
        message: "One or both tables not found. Please verify section and table numbers.",
        details: {
          fromTableFound: !!fromTable,
          toTableFound: !!toTable
        }
      });
    }

    // Get actual database IDs for the orders transfer
    const parsedFromTableId = fromTable.id;
    const parsedToTableId = toTable.id;

    console.log("Resolved table IDs:", {
      fromTable: { id: parsedFromTableId, display: fromDisplayNumber },
      toTable: { id: parsedToTableId, display: toDisplayNumber }
    });

    // Ensure destination table is free
    if (toTable.status !== "free") {
      await transaction.rollback();
      return res.status(400).json({
        message: `Destination table (${toSectionId}-T${toDisplayNumber}) must be free. Current status: ${toTable.status}`
      });
    }

    // Check if source table has any orders
    const activeOrders = await Order.findAll({
      where: { table_number: parsedFromTableId },
      transaction,
    });

    console.log(`Table number (${parsedFromTableId}) \n activeOrders : ${activeOrders}.`);


    const activeDrinks = await DrinksOrder.findAll({
      where: { table_number: parsedFromTableId },
      transaction,
    });

    if (activeOrders.length === 0 && activeDrinks.length === 0) {
      await transaction.rollback();
      return res.status(400).json({
        message: "No orders found on source table to transfer"
      });
    }

    const fromSection = fromTable.sectionId
      ? await Section.findByPk(fromTable.sectionId, { transaction })
      : null;
    const fromSectionName = fromSection?.name ?? '';

    // ✅ Build the label with section name
    const shiftedFromLabel = fromSectionName
      ? `${fromSectionName} Table ${fromDisplayNumber}`
      : `Table ${fromDisplayNumber}`;

    // Transfer food orders (using actual database IDs)
     await Order.update(
      {
        table_number: parsedToTableId,
        restaurent_table_number: String(toDisplayNumber),
        shifted_from_table: shiftedFromLabel,  // ✅ now "Garden Table 11"
      },
      { where: { table_number: parsedFromTableId }, transaction }
    );

    // Transfer drinks orders
    await DrinksOrder.update(
      {
        table_number: parsedToTableId,
        restaurant_table_number: String(toDisplayNumber),
        shifted_from_table: shiftedFromLabel,  // ✅ same label
      },
      { where: { table_number: parsedFromTableId }, transaction }
    );

    // Transfer table metadata
    toTable.seatingTime = fromTable.seatingTime || new Date();
    toTable.status = "occupied";
    toTable.food_bill_id = fromTable.food_bill_id;
    toTable.customer_id = fromTable.customer_id;
    toTable.bill_discount_details = fromTable.bill_discount_details;
    toTable.lottery_discount_detail = fromTable.lottery_discount_detail;
    toTable.isComplimentary = fromTable.isComplimentary;

    // Reset source table
    fromTable.status = "free";
    fromTable.seatingTime = null;
    fromTable.food_bill_id = null;
    fromTable.customer_id = null;
    fromTable.bill_discount_details = null;
    fromTable.lottery_discount_detail = null;
    fromTable.isComplimentary = false;
    fromTable.merged_with = null;

    await fromTable.save({ transaction });
    await toTable.save({ transaction });

    await transaction.commit();

    // Emit socket event with database IDs (for backend consistency)
    const io = req.app.get("io");
    if (io) {
      io.emit("transfer_table", {
        transferredOrderIds: activeOrders.map(o => o.id),
        transferredDrinkIds: activeDrinks.map(d => d.id),
        fromTable: {
          id: parsedFromTableId,
          display_number: fromDisplayNumber,
          sectionId: parsedFromSectionId,
          section_name: fromSectionName,   // ✅ ADD this
          status: "free",
        },
        toTable: {
          id: parsedToTableId,
          display_number: toDisplayNumber,
          sectionId: parsedToSectionId,
          status: "occupied",
        },

        food_bill_id: toTable.food_bill_id,
        customer_id: toTable.customer_id,
        orderCount: activeOrders.length + activeDrinks.length,
        timestamp: new Date().toISOString(),
      });
    }


    res.status(200).json({
      message: "Orders transferred successfully",
      transferredOrderCount: activeOrders.length,
      transferredDrinkCount: activeDrinks.length,
      fromTable: {
        databaseId: parsedFromTableId,
        displayNumber: fromDisplayNumber,
        section: parsedFromSectionId
      },
      toTable: {
        databaseId: parsedToTableId,
        displayNumber: toDisplayNumber,
        section: parsedToSectionId
      }
    });
  } catch (error) {
    console.error("Transfer error:", error);
    try {
      await transaction.rollback();
    } catch (rbErr) {
      console.error("Rollback error:", rbErr);
    }
    res.status(500).json({
      message: "Internal server error",
      error: error.message
    });
  }
};



// ===============================
// 🎯 Mark table as free
// ===============================
const markTableAsFree = async (req, res) => {
  try {
    const { id } = req.params;
    const table = await Table.findByPk(id);
    if (!table) return res.status(404).json({ message: "Table not found" });

    const oldStatus = table.status;

    await table.update({
      seatingTime: null,
      status: "free",
      merged_with: null,
      food_bill_id: null,
      bill_discount_details: null,
      lottery_discount_detail: null,
      customer_id: null,
      isComplimentary: false,
    });

    const io = req.app.get("io");
    emitTableStatusChanged(io, table, oldStatus);

    res.status(200).json({ message: "Table marked as free", table });
  } catch (error) {
    console.error("Error marking table as free:", error);
    res.status(500).json({ message: "Error marking table as free", error: error.message });
  }
};


// ===============================
// 🎯 Mark table as occupied
// ===============================
const markTableAsOccupied = async (req, res) => {
  try {
    const { id } = req.params;
    const table = await Table.findByPk(id);
    if (!table) return res.status(404).json({ message: "Table not found" });

    const oldStatus = table.status;

    if (table.status !== "occupied") {
      await table.update({
        status: "occupied",
        seatingTime: new Date(),
      });
    }

    const io = req.app.get("io");
    emitTableStatusChanged(io, table, oldStatus);

    res.status(200).json({
      message: "Table marked as occupied",
      table,
    });
  } catch (error) {
    console.error("Error marking table as occupied:", error);
    res.status(500).json({ message: "Error marking table as occupied", error: error.message });
  }
};

// ===============================
// ⏱️ Helper Function to Calculate Elapsed Time
// ===============================
const calculateElapsedTime = (seatingTime) => {
  const now = new Date();
  const diffInSeconds = Math.floor((now - new Date(seatingTime)) / 1000);

  const hours = Math.floor(diffInSeconds / 3600)
    .toString()
    .padStart(2, "0");
  const minutes = Math.floor((diffInSeconds % 3600) / 60)
    .toString()
    .padStart(2, "0");
  const seconds = (diffInSeconds % 60).toString().padStart(2, "0");

  return `${hours}:${minutes}:${seconds}`;
};



// ===============================
// 🎯 FIXED MERGE TABLE ORDERS
// ===============================
async function mergeTableOrders(req, res) {
  const transaction = await sequelize.transaction();
  try {
    const { primaryTableId, mergingTableId } = req.body;

    const primaryId = Number(primaryTableId);
    const mergingId = Number(mergingTableId);

    if (!primaryId || !mergingId || primaryId === mergingId) {
      throw new Error("Invalid table IDs");
    }

    const primary = await Table.findByPk(primaryId, {
      transaction,
      lock: transaction.LOCK.UPDATE,
    });

    const merging = await Table.findByPk(mergingId, {
      transaction,
      lock: transaction.LOCK.UPDATE,
    });

    if (!primary || !merging) {
      throw new Error("One or both tables not found");
    }

    if (merging.status === 'merged') {
      throw new Error(`Table ${merging.display_number} is already merged`);
    }

    const mergingFoodOrders = await Order.findAll({
      where: { table_number: mergingId },
      transaction,
    });

    const mergingDrinkOrders = await DrinksOrder.findAll({
      where: { table_number: mergingId },
      transaction,
    });

    const mergingOrderCount =
      mergingFoodOrders.length + mergingDrinkOrders.length;

    await Order.update(
      {
        table_number: primaryId,
        section_number: primary.sectionId,
        merged_from_table: mergingId,
      },
      { where: { table_number: mergingId }, transaction }
    );

    await DrinksOrder.update(
      {
        table_number: primaryId,
        section_number: primary.sectionId,
        merged_from_table: mergingId,
      },
      { where: { table_number: mergingId }, transaction }
    );

    const mergedWithArray = Array.isArray(primary.merged_with)
      ? [...new Set([...primary.merged_with, mergingId])]
      : [mergingId];

    primary.merged_with = mergedWithArray;
    primary.status = "occupied";
    await primary.save({ transaction });

    merging.status = "merged";
    merging.merged_with = [primaryId];
    merging.merged_at = new Date();
    merging.seatingTime = null;
    merging.food_bill_id = null;
    merging.customer_id = null;
    await merging.save({ transaction });

    // ✅ COMMIT ONLY AFTER ALL DB WORK
    await transaction.commit();

    // 🔊 SOCKETS AFTER COMMIT
    const io = req.app.get("io");
    if (io) {
      io.emit("merge_table", {
        primaryTableId: primaryId,
        primaryTableDisplay: primary.display_number,
        mergingTableId: mergingId,
        mergingTableDisplay: merging.display_number,
        primaryStatus: primary.status,
        mergingStatus: merging.status,
        orderCount: mergingOrderCount,
        sectionId: primary.sectionId,
        timestamp: new Date().toISOString(),
      });
    }

    return res.json({
      message: "Tables merged successfully",
      movedOrders: mergingOrderCount,
    });

  } catch (err) {
    // ✅ SAFE ROLLBACK
    if (!transaction.finished) {
      await transaction.rollback();
    }

    console.error("❌ Merge error:", err);
    return res.status(500).json({
      message: "Merge failed",
      error: err.message,
    });
  }
}



// ===============================
// 🎯 FIXED DEMERGE TABLE ORDERS
// ===============================
async function demergeTableOrders(req, res) {
  const t = await sequelize.transaction();
  let committed = false;

  try {
    console.log('\n================ DEMERGE START ================');

    const { primaryTableId, mergingTableId } = req.body;
    const primaryId = Number(primaryTableId);
    const mergingId = Number(mergingTableId);

    console.log('🟢 Incoming Demerge Request');
    console.log('   ➤ Primary Table ID:', primaryId);
    console.log('   ➤ Merging Table ID:', mergingId);

    if (!primaryId || !mergingId || primaryId === mergingId) {
      await t.rollback();
      return res.status(400).json({ message: 'Invalid table IDs' });
    }

    // 🔒 Lock both tables
    const primary = await Table.findByPk(primaryId, {
      transaction: t,
      lock: t.LOCK.UPDATE,
    });

    const merging = await Table.findByPk(mergingId, {
      transaction: t,
      lock: t.LOCK.UPDATE,
    });

    if (!primary || !merging) {
      await t.rollback();
      return res.status(404).json({ message: 'Table not found' });
    }

    console.log('🪑 Primary Table:', {
      id: primary.id,
      status: primary.status,
      merged_with: primary.merged_with,
    });

    console.log('🪑 Merging Table:', {
      id: merging.id,
      status: merging.status,
      merged_with: merging.merged_with,
    });

    // 🔗 Validate merge relationship
    const primaryMergedWith = Array.isArray(primary.merged_with)
      ? primary.merged_with
      : primary.merged_with != null
        ? [primary.merged_with]
        : [];

    const mergingMergedWith = Array.isArray(merging.merged_with)
      ? merging.merged_with
      : merging.merged_with != null
        ? [merging.merged_with]
        : [];

    console.log('🔗 Merge Relationship Check');
    console.log('   Primary merged_with:', primaryMergedWith);
    console.log('   Merging merged_with:', mergingMergedWith);

    if (
      !primaryMergedWith.includes(mergingId) ||
      !mergingMergedWith.includes(primaryId)
    ) {
      await t.rollback();
      return res.status(400).json({ message: 'Invalid merge relationship' });
    }

    console.log('✅ Merge relationship verified');

    // =====================================================
    // 🔥 FIND ORDERS TO RESTORE BACK TO PRIMARY TABLE
    // These are orders that were moved from primary → merging during merge
    // =====================================================

    const foodOrdersToRestore = await Order.findAll({
      where: {
        table_number: mergingId,
        merged_from_table: primaryId,
      },
      transaction: t,
      lock: t.LOCK.UPDATE,
    });

    const drinkOrdersToRestore = await DrinksOrder.findAll({
      where: {
        table_number: mergingId,
        merged_from_table: primaryId,
      },
      transaction: t,
      lock: t.LOCK.UPDATE,
    });

    console.log('📦 Orders to restore');
    console.log('   🍽 Food Orders:', foodOrdersToRestore.length);
    console.log('   🥤 Drink Orders:', drinkOrdersToRestore.length);

    // 🔄 Restore FOOD orders back to primary table
    for (const order of foodOrdersToRestore) {
      console.log(`   ↩ Restoring FOOD order ${order.id} → table ${primaryId}`);
      await order.update(
        { table_number: primaryId, merged_from_table: null },
        { transaction: t }
      );
    }

    // 🔄 Restore DRINK orders back to primary table
    for (const order of drinkOrdersToRestore) {
      console.log(`   ↩ Restoring DRINK order ${order.id} → table ${primaryId}`);
      await order.update(
        { table_number: primaryId, merged_from_table: null },
        { transaction: t }
      );
    }

    const restoredCount = foodOrdersToRestore.length + drinkOrdersToRestore.length;

    // =====================================================
    // 📊 Check remaining orders on MERGING table
    // =====================================================

    const remainingFoodOnMerging = await Order.count({
      where: { table_number: mergingId, merged_from_table: null },
      transaction: t,
    });

    const remainingDrinksOnMerging = await DrinksOrder.count({
      where: { table_number: mergingId, merged_from_table: null },
      transaction: t,
    });

    const mergingRemainingCount = remainingFoodOnMerging + remainingDrinksOnMerging;
    console.log('📊 Remaining on merging table:', mergingRemainingCount);

    // =====================================================
    // 🧹 Update PRIMARY table
    // =====================================================

    primary.merged_with = primaryMergedWith.filter((id) => id !== mergingId);

    if (primary.merged_with.length === 0) {
      primary.merged_with = null;
      primary.merged_at = null;
    }

    primary.status = 'occupied';
    primary.seatingTime = primary.seatingTime || new Date();

    await primary.save({ transaction: t });
    console.log(`🪑 Primary table ${primaryId} → occupied`);

    // =====================================================
    // 🧹 Update MERGING table
    // =====================================================

    if (mergingRemainingCount > 0) {
      merging.status = 'occupied';
      merging.seatingTime = merging.seatingTime || new Date();
    } else {
      merging.status = 'free';
      merging.seatingTime = null;
    }

    merging.merged_with = null;
    merging.merged_at = null;

    await merging.save({ transaction: t });
    console.log(`🪑 Merging table ${mergingId} → ${merging.status} (remaining: ${mergingRemainingCount})`);

    // =====================================================
    // ✅ Commit transaction BEFORE fetching socket data
    // =====================================================

    await t.commit();
    committed = true;

    console.log('✅ TRANSACTION COMMITTED');
    console.log('================ DEMERGE END =================\n');

    // =====================================================
    // 📡 Fetch final DB state AFTER commit, then emit socket
    // This ensures frontend gets authoritative order data
    // and never needs to call fetchSections()
    // =====================================================

    try {
      const io = req.app.get('io');
      if (io) {

        // Fetch primary table's current orders (all statuses)
        const [primaryFoodOrders, primaryDrinkOrders] = await Promise.all([
          Order.findAll({
            where: { table_number: primaryId },
            include: [
              { model: Menu, as: 'menu', attributes: ['id', 'name', 'price'] },
            ],
            attributes: [
              'id', 'table_number', 'quantity', 'amount', 'status',
              'is_custom', 'item_desc', 'kotNumber', 'merged_from_table',
            ],
            order: [['createdAt', 'ASC']],
          }),
          DrinksOrder.findAll({
            where: { table_number: primaryId },
            include: [
              { model: DrinksMenu, as: 'drink', attributes: ['id', 'name', 'price', 'applyVAT'] },
            ],
            attributes: [
              'id', 'table_number', 'quantity', 'amount', 'status',
              'is_custom', 'item_desc', 'kotNumber', 'merged_from_table', 'applyVAT',
            ],
            order: [['createdAt', 'ASC']],
          }),
        ]);

        // Fetch merging table's current orders (all statuses)
        const [mergingFoodOrders, mergingDrinkOrders] = await Promise.all([
          Order.findAll({
            where: { table_number: mergingId },
            include: [
              { model: Menu, as: 'menu', attributes: ['id', 'name', 'price'] },
            ],
            attributes: [
              'id', 'table_number', 'quantity', 'amount', 'status',
              'is_custom', 'item_desc', 'kotNumber', 'merged_from_table',
            ],
            order: [['createdAt', 'ASC']],
          }),
          DrinksOrder.findAll({
            where: { table_number: mergingId },
            include: [
              { model: DrinksMenu, as: 'drink', attributes: ['id', 'name', 'price', 'applyVAT'] },
            ],
            attributes: [
              'id', 'table_number', 'quantity', 'amount', 'status',
              'is_custom', 'item_desc', 'kotNumber', 'merged_from_table', 'applyVAT',
            ],
            order: [['createdAt', 'ASC']],
          }),
        ]);

        // Helper: convert Sequelize instances to plain JSON
        const toJson = (arr) => arr.map((o) => (o.toJSON ? o.toJSON() : { ...o }));

        // Helper: bucket food orders by status
        const bucketFood = (arr) => ({
          pendingOrders:  toJson(arr.filter((o) => o.status === 'pending')),
          ongoingOrders:  toJson(arr.filter((o) => o.status === 'accepted')),
          completeOrders: toJson(arr.filter((o) => o.status === 'completed')),
        });

        // Helper: bucket drink orders by status
        const bucketDrink = (arr) => ({
          pendingDrinksOrders:  toJson(arr.filter((o) => o.status === 'pending')),
          ongoingDrinksOrders:  toJson(arr.filter((o) => o.status === 'accepted')),
          completeDrinksOrders: toJson(arr.filter((o) => o.status === 'completed')),
        });

        // Helper: sum amounts
        const sumAmount = (arr) =>
          arr.reduce((s, o) => s + (Number(o.amount) || 0), 0);

        const primaryTotalAmount = Math.round(
          sumAmount(primaryFoodOrders) + sumAmount(primaryDrinkOrders)
        );
        const mergingTotalAmount = Math.round(
          sumAmount(mergingFoodOrders) + sumAmount(mergingDrinkOrders)
        );

        console.log(`📊 Primary total after demerge: ₹${primaryTotalAmount}`);
        console.log(`📊 Merging total after demerge: ₹${mergingTotalAmount}`);

        io.emit('demerge_table', {
          primaryTableId: primaryId,
          mergingTableId: mergingId,

          // ✅ Correct statuses derived from actual remaining orders
          primaryTableStatus: primaryTotalAmount > 0 ? 'occupied' : 'free',
          mergingTableStatus: mergingTotalAmount > 0 ? 'occupied' : 'free',

          primaryOrderCount: primaryFoodOrders.length + primaryDrinkOrders.length,
          mergingOrderCount: mergingFoodOrders.length  + mergingDrinkOrders.length,

          // ✅ Full bucketed order data — frontend replaces state directly
          primaryOrders:       bucketFood(primaryFoodOrders),
          primaryDrinksOrders: bucketDrink(primaryDrinkOrders),
          mergingOrders:       bucketFood(mergingFoodOrders),
          mergingDrinksOrders: bucketDrink(mergingDrinkOrders),

          // ✅ Pre-computed totals so frontend doesn't need to recalculate
          primaryTotalAmount,
          mergingTotalAmount,

          restoredOrders: restoredCount,
          sectionId: primary.sectionId,
          timestamp: new Date().toISOString(),
        });

        console.log('📡 Socket event emitted with full order data');
      }
    } catch (e) {
      console.warn('⚠️ Socket emit failed:', e.message);
    }

    return res.json({
      message: 'Tables demerged successfully',
      restoredOrders: restoredCount,
    });

  } catch (err) {
    if (!committed) await t.rollback();
    console.error('❌ DEMERGE FAILED:', err);
    return res.status(500).json({
      message: 'Demerge failed',
      error: err.message,
    });
  }
}



// ===============================
// 🎯 SHIFT ORDERS BETWEEN TABLES
// ===============================  

const shiftOrders = async (req, res) => {
  const transaction = await sequelize.transaction();

  try {
    const { fromTableId, toTableId, orderIds, orderType, quantity } = req.body;

    console.log('📦 Shift request:', {
      fromTableId,
      toTableId,
      orderIds,
      orderType,
      quantity,
    });

    /* -------------------- VALIDATION -------------------- */

    if (!fromTableId || !toTableId || !orderIds || !orderType) {
      await transaction.rollback();
      return res.status(400).json({ message: 'Missing required fields' });
    }

    if (fromTableId === toTableId) {
      await transaction.rollback();
      return res
        .status(400)
        .json({ message: 'Cannot shift orders to the same table' });
    }

    if (!['food', 'drink'].includes(orderType)) {
      await transaction.rollback();
      return res.status(400).json({ message: 'Invalid order type' });
    }

    const fromId = Number(fromTableId);
    const toId = Number(toTableId);

    if (!Number.isInteger(fromId) || !Number.isInteger(toId)) {
      await transaction.rollback();
      return res.status(400).json({ message: 'Invalid table IDs' });
    }

    /* -------------------- LOCK TABLES -------------------- */

    const fromTable = await Table.findByPk(fromId, {
      transaction,
      lock: transaction.LOCK.UPDATE,
    });

    const toTable = await Table.findByPk(toId, {
      transaction,
      lock: transaction.LOCK.UPDATE,
    });

    if (!fromTable || !toTable) {
      await transaction.rollback();
      return res
        .status(404)
        .json({ message: 'One or both tables not found' });
    }

    /* -------------------- FETCH SECTIONS -------------------- */

    const fromSection = fromTable.sectionId
      ? await Section.findByPk(fromTable.sectionId, { transaction })
      : null;

    const toSection = toTable.sectionId
      ? await Section.findByPk(toTable.sectionId, { transaction })
      : null;

    const shiftedFromTableLabel = `${fromSection?.name || 'Section'
      } - Table ${fromTable.display_number}`;

    console.log('✅ Tables locked:', {
      from: {
        id: fromTable.id,
        display: fromTable.display_number,
        section: fromSection?.name,
      },
      to: {
        id: toTable.id,
        display: toTable.display_number,
        section: toSection?.name,
      },
    });

    /* -------------------- MODEL MAPPING -------------------- */

    const OrderModel = orderType === 'food' ? Order : DrinksOrder;

    const orderField =
      orderType === 'food' ? 'menuId' : 'drinksMenuId';

    const tableNumberField =
      orderType === 'food'
        ? 'restaurent_table_number' // food typo (existing schema)
        : 'restaurant_table_number'; // drinks correct spelling

    const parsedOrderIds = Array.isArray(orderIds)
      ? orderIds.map(Number).filter(Number.isInteger)
      : [Number(orderIds)].filter(Number.isInteger);

    if (parsedOrderIds.length === 0) {
      await transaction.rollback();
      return res
        .status(400)
        .json({ message: 'No valid order IDs provided' });
    }

    /* -------------------- FETCH ORDERS -------------------- */

    console.log('🔍 Fetching orders:', {
      parsedOrderIds,
      fromId,
      orderType,
    });

    const ordersToShift = await OrderModel.findAll({
      where:
        orderType === 'drink'
          ? {
              id: parsedOrderIds,
              [Op.or]: [
                { table_number: fromId },
                { restaurant_table_number: String(fromTable.display_number) }, // ✅ cast to string
              ],
            }
          : {
              id: parsedOrderIds,
              table_number: fromId,
            },
      transaction,
    });

    if (!ordersToShift.length) {
      await transaction.rollback();
      return res
        .status(404)
        .json({ message: 'No orders found to shift' });
    }

    /* -------------------- 🔥 NEW: GENERATE SHIFTED KOT NUMBER -------------------- */

    // ✅ Get the original KOT number from the first order
    const originalKotNumber = ordersToShift[0].kotNumber || ordersToShift[0].id;

    // ✅ Generate new KOT number with _SHIFTED suffix
    // Format: <original_kot>_SHIFTED_<timestamp>
    const shiftedKotNumber = `${originalKotNumber}`;

    console.log('🔄 Generated shifted KOT:', {
      original: originalKotNumber,
      shifted: shiftedKotNumber,
    });

    /* -------------------- SHIFT LOGIC -------------------- */

    let totalShiftedAmount = 0;
    const shiftedOrderIds = [];
    const shiftedOrderDetails = []; // ✅ NEW: Track shifted order details for socket

    for (const order of ordersToShift) {
      const orderQty = Number(order.quantity) || 1;
      const qtyToShift = Math.min(
        Number(quantity) || orderQty,
        orderQty
      );

      if (qtyToShift <= 0) continue;

      const amountPerUnit = Number(order.amount) / orderQty;
      const shiftAmount = amountPerUnit * qtyToShift;

      // ✅ UPDATED: Base payload with new shifted KOT tracking
      const tablePayload = {
        table_number: toId,
        section_number: toTable.sectionId,
        merged_from_table: null, // ✅ Clear any merge tracking
        shifted_from_table: shiftedFromTableLabel,
        [tableNumberField]: toTable.display_number,
        kotNumber: shiftedKotNumber, // ✅ NEW: Assign new KOT number
        original_kot_number: originalKotNumber, // ✅ NEW: Store original for reference
        is_shifted: true, // ✅ NEW: Flag to prevent re-merging
      };

      if (qtyToShift === orderQty) {
        // ✅ FULL SHIFT - Update existing order
        await order.update(tablePayload, { transaction });

        totalShiftedAmount += shiftAmount;
        shiftedOrderIds.push(order.id);

        // ✅ NEW: Track shifted order details
        shiftedOrderDetails.push({
          id: order.id,
          kotNumber: shiftedKotNumber,
          originalKotNumber: originalKotNumber,
          quantity: qtyToShift,
          amount: shiftAmount,
        });
      } else {
        // ✅ SPLIT ORDER - Create new order for shifted portion

        // Update original order (reduce quantity)
        await order.update(
          {
            quantity: orderQty - qtyToShift,
            amount: amountPerUnit * (orderQty - qtyToShift),
          },
          { transaction }
        );

        // Create new order for shifted portion
        const newOrder = await OrderModel.create(
          {
            userId: order.userId,
            [orderField]: order[orderField],
            item_desc: order.item_desc,
            quantity: qtyToShift,
            status: order.status,
            amount: shiftAmount,
            is_custom: order.is_custom,
            kotNumber: shiftedKotNumber, // ✅ NEW: New KOT number
            original_kot_number: originalKotNumber, // ✅ NEW: Original KOT reference
            is_shifted: true, // ✅ NEW: Mark as shifted
            ...tablePayload,
          },
          { transaction }
        );

        totalShiftedAmount += shiftAmount;
        shiftedOrderIds.push(newOrder.id);

        // ✅ NEW: Track shifted order details
        shiftedOrderDetails.push({
          id: newOrder.id,
          kotNumber: shiftedKotNumber,
          originalKotNumber: originalKotNumber,
          quantity: qtyToShift,
          amount: shiftAmount,
        });
      }
    }

    /* -------------------- UPDATE TABLE STATUS -------------------- */

    const remainingFood = await Order.count({
      where: { table_number: fromId },
      transaction,
    });

    const remainingDrinks = await DrinksOrder.count({
      where: { table_number: fromId },
      transaction,
    });

    if (remainingFood === 0 && remainingDrinks === 0) {
      await fromTable.update(
        { status: 'free', seatingTime: null },
        { transaction }
      );
    }

    if (toTable.status === 'free') {
      await toTable.update(
        {
          status: 'occupied',
          seatingTime: toTable.seatingTime || new Date(),
        },
        { transaction }
      );
    }

    /* -------------------- COMMIT -------------------- */

    await transaction.commit();

    /* -------------------- 🔥 ENHANCED SOCKET EVENT -------------------- */

    const io = req.app.get('io');
    if (io) {
      const socketEvent =
        orderType === 'drink'
          ? 'drinks_order_shifted'
          : 'order_shifted';

      // ✅ ENHANCED: Include shifted KOT number and order details
      io.emit(socketEvent, {
        fromTableId: fromTable.display_number,
        toTableId: toTable.display_number,
        fromSectionName: fromSection?.name,
        toSectionName: toSection?.name,
        orderIds: shiftedOrderIds,
        orderType,
        shiftedAmount: totalShiftedAmount,
        // ✅ NEW: Include shifted KOT tracking
        shiftedKotNumber: shiftedKotNumber,
        originalKotNumber: originalKotNumber,
        shiftedOrderDetails: shiftedOrderDetails, // ✅ NEW: Detailed order info
        timestamp: new Date().toISOString(),
      });

      console.log('📡 Emitted shift event:', {
        event: socketEvent,
        shiftedKotNumber,
        orderCount: shiftedOrderIds.length,
      });
    }

    /* -------------------- RESPONSE -------------------- */

    return res.status(200).json({
      message: 'Orders shifted successfully',
      shiftedOrders: shiftedOrderIds.length,
      totalAmount: totalShiftedAmount,
      shiftedKotNumber: shiftedKotNumber, // ✅ NEW: Return shifted KOT number
      originalKotNumber: originalKotNumber, // ✅ NEW: Return original KOT
      shiftedOrderDetails: shiftedOrderDetails, // ✅ NEW: Return detailed info
    });
  } catch (error) {
    console.error('❌ Error shifting orders:', error);
    await transaction.rollback();

    return res.status(500).json({
      message: 'Error shifting orders',
      error: error.message,
    });
  }
};




// ===============================
// 🎯 Mark table as reserved
// ===============================
const markTableAsReserved = async (req, res) => {
  try {
    const { id } = req.params;
    console.log(id);
    const table = await Table.findByPk(id);
    if (!table) {
      return res.status(404).json({ message: "Table not found" });
    }

    await table.update({ status: "reserved" });

    const io = req.app.get("io");
    io.emit("reserve_table", {
      TableId: id,
      SectionId: table.sectionId,
      status: table.status,
      status: "reserved",
    });

    res.status(200).json({ message: "Table marked as reserved", table });
  } catch (error) {
    console.error("Error marking table as reserved:", error);
    res.status(500).json({
      message: "Error marking table as reserved",
      error: error.message,
    });
  }
};



const getBills = async (req, res) => {
  try {
    const billItems = await Bill.findAll({
      order: [["id", "ASC"]],
      include: [
        {
          model: Table,
          as: "table",
          attributes: ["display_number"],
          include: [
            {
              model: Section,
              as: "section",
              attributes: ["name"],
            },
          ],
        },
      ],
    });

    const response = billItems.map((bill) => ({
      ...bill.toJSON(),
      section_name: bill.table?.section?.name || null,
      display_number: bill.table?.display_number || null,
    }));

    res.status(200).json(response);
  } catch (error) {
    console.error("Error fetching bills:", error);
    res.status(500).json({ message: "Error fetching bills", error });
  }
};



const getBillById = async (req, res) => {
  try {
    const { id } = req.params;

    const billItem = await Bill.findByPk(id, {
      include: [
        {
          model: User,
          as: "waiter",
          attributes: ["name"],
        },
        {
          model: Table,
          as: "table",
          attributes: ["display_number"],
          include: [
            {
              model: Section,
              as: "section",
              attributes: ["name"],
            },
          ],
        },
      ],
    });

    if (!billItem) {
      return res.status(404).json({ message: "Bill not found" });
    }

    const response = {
      ...billItem.toJSON(),
      waiter_name: billItem.waiter ? billItem.waiter.name : null,
      section_name: billItem.table?.section?.name || null,
      display_number: billItem.table?.display_number || null,
    };

    res.status(200).json(response);
  } catch (error) {
    console.error("Error fetching bill by ID:", error);
    res.status(500).json({ message: "Error fetching bill by ID", error });
  }
};



// ===============================
// 🎯 Generate bill for the table
// ===============================


// Helper
const isTruthy = (v) => v === true || v === "true" || v === 1 || v === "1";


const getOrCreateDuplicateTable = async (parentTableId, transaction) => {
  const parentTable = await Table.findByPk(parentTableId, { transaction });
  if (!parentTable) throw new Error("Parent table not found");

  // Get existing duplicates for this parent
  const existingDuplicates = await Table.findAll({
    where: {
      parent_table_id: parentTableId,
      is_split: true
    },
    order: [['split_name', 'ASC']],
    transaction
  });

  // Generate next split name (A, B, C, etc.)
  const nextLetter = String.fromCharCode(65 + existingDuplicates.length); // A=65

  // Create new duplicate
  const duplicate = await Table.create({
    sectionId: parentTable.sectionId,
    status: "occupied",
    seatingCapacity: parentTable.seatingCapacity,
    seatingTime: new Date(),
    display_number: parentTable.display_number,
    is_split: true,
    parent_table_id: parentTableId,
    split_name: nextLetter,
  }, { transaction });

  const io = req.app.get("io");
  if (io) {
    io.emit("auto_split_table_created", {
      newTable: duplicate.toJSON(),
      parentTableId: parentTable.id,
      sectionId: parentTable.sectionId,
      timestamp: new Date().toISOString(),
    });
  }

  return duplicate;
};



const generateTableBill = async (req, res) => {
  const transaction = await sequelize.transaction();

  try {
    const { tableNumber } = req.params;
    const {
      customer_name,
      customer_phoneNumber,
      discount = {},
      user_id,
      serviceCharge = 0,
      vat = 0,
      cgst = 0,
      sgst = 0,
      roundOff = 0,
      payment_method,
      isComplimentary = false,
      complimentary_remark = "",
      complimentary_profile_id
    } = req.body;

    // Validation
    if (!customer_name || !customer_phoneNumber || !payment_method || !user_id) {
      await transaction.rollback();
      return res.status(400).json({
        message: "Required fields missing",
      });
    }

    const tableId = parseInt(tableNumber);
    if (isNaN(tableId)) {
      await transaction.rollback();
      return res.status(400).json({ message: "Invalid table number" });
    }

    // ✅ Lock table for update
    const table = await Table.findOne({
      where: { id: tableId },
      transaction,
      lock: transaction.LOCK.UPDATE,
    });

    if (!table) {
      await transaction.rollback();
      return res.status(404).json({ message: "Table not found" });
    }

    if (table.food_bill_id) {
      await transaction.rollback();
      return res.status(400).json({ message: "Bill already exists" });
    }

    // Check for open orders
    const [openOrders, openDrinks] = await Promise.all([
      Order.findOne({
        where: { table_number: tableId, status: { [Op.ne]: "completed" } },
        transaction,
      }),
      DrinksOrder.findOne({
        where: { table_number: tableId, status: { [Op.ne]: "completed" } },
        transaction,
      }),
    ]);

    if (openOrders || openDrinks) {
      await transaction.rollback();
      return res.status(400).json({
        message: "Cannot generate bill with pending/accepted orders",
      });
    }

    // Get completed orders
    const [completedOrders, completedDrinks] = await Promise.all([
      Order.findAll({
        where: { table_number: tableId, status: "completed" },
        include: [{ model: Menu, as: "menu", attributes: ["name", "price"] }],
        transaction,
      }),
      DrinksOrder.findAll({
        where: { table_number: tableId, status: "completed" },
        include: [{ model: DrinksMenu, as: "drink", attributes: ["name", "price", "applyVAT"] }],
        transaction,
      }),
    ]);

    if (completedOrders.length === 0 && completedDrinks.length === 0) {
      await transaction.rollback();
      return res.status(404).json({ message: "No completed orders" });
    }

    // Calculate totals
    const foodTotal = completedOrders.reduce((sum, o) => sum + (parseFloat(o.amount) || 0), 0);
    const drinksTotal = completedDrinks.reduce((sum, d) => sum + (parseFloat(d.amount) || 0), 0);
    const subtotal = foodTotal + drinksTotal;

    // Calculate discounts
    const foodDiscountAmt = discount?.food?.type === "percent"
      ? (foodTotal * (parseFloat(discount.food.value) || 0)) / 100
      : parseFloat(discount?.food?.value || 0);

    const drinkDiscountAmt = discount?.drinks?.type === "percent"
      ? (drinksTotal * (parseFloat(discount.drinks.value) || 0)) / 100
      : parseFloat(discount?.drinks?.value || 0);

    const totalDiscount = foodDiscountAmt + drinkDiscountAmt;

    // Service charge
    const serviceChargeAmount = Math.round(
      ((subtotal - totalDiscount) * (parseFloat(serviceCharge) || 0)) / 100
    );

    // Taxes (already absolute)
    const cgstAmount = Math.round(parseFloat(cgst) || 0);
    const sgstAmount = Math.round(parseFloat(sgst) || 0);
    const vatAmount = Math.round(parseFloat(vat) || 0);
    const roundOffValue = Number(roundOff) || 0;

    // Final amount
    const finalAmount = Math.round(
      subtotal - totalDiscount + serviceChargeAmount +
      cgstAmount + sgstAmount + vatAmount + roundOffValue
    );

    // Build bill details
    const billDetails = [
      ...completedOrders.map(o => ({
        type: "food",
        item: o.menu?.name || o.item_desc || "Unknown",
        quantity: parseInt(o.quantity) || 1,
        pricePerUnit: parseFloat(o.menu?.price) || 0,
        totalAmount: parseFloat(o.amount) || 0,
      })),
      ...completedDrinks.map(d => ({
        type: "drink",
        item: d.drink?.name || d.item_desc || "Unknown",
        quantity: parseInt(d.quantity) || 1,
        pricePerUnit: parseFloat(d.drink?.price) || 0,
        totalAmount: parseFloat(d.amount) || 0,
        applyVAT: !!d.drink?.applyVAT,
      })),
    ];

    // Create customer
    const customerDetails = await CustomerDetails.create({
      customer_name: customer_name.trim(),
      customer_phoneNumber: customer_phoneNumber.trim(),
      total_amount: finalAmount,
      time_of_bill: new Date(),
      user_id,
      table_number: tableId,
      payment_method,
    }, { transaction });

    // Create bill
    const bill = await Bill.create({
      waiter_id: user_id,
      table_number: tableId,
      customerDetails_id: customerDetails.id,
      order_details: billDetails,
      total_amount: subtotal,
      discount_amount: totalDiscount,
      service_charge_amount: serviceChargeAmount,
      tax_amount: cgstAmount + sgstAmount,
      vat_amount: vatAmount,
      final_amount: finalAmount,
      round_off: roundOffValue.toString(),
      time_of_bill: new Date(),
      generated_at: new Date(),
      isComplimentary: !!isComplimentary,
      remark: complimentary_remark,
      complimentary_profile_id,
      is_locked: false,
    }, { transaction });

    // Update table
    await table.update({
      status: "settleUp",
      food_bill_id: bill.id,
      bill_discount_details: discount,
      customer_id: customerDetails.id,
      isComplimentary: !!isComplimentary,
    }, { transaction });

    await transaction.commit();

    // Clear cache
    cache.delete('all_tables');

    // ✅ EMIT SOCKET EVENT (Added/Fixed)
    const io = req.app.get("io");
    if (io) {
      io.emit("bill_generated", {
        tableId: tableId,
        billId: bill.id,
        status: "settleUp",
        finalAmount: finalAmount,
        customerName: customer_name,
        timestamp: new Date().toISOString(),
      });

      console.log(`✅ Emitted bill_generated for table ${tableId}`);
    }

    return res.status(200).json({
      message: "Bill generated successfully",
      data: {
        bill_id: bill.id,
        bill,
        customer: customerDetails,
        summary: {
          subtotal,
          discount: totalDiscount,
          serviceCharge: serviceChargeAmount,
          taxes: { cgst: cgstAmount, sgst: sgstAmount, vat: vatAmount },
          roundOff: roundOffValue,
          finalAmount,
        },
      },
    });

  } catch (error) {
    console.error("❌ Error generating bill:", error);
    try {
      await transaction.rollback();
    } catch (rbErr) {
      console.error("Rollback error:", rbErr);
    }
    return res.status(500).json({
      message: "Error generating bill",
      error: error.message
    });
  }
};



// =============================================================
// ✅ UPDATE BILL CONTROLLER
// =============================================================
// const updateBillById = async (req, res) => {
//   try {
//     const { billId } = req.params;
//     const {
//       discount = {},
//       serviceCharge,
//       vat,
//       cgst,
//       sgst,
//       roundOff,
//       payment_method,
//       isComplimentary,
//       complimentary_remark,
//       complimentary_password,
//       complimentary_profile_id
//     } = req.body;

//     const bill = await Bill.findByPk(billId);
//     if (!bill) return res.status(404).json({ message: "Bill not found" });

//     const tableNumber = bill.table_number;
//     const table = await Table.findByPk(tableNumber);
//     if (!table) return res.status(404).json({ message: `Table ${tableNumber} not found` });

//     // ------------------ Get Completed Orders ------------------
//     const completedFoodOrders = await Order.findAll({
//       where: { table_number: tableNumber, status: "completed" },
//       include: [{ model: Menu, as: "menu", include: ["category"] }],
//     });

//     const completedDrinkOrders = await DrinksOrder.findAll({
//       where: { table_number: tableNumber, status: "completed" },
//       include: [{ model: DrinksMenu, as: "drink" }],
//     });

//     // ------------------ Combine Orders ------------------
//     const combinedOrderDetails = [
//       ...completedFoodOrders.map((o) => ({
//         type: "food",
//         item: o.menu?.name || o.item_desc,
//         category: o.menu?.category?.name || "N/A",
//         quantity: o.quantity,
//         pricePerUnit: o.menu?.price || 0,
//         totalAmount: o.amount,
//       })),
//       ...completedDrinkOrders.map((d) => ({
//         type: "drink",
//         item: d.drink?.name || d.item_desc,
//         category: "Drink",
//         quantity: d.quantity,
//         pricePerUnit: d.drink?.price || 0,
//         totalAmount: d.amount,
//       })),
//     ];

//     bill.order_details = combinedOrderDetails;

//     // ------------------ Amounts ------------------
//     const foodAmount = combinedOrderDetails
//       .filter(i => i.type === "food")
//       .reduce((sum, i) => sum + (parseFloat(i.totalAmount) || 0), 0);

//     const drinkAmount = combinedOrderDetails
//       .filter(i => i.type === "drink")
//       .reduce((sum, i) => sum + (parseFloat(i.totalAmount) || 0), 0);

//     const totalAmount = foodAmount + drinkAmount;

//     // ------------------ Discounts ------------------
//     const foodDiscountPercent = discount?.food?.type === "percent" ? parseFloat(discount.food.value) || 0 : 0;
//     const drinkDiscountPercent = discount?.drinks?.type === "percent" ? parseFloat(discount.drinks.value) || 0 : 0;
//     const foodDiscountFlat = discount?.food?.type === "flat" ? parseFloat(discount.food.value) || 0 : 0;
//     const drinkDiscountFlat = discount?.drinks?.type === "flat" ? parseFloat(discount.drinks.value) || 0 : 0;

//     const foodDiscountAmt = foodDiscountPercent > 0 ? (foodAmount * foodDiscountPercent) / 100 : foodDiscountFlat;
//     const drinkDiscountAmt = drinkDiscountPercent > 0 ? (drinkAmount * drinkDiscountPercent) / 100 : drinkDiscountFlat;
//     const totalDiscount = foodDiscountAmt + drinkDiscountAmt;

//     // ------------------ Taxes ------------------
//     let computedCgstAmt = parseFloat(cgst) || 0;
//     let computedSgstAmt = parseFloat(sgst) || 0;
//     computedCgstAmt = Math.max(0, computedCgstAmt);
//     computedSgstAmt = Math.max(0, computedSgstAmt);
//     const vatAmt = Math.max(0, parseFloat(vat) || 0);

//     // ------------------ Round Off ------------------
//     const roundOffValue = roundOff ? Number(roundOff) : 0;

//     // ------------------ Final Amount ------------------
//     const rawFinalAmount =
//       foodAmount - foodDiscountAmt +
//       drinkAmount - drinkDiscountAmt +
//       computedCgstAmt +
//       computedSgstAmt +
//       vatAmt +
//       roundOffValue;

//     const finalAmount = Math.round(rawFinalAmount);

//     // ------------------ Update Bill ------------------
//     bill.total_amount = totalAmount;
//     bill.discount_amount = totalDiscount;
//     bill.food_discount_percentage = foodDiscountPercent;
//     bill.food_discount_flat_amount = foodDiscountFlat;
//     bill.drink_discount_percentage = drinkDiscountPercent;
//     bill.drink_discount_flat_amount = drinkDiscountFlat;
//     bill.tax_amount = computedCgstAmt + computedSgstAmt;
//     bill.vat_amount = vatAmt;
//     bill.final_amount = finalAmount;
//     bill.round_off = roundOffValue.toString();
//     bill.service_charge_amount = parseFloat(serviceCharge) || 0;
//     bill.payment_method = payment_method || bill.payment_method;
//     bill.is_complimentary = !!isComplimentary;
//     bill.complimentary_remark = complimentary_remark || "";
//     bill.complimentary_password = complimentary_password || "";
//     bill.time_of_bill = new Date();
//     bill.complimentary_profile_id = complimentary_profile_id || null;

//     await bill.save();

//     // ------------------ Update Table ------------------
//     await Table.update(
//       {
//         bill_discount_details: discount || {}, // ✅ save full discount JSON here
//         payment_method: payment_method || table.payment_method,
//       },
//       { where: { id: tableNumber } }
//     );

//     return res.status(200).json({
//       message: "Bill updated successfully with new discount, tax, VAT, and round off",
//       bill_id: bill.id,
//       bill,
//       tableInfo: await Table.findByPk(tableNumber),
//     });
//   } catch (error) {
//     console.error("Error updating bill:", error);
//     return res.status(500).json({ message: "Error updating bill", error: error.message });
//   }
// };


// const settleAndCloseBill = async (req, res) => {
//   const transaction = await sequelize.transaction();

//   try {
//     const { billId } = req.params;
//     const { tip_amount, payment_breakdown } = req.body;

//     const bill = await Bill.findByPk(billId, {
//       transaction,
//       lock: transaction.LOCK.UPDATE,
//     });

//     if (!bill) {
//       await transaction.rollback();
//       return res.status(404).json({ message: "Bill not found" });
//     }

//     if (bill.is_locked) {
//       await transaction.rollback();
//       return res.status(400).json({ message: "Bill already settled" });
//     }

//     // Parse payment breakdown
//     const payments = { cash: 0, card: 0, upi: 0, other: 0 };

//     if (Array.isArray(payment_breakdown)) {
//       payment_breakdown.forEach(item => {
//         if (item.method && item.amount) {
//           const method = item.method.toLowerCase();
//           if (payments.hasOwnProperty(method)) {
//             payments[method] += Number(item.amount) || 0;
//           }
//         }
//       });
//     }

//     // Update bill
//     bill.tip_amount = tip_amount || 0;
//     bill.payment_breakdown = payments;
//     bill.is_locked = true;
//     bill.settled_at = new Date();
//     await bill.save({ transaction });

//     const tableId = bill.table_number;
//     const table = await Table.findByPk(tableId, {
//       transaction,
//       lock: transaction.LOCK.UPDATE,
//     });

//     if (!table) {
//       await transaction.rollback();
//       return res.status(404).json({ message: "Table not found" });
//     }

//     // Handle duplicate table deletion
//     if (table.is_split && table.parent_table_id) {
//       await Promise.all([
//         Order.destroy({ where: { table_number: tableId }, transaction }),
//         DrinksOrder.destroy({ where: { table_number: tableId }, transaction }),
//       ]);

//       await table.destroy({ transaction });
//       await transaction.commit();

//       // Clear cache
//       cache.delete('all_tables');

//       // Emit events
//       const io = req.app.get("io");
//       if (io) {
//         io.emit("delete_table", { tableId, deletedTable: table.toJSON() });
//         io.emit("bill_settled", { billId, tableId });
//       }

//       return res.status(200).json({
//         message: "Bill settled and duplicate table deleted",
//         bill,
//       });
//     }

//     // Regular table - free it
//     await table.update({
//       status: "free",
//       seatingTime: null,
//       food_bill_id: null,
//       bill_discount_details: null,
//       lottery_discount_detail: null,
//       customer_id: null,
//       merged_with: null,
//       isComplimentary: false,
//     }, { transaction });

//     // Delete completed orders
//     await Promise.all([
//       Order.destroy({
//         where: { table_number: tableId, status: "completed" },
//         transaction,
//       }),
//       DrinksOrder.destroy({
//         where: { table_number: tableId, status: "completed" },
//         transaction,
//       }),
//     ]);

//     await transaction.commit();

//     // Clear cache
//     cache.delete('all_tables');

//     // Emit event
//     const io = req.app.get("io");
//     if (io) {
//       io.emit("bill_settled", { billId, tableId });
//       io.emit("table_status_changed", {
//         tableId,
//         newStatus: "free",
//         timestamp: new Date().toISOString(),
//       });
//     }

//     return res.status(200).json({
//       message: "Bill settled and table freed",
//       bill,
//     });

//   } catch (error) {
//     console.error("❌ Error settling bill:", error);
//     try {
//       await transaction.rollback();
//     } catch (rbErr) {
//       console.error("Rollback error:", rbErr);
//     }
//     return res.status(500).json({
//       message: "Error settling bill",
//       error: error.message
//     });
//   }
// };



const updateBillById = async (req, res) => {
  try {
    const { billId } = req.params;
    const {
      discount = {},
      serviceCharge,
      vat,
      cgst,
      sgst,
      roundOff,
      payment_method,
      isComplimentary,
      complimentary_remark,
      complimentary_password,
      complimentary_profile_id
    } = req.body;

    const bill = await Bill.findByPk(billId);
    if (!bill) return res.status(404).json({ message: "Bill not found" });

    const tableNumber = bill.table_number;
    const table = await Table.findByPk(tableNumber);
    if (!table) return res.status(404).json({ message: `Table ${tableNumber} not found` });

    // ------------------ Get Completed Orders ------------------
    const completedFoodOrders = await Order.findAll({
      where: { table_number: tableNumber, status: "completed" },
      include: [{ model: Menu, as: "menu", include: ["category"] }],
    });

    const completedDrinkOrders = await DrinksOrder.findAll({
      where: { table_number: tableNumber, status: "completed" },
      // ✅ FIX: include the full drink menu so applyVAT is available
      include: [{ model: DrinksMenu, as: "drink" }],
    });

    // ------------------ Combine Orders ------------------
    const combinedOrderDetails = [
      ...completedFoodOrders.map((o) => {
        const isCustom = o.is_custom === true || o.is_custom === 1;
        const qty = o.quantity || 1;
        const totalAmount = parseFloat(o.amount) || 0;

        // For custom food items there is no menu record, so derive price from total
        const pricePerUnit = isCustom
          ? totalAmount / qty
          : (parseFloat(o.menu?.price) || 0);

        return {
          type: "food",
          item: isCustom
            ? (o.note || o.item_desc || "Custom Item")
            : (o.menu?.name || o.item_desc),
          category: o.menu?.category?.name || "N/A",
          quantity: qty,
          pricePerUnit,
          totalAmount,
          is_custom: isCustom,
        };
      }),

      ...completedDrinkOrders.map((d) => {
        const isCustom = d.is_custom === true || d.is_custom === 1;
        const qty = d.quantity || 1;
        const totalAmount = parseFloat(d.amount) || 0;

        // applyVAT rules:
        //   • Custom drink (no linked drink record) → always true (treated as alcoholic)
        //   • Regular drink                         → read from DrinksMenu.applyVAT only
        //                                             (never from DrinksOrder itself)
        const applyVAT = isCustom
          ? true
          : d.drink?.applyVAT === true || d.drink?.applyVAT === "true";

        // For custom drinks there is no menu record, so derive price from total
        const pricePerUnit = isCustom
          ? totalAmount / qty
          : (parseFloat(d.drink?.price) || 0);

        return {
          type: "drink",
          item: isCustom
            ? (d.note || d.item_desc || "Custom Drink")
            : (d.drink?.name || d.item_desc),
          category: "Drink",
          quantity: qty,
          pricePerUnit,
          totalAmount,
          applyVAT,
          is_custom: isCustom,
        };
      }),
    ];

    bill.order_details = combinedOrderDetails;

    // ------------------ Amounts ------------------
    const foodAmount = combinedOrderDetails
      .filter(i => i.type === "food")
      .reduce((sum, i) => sum + (parseFloat(i.totalAmount) || 0), 0);

    const drinkAmount = combinedOrderDetails
      .filter(i => i.type === "drink")
      .reduce((sum, i) => sum + (parseFloat(i.totalAmount) || 0), 0);

    const totalAmount = foodAmount + drinkAmount;

    // ------------------ Discounts ------------------
    const foodDiscountPercent = discount?.food?.type === "percent" ? parseFloat(discount.food.value) || 0 : 0;
    const drinkDiscountPercent = discount?.drinks?.type === "percent" ? parseFloat(discount.drinks.value) || 0 : 0;
    const foodDiscountFlat = discount?.food?.type === "flat" ? parseFloat(discount.food.value) || 0 : 0;
    const drinkDiscountFlat = discount?.drinks?.type === "flat" ? parseFloat(discount.drinks.value) || 0 : 0;

    const foodDiscountAmt = foodDiscountPercent > 0 ? (foodAmount * foodDiscountPercent) / 100 : foodDiscountFlat;
    const drinkDiscountAmt = drinkDiscountPercent > 0 ? (drinkAmount * drinkDiscountPercent) / 100 : drinkDiscountFlat;
    const totalDiscount = foodDiscountAmt + drinkDiscountAmt;

    // ------------------ Taxes ------------------
    let computedCgstAmt = parseFloat(cgst) || 0;
    let computedSgstAmt = parseFloat(sgst) || 0;
    computedCgstAmt = Math.max(0, computedCgstAmt);
    computedSgstAmt = Math.max(0, computedSgstAmt);
    const vatAmt = Math.max(0, parseFloat(vat) || 0);

    // ------------------ Round Off ------------------
    const roundOffValue = roundOff ? Number(roundOff) : 0;

    // ------------------ Final Amount ------------------
    const rawFinalAmount =
      foodAmount - foodDiscountAmt +
      drinkAmount - drinkDiscountAmt +
      computedCgstAmt +
      computedSgstAmt +
      vatAmt +
      roundOffValue;

    const finalAmount = Math.round(rawFinalAmount);

    // ------------------ Update Bill ------------------
    bill.total_amount = totalAmount;
    bill.discount_amount = totalDiscount;
    bill.food_discount_percentage = foodDiscountPercent;
    bill.food_discount_flat_amount = foodDiscountFlat;
    bill.drink_discount_percentage = drinkDiscountPercent;
    bill.drink_discount_flat_amount = drinkDiscountFlat;
    bill.tax_amount = computedCgstAmt + computedSgstAmt;
    bill.vat_amount = vatAmt;
    bill.final_amount = finalAmount;
    bill.round_off = roundOffValue.toString();
    bill.service_charge_amount = parseFloat(serviceCharge) || 0;
    bill.payment_method = payment_method || bill.payment_method;
    bill.isComplimentary = !!isComplimentary;
    bill.complimentary_remark = complimentary_remark || "";
    bill.complimentary_password = complimentary_password || "";
    bill.time_of_bill = new Date();
    bill.complimentary_profile_id = complimentary_profile_id || null;

    await bill.save();

    // ------------------ Update Table ------------------
    await Table.update(
      {
        bill_discount_details: discount || {},
        payment_method: payment_method || table.payment_method,
        isComplimentary: !!isComplimentary,
      },
      { where: { id: tableNumber } }
    );

    return res.status(200).json({
      message: "Bill updated successfully with new discount, tax, VAT, and round off",
      bill_id: bill.id,
      bill,
      tableInfo: await Table.findByPk(tableNumber),
    });
  } catch (error) {
    console.error("Error updating bill:", error);
    return res.status(500).json({ message: "Error updating bill", error: error.message });
  }
};


const settleAndCloseBill = async (req, res) => {
  const transaction = await sequelize.transaction();

  try {
    const { billId } = req.params;
    const { tip_amount, payment_breakdown } = req.body;

    const bill = await Bill.findByPk(billId, {
      transaction,
      lock: transaction.LOCK.UPDATE,
    });

    if (!bill) {
      await transaction.rollback();
      return res.status(404).json({ message: "Bill not found" });
    }

    if (bill.is_locked) {
      await transaction.rollback();
      return res.status(400).json({ message: "Bill already settled" });
    }

    const payments = { cash: 0, card: 0, upi: 0, other: 0 };

    if (Array.isArray(payment_breakdown)) {
      payment_breakdown.forEach(item => {
        if (item.method && item.amount != null) {
          const method = item.method.toLowerCase();
          if (Object.prototype.hasOwnProperty.call(payments, method)) {
            payments[method] += Number(item.amount) || 0;
          }
        }
      });
    } else if (payment_breakdown && typeof payment_breakdown === "object") {
      Object.entries(payment_breakdown).forEach(([method, amount]) => {
        const key = method.toLowerCase();
        payments[key] = Number(amount) || 0;
      });
    }

    // ✅ Update bill ONLY
    bill.tip_amount = tip_amount || 0;
    bill.payment_breakdown = payments;
    bill.is_locked = true;
    bill.settled_at = new Date();
    await bill.save({ transaction });

    const tableId = bill.table_number;
    const table = await Table.findByPk(tableId, {
      transaction,
      lock: transaction.LOCK.UPDATE,
    });

    if (!table) {
      await transaction.rollback();
      return res.status(404).json({ message: "Table not found" });
    }

    // ✅ Handle split table deletion
    if (table.is_split && table.parent_table_id) {
      await Promise.all([
        Order.destroy({ where: { table_number: tableId }, transaction }),
        DrinksOrder.destroy({ where: { table_number: tableId }, transaction }),
      ]);

      await table.destroy({ transaction });
      await transaction.commit();

      cache.delete('all_tables');

      const io = req.app.get("io");
      if (io) {
        io.emit("delete_table", { tableId, deletedTable: table.toJSON() });
        io.emit("bill_settled", { billId, tableId });
      }

      return res.status(200).json({
        message: "Bill settled and duplicate table deleted",
        bill,
      });
    }

    // ✅ STEP 1: Find all merged tables (tables that point to this table as primary)
    const mergedTableIds = Array.isArray(table.merged_with)
      ? table.merged_with.filter(id => id != null).map(Number)
      : [];

    console.log(`🔍 Primary table ${tableId} has merged tables:`, mergedTableIds);

    // ✅ STEP 2: Fetch and free all merged tables
    const mergedTables = [];
    if (mergedTableIds.length > 0) {
      const foundMergedTables = await Table.findAll({
        where: { id: mergedTableIds },
        transaction,
        lock: transaction.LOCK.UPDATE,
      });

      for (const mergedTable of foundMergedTables) {
        console.log(`🔓 Freeing merged table ${mergedTable.id}`);

        // Delete any remaining orders on the merged table (should be none, but clean up)
        await Promise.all([
          Order.destroy({ where: { table_number: mergedTable.id }, transaction }),
          DrinksOrder.destroy({ where: { table_number: mergedTable.id }, transaction }),
        ]);

        await mergedTable.update({
          status: "free",
          seatingTime: null,
          food_bill_id: null,
          bill_discount_details: null,
          lottery_discount_detail: null,
          customer_id: null,
          merged_with: null,
          merged_at: null,
          isComplimentary: false,
        }, { transaction });

        mergedTables.push(mergedTable.toJSON());
        console.log(`✅ Merged table ${mergedTable.id} freed`);
      }
    }

    // ✅ STEP 3: Also find tables where merged_with contains this tableId
    // (reverse lookup — tables that consider this table as their primary)
    const reverseMergedTables = await Table.findAll({
      where: sequelize.where(
        sequelize.cast(sequelize.col('merged_with'), 'text'),
        { [Op.like]: `%${tableId}%` }
      ),
      transaction,
      lock: transaction.LOCK.UPDATE,
    });

    const reverseFreedIds = [];
    for (const revTable of reverseMergedTables) {
      // Double check it's actually in the merged_with array
      const mw = Array.isArray(revTable.merged_with) ? revTable.merged_with : [];
      if (mw.map(Number).includes(Number(tableId))) {
        console.log(`🔓 Freeing reverse-merged table ${revTable.id}`);

        await Promise.all([
          Order.destroy({ where: { table_number: revTable.id }, transaction }),
          DrinksOrder.destroy({ where: { table_number: revTable.id }, transaction }),
        ]);

        await revTable.update({
          status: "free",
          seatingTime: null,
          food_bill_id: null,
          bill_discount_details: null,
          lottery_discount_detail: null,
          customer_id: null,
          merged_with: null,
          merged_at: null,
          isComplimentary: false,
        }, { transaction });

        reverseFreedIds.push(revTable.id);
        mergedTables.push(revTable.toJSON());
        console.log(`✅ Reverse-merged table ${revTable.id} freed`);
      }
    }

    // ✅ STEP 4: Free the primary table and delete its completed orders
    await table.update({
      status: "free",
      seatingTime: null,
      food_bill_id: null,
      bill_discount_details: null,
      lottery_discount_detail: null,
      customer_id: null,
      merged_with: null,
      merged_at: null,
      isComplimentary: false,
    }, { transaction });

    await Promise.all([
      Order.destroy({
        where: { table_number: tableId, status: "completed" },
        transaction,
      }),
      DrinksOrder.destroy({
        where: { table_number: tableId, status: "completed" },
        transaction,
      }),
    ]);

    await transaction.commit();

    cache.delete('all_tables');

    // ✅ STEP 5: Emit socket events for ALL freed tables
    const io = req.app.get("io");
    if (io) {
      // Emit bill settled
      io.emit("bill_settled", {
        billId,
        tableId,
        mergedTableIds: [...mergedTableIds, ...reverseFreedIds],
      });

      // ✅ Free primary table via socket
      io.emit("table_status_changed", {
        tableId,
        newStatus: "free",
        seatingTime: null,
        merged_with: null,
        timestamp: new Date().toISOString(),
      });

      // ✅ Free each merged table via socket
      for (const mt of mergedTables) {
        console.log(`📡 Emitting table_status_changed for merged table ${mt.id}`);
        io.emit("table_status_changed", {
          tableId: mt.id,
          newStatus: "free",
          seatingTime: null,
          merged_with: null,
          timestamp: new Date().toISOString(),
        });
      }

      console.log(`✅ Emitted status_changed for ${mergedTables.length + 1} tables`);
    }

    return res.status(200).json({
      message: "Bill settled and table(s) freed",
      bill,
      freedTables: [tableId, ...mergedTableIds, ...reverseFreedIds],
    });

  } catch (error) {
    console.error("❌ Error settling bill:", error);
    try {
      await transaction.rollback();
    } catch (rbErr) {
      console.error("Rollback error:", rbErr);
    }
    return res.status(500).json({
      message: "Error settling bill",
      error: error.message
    });
  }
};


const splitTable = async (req, res) => {
  const transaction = await sequelize.transaction();

  try {
    const { id } = req.params;
    const { seatingCapacity } = req.body;

    // 1️⃣ Fetch parent table
    const parentTable = await Table.findByPk(id, { transaction });
    if (!parentTable) {
      await transaction.rollback();
      return res.status(404).json({ message: "Parent table not found" });
    }

    // 2️⃣ Get existing splits
    const existingSplits = await Table.findAll({
      where: { parent_table_id: parentTable.id },
      attributes: ["split_name"],
      order: [["createdAt", "ASC"]],
      transaction,
    });

    // 3️⃣ Generate split letter (A, B, ... Z, AA, AB)
    const generateSplitName = (index) => {
      let name = "";
      index++;
      while (index > 0) {
        index--;
        name = String.fromCharCode(65 + (index % 26)) + name;
        index = Math.floor(index / 26);
      }
      return name;
    };

    const splitName = generateSplitName(existingSplits.length);

    // 4️⃣ Create split table
    const newTable = await Table.create(
      {
        sectionId: parentTable.sectionId,
        status: "free",
        seatingCapacity: seatingCapacity || parentTable.seatingCapacity || 4,
        seatingTime: new Date(),
        merged_with: null,
        food_bill_id: null,
        bill_discount_details: null,
        lottery_discount_detail: null,
        customer_id: null,
        is_split: true,
        parent_table_id: parentTable.id,
        split_name: splitName,
        display_number: parentTable.display_number, // ✅ INTEGER ONLY
        isComplimentary: false,
        merged_at: null,
      },
      { transaction }
    );

    await transaction.commit();

    // 5️⃣ Emit socket event
    try {
      const io = req.app.get("io");
      if (io) {
        io.emit("split_table", {
          parentTable: {
            id: parentTable.id,
            display_number: parentTable.display_number,
            sectionId: parentTable.sectionId,
            status: parentTable.status,
          },
          newTable: {
            ...newTable.toJSON(),
            ui_label: `${parentTable.display_number}${splitName}`, // 👈 frontend helper
          },
          timestamp: new Date().toISOString(),
        });
      }
    } catch (err) {
      console.error("Socket emit error (split_table):", err);
    }

    return res.status(201).json({
      message: "Table split successfully",
      table: {
        ...newTable.toJSON(),
        ui_label: `${parentTable.display_number}${splitName}`, // 👈 frontend display
      },
    });

  } catch (error) {
    console.error("Error splitting table:", error);
    await transaction.rollback();
    return res.status(500).json({
      message: "Error splitting table",
      error: error.message,
    });
  }
};




const closeSplitTable = async (req, res) => {
  const transaction = await sequelize.transaction();

  try {
    const { id } = req.params;

    // 1️⃣ Fetch split table
    const splitTable = await Table.findByPk(id, { transaction });

    if (!splitTable) {
      await transaction.rollback();
      return res.status(404).json({ message: "Split table not found" });
    }

    // 2️⃣ Validate it is actually a split
    if (!splitTable.is_split || !splitTable.parent_table_id) {
      await transaction.rollback();
      return res.status(400).json({
        message: "This table is not a split table",
      });
    }

    // 3️⃣ Prevent deletion if active order exists
    const activeOrder = await Order.findOne({
      where: {
        table_number: splitTable.id,
        status: ["pending", "accepted", "completed"],
      },
      transaction,
    });


    if (activeOrder) {
      await transaction.rollback();
      return res.status(400).json({
        message: "Cannot close split table with active orders",
      });
    }

    // 4️⃣ Fetch parent table (for socket/UI reference)
    const parentTable = await Table.findByPk(
      splitTable.parent_table_id,
      { transaction }
    );

    // 5️⃣ Delete split table
    await splitTable.destroy({ transaction });

    await transaction.commit();

    // 6️⃣ Emit socket event
    try {
      const io = req.app.get("io");
      if (io) {
        // Update the socket emission in closeSplitTable to match frontend expectations
        io.emit("delete_table", {
          tableId: id,
          sectionId: splitTable.sectionId,
          parentTableId: splitTable.parent_table_id,
          deletedTable: {
            id: id,
            parent_table_id: splitTable.parent_table_id,
            sectionId: splitTable.sectionId,
          },
          timestamp: new Date().toISOString(),
        });
      }
    } catch (err) {
      console.error("Socket emit error (close_split_table):", err);
    }

    return res.status(200).json({
      message: "Split table closed successfully",
      splitTableId: id,
    });

  } catch (error) {
    console.error("Error closing split table:", error);
    await transaction.rollback();
    return res.status(500).json({
      message: "Error closing split table",
      error: error.message,
    });
  }
};




function emitTableStatusChanged(io, table, oldStatus) {
  if (!io) return;

  io.emit("table_status_changed", {
    tableId: table.id,
    displayNumber: table.display_number,
    sectionId: table.sectionId,
    oldStatus,
    newStatus: table.status,
    seatingTime: table.seatingTime,
    merged_with: table.merged_with,
  });
}




// ===============================
// 🧾 Get full table details for bill generation
// Returns table metadata + orders with precomputed amount_per_item (post-tax)
// so the frontend never needs to re-apply any tax.
// ===============================
const getTableBillDetails = async (req, res) => {
  try {
    const { tableId } = req.params;
    const id = Number(tableId);

    if (!Number.isInteger(id)) {
      return res.status(400).json({ message: 'Invalid tableId' });
    }

    // 1️⃣ Fetch table metadata
    const table = await Table.findByPk(id, {
      attributes: [
        'id', 'status', 'food_bill_id', 'bill_discount_details',
        'lottery_discount_detail', 'isComplimentary', 'customer_id',
        'seatingTime', 'display_number', 'sectionId'
      ],
    });

    if (!table) {
      return res.status(404).json({ message: 'Table not found' });
    }

    // 2️⃣ Fetch all food orders for this table (all statuses)
    const allFoodOrders = await Order.findAll({
      where: { table_number: id },
      include: [
        { model: Menu, as: 'menu', attributes: ['id', 'name', 'price'] },
        { model: User, as: 'user', attributes: ['name'] },
      ],
      attributes: ['id', 'table_number', 'quantity', 'amount', 'status', 'is_custom', 'item_desc', 'note'],
    });

    // 3️⃣ Fetch all drink orders for this table (all statuses)
    const allDrinkOrders = await DrinksOrder.findAll({
      where: { table_number: id },
      include: [
        { model: DrinksMenu, as: 'drink', attributes: ['id', 'name', 'price', 'applyVAT'] },
        { model: User, as: 'user', attributes: ['name'] },
      ],
      attributes: ['id', 'table_number', 'quantity', 'amount', 'status', 'is_custom', 'item_desc', 'note', 'applyVAT'],
    });

    // 4️⃣ Enrich each order with `amount_per_item` (post-tax per unit)
    //    o.amount in DB is the BASE price total for the row (pre-tax, for all qty)
    //    amount_per_item = (o.amount / qty) * taxRate
    const enrichFoodOrder = (o) => {
      const json = o.toJSON ? o.toJSON() : { ...o };
      const qty = Number(json.quantity ?? 1);
      const baseTotal = Number(json.amount ?? 0);
      const basePerItem = qty > 0 ? baseTotal / qty : baseTotal;
      // Food always gets 5% GST
      const taxedPerItem = parseFloat((basePerItem * 1.05).toFixed(2));
      return { ...json, amount_per_item: taxedPerItem };
    };

    const enrichDrinkOrder = (o) => {
      const json = o.toJSON ? o.toJSON() : { ...o };
      const qty = Number(json.quantity ?? 1);
      const baseTotal = Number(json.amount ?? 0);
      const basePerItem = qty > 0 ? baseTotal / qty : baseTotal;
      // Alcoholic drinks: 10% VAT; non-alcoholic (incl. custom): 5% GST
      const isAlcoholic = json.drink?.applyVAT === true;
      const taxRate = isAlcoholic ? 1.10 : 1.05;
      const taxedPerItem = parseFloat((basePerItem * taxRate).toFixed(2));
      return { ...json, amount_per_item: taxedPerItem };
    };

    // 5️⃣ Bucket by status
    const foodByStatus = { pending: [], ongoing: [], completed: [] };
    allFoodOrders.forEach(o => {
      const enriched = enrichFoodOrder(o);
      if (o.status === 'pending') foodByStatus.pending.push(enriched);
      else if (o.status === 'accepted') foodByStatus.ongoing.push(enriched);
      else if (o.status === 'completed') foodByStatus.completed.push(enriched);
    });

    const drinkByStatus = { pending: [], ongoing: [], completed: [] };
    allDrinkOrders.forEach(o => {
      const enriched = enrichDrinkOrder(o);
      if (o.status === 'pending') drinkByStatus.pending.push(enriched);
      else if (o.status === 'accepted') drinkByStatus.ongoing.push(enriched);
      else if (o.status === 'completed') drinkByStatus.completed.push(enriched);
    });

    const tableJson = table.toJSON ? table.toJSON() : { ...table };

    return res.status(200).json({
      ...tableJson,
      orders: {
        pendingOrders: foodByStatus.pending,
        ongoingOrders: foodByStatus.ongoing,
        completeOrders: foodByStatus.completed,
      },
      drinksOrders: {
        pendingDrinksOrders: drinkByStatus.pending,
        ongoingDrinksOrders: drinkByStatus.ongoing,
        completeDrinksOrders: drinkByStatus.completed,
      },
    });
  } catch (error) {
    console.error('❌ Error in getTableBillDetails:', error);
    return res.status(500).json({
      message: 'Error fetching table bill details',
      error: error.message,
    });
  }
};


// ===============================
// 🧾 ENHANCED: Get full table details with aggregated orders
// Similar to getSections, this fetches a specific table with:
// - All food orders (pending, ongoing, completed) with aggregated details
// - All drink orders (pending, ongoing, completed) with aggregated details
// - Metadata (bill ID, discount details, complimentary status)
// - Customer information
// ===============================

const getTableWithAllOrderDetails = async (req, res) => {
  try {
    const { tableId } = req.params;
    const id = Number(tableId);
 
    if (!Number.isInteger(id) || id <= 0) {
      return res.status(400).json({ message: 'Invalid tableId' });
    }
 
    // 1️⃣ Fetch table metadata
    const table = await Table.findByPk(id, {
      attributes: [
        'id', 'status', 'food_bill_id', 'bill_discount_details',
        'lottery_discount_detail', 'isComplimentary', 'customer_id',
        'seatingTime', 'display_number', 'sectionId', 'merged_with',
        'is_split', 'parent_table_id', 'split_name'
      ],
    });
 
    if (!table) {
      return res.status(404).json({
        message: 'Table not found',
        tableId: id
      });
    }
 
    // 2️⃣ Fetch ALL food orders (all statuses) — same includes as getSections
    const allFoodOrders = await Order.findAll({
      where: { table_number: id },
      include: [
        { model: Menu, as: 'menu', attributes: ['id', 'name', 'price'] },
        { model: User, as: 'user', attributes: ['id', 'name'] },
      ],
      attributes: [
        'id', 'table_number', 'quantity', 'amount', 'status', 'is_custom',
        'item_desc', 'kotNumber', 'merged_from_table', 'createdAt', 'updatedAt'
      ],
      order: [['createdAt', 'ASC']],
    });
 
    // 3️⃣ Fetch ALL drink orders (all statuses) — same includes as getSections
    const allDrinkOrders = await DrinksOrder.findAll({
      where: { table_number: id },
      include: [
        { model: DrinksMenu, as: 'drink', attributes: ['id', 'name', 'price', 'applyVAT'] },
        { model: User, as: 'user', attributes: ['id', 'name'] },
      ],
      attributes: [
        'id', 'table_number', 'quantity', 'amount', 'status', 'is_custom',
        'item_desc', 'applyVAT', 'kotNumber', 'merged_from_table', 'createdAt', 'updatedAt'
      ],
      order: [['createdAt', 'ASC']],
    });
 
    // 4️⃣ Bucket by status — matching getSections splitOrdersByStatus
    const foodByStatus = {
      pendingOrders: [],
      ongoingOrders: [],
      completeOrders: [],
    };
 
    allFoodOrders.forEach(o => {
      const json = o.toJSON ? o.toJSON() : { ...o };
      if (o.status === 'pending') {
        foodByStatus.pendingOrders.push(json);
      } else if (o.status === 'accepted' || o.status === 'ongoing' || o.status === 'in_progress') {
        foodByStatus.ongoingOrders.push(json);
      } else if (o.status === 'completed') {
        foodByStatus.completeOrders.push(json);
      }
    });
 
    const drinkByStatus = {
      pendingDrinksOrders: [],
      ongoingDrinksOrders: [],
      completeDrinksOrders: [],
    };
 
    allDrinkOrders.forEach(o => {
      const json = o.toJSON ? o.toJSON() : { ...o };
      if (o.status === 'pending') {
        drinkByStatus.pendingDrinksOrders.push(json);
      } else if (o.status === 'accepted' || o.status === 'ongoing' || o.status === 'in_progress') {
        drinkByStatus.ongoingDrinksOrders.push(json);
      } else if (o.status === 'completed') {
        drinkByStatus.completeDrinksOrders.push(json);
      }
    });
 
    // 5️⃣ Calculate amounts — matching getSections sumAmount logic exactly
    // o.amount is the BASE price stored in DB (pre-tax).
    // Tax is applied here for orderAmounts summary only.
    const sumAmount = (orders, kind = 'food') => {
      if (!orders || orders.length === 0) return 0;
      const total = orders.reduce((sum, o) => {
        const baseAmount = Number(o.amount ?? 0);
        if (kind === 'food') {
          return sum + baseAmount * 1.05;
        }
        if (kind === 'drink') {
          const applyVAT = o.is_custom === true || o.drink?.applyVAT === true;
          return sum + (applyVAT ? baseAmount * 1.10 : baseAmount * 1.05);
        }
        return sum + baseAmount;
      }, 0);
      return Number(total.toFixed(2));
    };
 
    const pFood  = sumAmount(foodByStatus.pendingOrders,   'food');
    const oFood  = sumAmount(foodByStatus.ongoingOrders,   'food');
    const cFood  = sumAmount(foodByStatus.completeOrders,  'food');
    const pDrink = sumAmount(drinkByStatus.pendingDrinksOrders,   'drink');
    const oDrink = sumAmount(drinkByStatus.ongoingDrinksOrders,   'drink');
    const cDrink = sumAmount(drinkByStatus.completeDrinksOrders,  'drink');
 
    const totalAmount = Math.round(pFood + oFood + cFood + pDrink + oDrink + cDrink);
 
    // 6️⃣ Fetch section details
    let sectionDetails = null;
    if (table.sectionId) {
      try {
        sectionDetails = await Section.findByPk(table.sectionId, {
          attributes: ['id', 'name'],
        });
      } catch (err) {
        console.error('Error fetching section:', err);
      }
    }
 
    // 7️⃣ Fetch customer details if available
    let customerDetails = null;
    if (table.customer_id) {
      try {
        customerDetails = await CustomerDetails.findByPk(table.customer_id, {
          attributes: ['id', 'customer_name', 'customer_phoneNumber'],
        });
      } catch (err) {
        console.error('Error fetching customer details:', err);
      }
    }
 
    // 8️⃣ Build merged table details
    let mergedTablesDetails = [];
    if (Array.isArray(table.merged_with) && table.merged_with.length > 0) {
      try {
        const mergedTables = await Table.findAll({
          where: { id: table.merged_with },
          attributes: ['id', 'display_number', 'sectionId'],
          include: [{ model: Section, as: 'section', attributes: ['id', 'name'] }],
        });
        mergedTablesDetails = mergedTables.map(t => ({
          id: t.id,
          display_number: t.display_number,
          section_name: t.section?.name || null,
        }));
      } catch (err) {
        console.error('Error fetching merged table details:', err);
      }
    }
 
    const tableJson = table.toJSON ? table.toJSON() : { ...table };
 
    return res.status(200).json({
      // Table metadata
      ...tableJson,
 
      // Section info
      section: sectionDetails ? { id: sectionDetails.id, name: sectionDetails.name } : null,
 
      // Customer info
      customer: customerDetails ? {
        id: customerDetails.id,
        name: customerDetails.customer_name,
        phone: customerDetails.customer_phoneNumber,
      } : null,
 
      // Merged tables
      merged_tables_details: mergedTablesDetails,
 
      // Orders — raw (amount = base pre-tax), matching getSections shape exactly
      orders: {
        pendingOrders:  foodByStatus.pendingOrders,
        ongoingOrders:  foodByStatus.ongoingOrders,
        completeOrders: foodByStatus.completeOrders,
      },
 
      drinksOrders: {
        pendingDrinksOrders:  drinkByStatus.pendingDrinksOrders,
        ongoingDrinksOrders:  drinkByStatus.ongoingDrinksOrders,
        completeDrinksOrders: drinkByStatus.completeDrinksOrders,
      },
 
      // Order amounts (tax-inclusive totals for display)
      orderAmounts: {
        pendingAmount:        Math.round(pFood),
        ongoingAmount:        Math.round(oFood),
        completeAmount:       Math.round(cFood),
        pendingDrinksAmount:  Math.round(pDrink),
        ongoingDrinksAmount:  Math.round(oDrink),
        completeDrinksAmount: Math.round(cDrink),
        totalAmount,
      },
 
      // Summary
      summary: {
        totalFoodItems:        allFoodOrders.length,
        totalDrinkItems:       allDrinkOrders.length,
        completedFoodCount:    foodByStatus.completeOrders.length,
        completedDrinkCount:   drinkByStatus.completeDrinksOrders.length,
        totalCompletedAmount:  Math.round(cFood + cDrink),
      },
 
      // Discount/complimentary fields already in tableJson via spread above
      // (bill_discount_details, lottery_discount_detail, isComplimentary, food_bill_id)
 
      fetchedAt: new Date().toISOString(),
    });
 
  } catch (error) {
    console.error('❌ Error in getTableWithAllOrderDetails:', error);
    return res.status(500).json({
      message: 'Error fetching table with order details',
      error: error.message,
    });
  }
};

// ===============================
// ✅ Export all functions
// ===============================

module.exports = {
  getTables,
  getTableById,
  createTable,
  updateTable,
  deleteTable,
  getTableInfo,
  markTableAsFree,
  markTableAsOccupied,
  markTableAsReserved,
  getBills,
  getBillById,
  updateBillById,
  generateTableBill,
  settleAndCloseBill,
  transferTableOrders,
  mergeTableOrders,
  splitTable,
  demergeTableOrders,
  shiftOrders,
  getOrCreateDuplicateTable,
  closeSplitTable,
  getTableBillDetails,
  getTableWithAllOrderDetails, // ✅ New comprehensive endpoint
};