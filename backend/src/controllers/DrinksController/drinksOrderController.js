const bcrypt = require("bcryptjs");
const {
  User,
  DrinksMenu,
  DrinksOrder,
  CanceledDrinkOrder,
  CanceledFoodOrder,
  DrinksKitchenInventory,
  DrinksMenuIngredient,
  Section,
  Table,
  OrderItem,
  DrinksIngredient,
} = require("../../models");
const moment = require("moment-timezone");
const logger = require("../../configs/logger");
const { sequelize } = require("../../models");
const { Op } = require('sequelize');


// ✅ Get all drink orders

const getDrinksOrders = async (req, res) => {
  try {
    const limit = Math.min(parseInt(req.query.limit || "50", 10), 500);
    const offset = parseInt(req.query.offset || "0", 10);

    const sortBy = ["createdAt", "updatedAt", "status"].includes(req.query.sortBy)
      ? req.query.sortBy
      : "createdAt";

    const sortDir =
      (req.query.sortDir || "DESC").toUpperCase() === "ASC" ? "ASC" : "DESC";

    const q = req.query.q?.trim();
    const status = req.query.status;
    const since = req.query.since;
    const includeCount = req.query.count === "true";

    /* ---------- WHERE ---------- */
    const where = {};
    if (status) where.status = status;
    if (since) where.createdAt = { [Op.gte]: new Date(since) };

    if (q) {
      where[Op.or] = [
        { "$drink.name$": { [Op.iLike]: `%${q}%` } },
        { "$user.name$": { [Op.iLike]: `%${q}%` } },
      ];
    }

    /* ---------- QUERY ---------- */
    const options = {
      where,
      limit,
      offset,
      order: [[sortBy, sortDir]],
      subQuery: false,
      attributes: [
        "id",
        "quantity",
        "status",
        "table_number",
        "restaurant_table_number",
        "section_number",
        "userId",
        "drinksMenuId",
        "item_desc",
        "amount",
        "is_custom",
        "kotNumber",
        "shifted_from_table",
        "createdAt",
        "updatedAt",
      ],
      include: [
        {
          model: DrinksMenu,
          as: "drink",
          attributes: ["id", "name", "price"], // ✅ FIXED
          required: false,
        },
        {
          model: User,
          as: "user",
          attributes: ["id", "name"],
          required: false,
        },
        {
          model: Table,
          as: "table",
          attributes: [
            "id",
            "display_number",
            "is_split",
            "parent_table_id",
            "split_name",
          ],
          required: false,
          include: [
            {
              model: Section,
              as: "section",
              attributes: ["id", "name"],
              required: false,
            },
          ],
        },
      ],
    };

    if (includeCount) {
      options.distinct = true;
      options.col = "DrinksOrder.id";
    }

    const result = includeCount
      ? await DrinksOrder.findAndCountAll(options)
      : await DrinksOrder.findAll(options);

    const rows = includeCount ? result.rows : result;

    /* ---------- FORMAT ---------- */
    const formatted = rows.map((order) => {
      const row = order.toJSON();

      row.createdAt = moment(row.createdAt).tz("Asia/Kolkata").format();
      row.updatedAt = moment(row.updatedAt).tz("Asia/Kolkata").format();

      if (row.table) {
        row.table_display_name =
          row.table.is_split &&
          row.table.parent_table_id &&
          row.table.split_name
            ? `${row.table.parent_table_id}${row.table.split_name}`
            : String(row.table.display_number);
      }

      row.actual_table_number = row.table_number;
      row.restaurent_table_number = row.table_display_name;
      row.restaurant_table_number = row.table_display_name;

      return row;
    });

    if (includeCount) {
      return res.json({
        total: result.count,
        limit,
        offset,
        rows: formatted,
      });
    }

    return res.json(formatted);
  } catch (error) {
    console.error("❌ Error fetching drink orders:", error);
    return res.status(500).json({
      message: "Error fetching drink orders",
      error: error.message,
    });
  }
};




// ✅ Get drink order by ID
const getDrinksOrderById = async (req, res) => {
  try {
    const order = await DrinksOrder.findByPk(req.params.id, {
      include: [
        { model: DrinksMenu, as: "drink", attributes: ["name", "price"] },
      ],
    });
    if (!order) {
      return res.status(404).json({ message: "Drink order not found" });
    }
    res.json(order);
  } catch (error) {
    console.error("Error fetching drink order by ID:", error);
    res
      .status(500)
      .json({ message: "Error fetching drink order", error: error.message });
  }
};


// ✅ Create new drink order with multiple items (kotNumber logic like createOrder; food = false)
const createDrinkOrder = async (req, res) => {
  const transaction = await sequelize.transaction();

  try {
    const { userId, sectionId, tableId, items } = req.body;
    console.log("createDrinkOrder body:", req.body);

    if (!tableId || !Array.isArray(items) || items.length === 0) {
      await transaction.rollback();
      return res.status(400).json({ message: "Table ID and items are required" });
    }

    let table = await Table.findByPk(tableId, { transaction });
    if (!table) {
      await transaction.rollback();
      return res.status(404).json({ message: "Table not found" });
    }

    let actualTableId = table.id;

    // 🔁 Handle settleUp → duplicate split table
    if (table.status === "settleUp") {
      const duplicate = await getOrCreateDuplicateTable(table, transaction);
      table = duplicate;
      actualTableId = duplicate.id;
    } else if (table.status !== "occupied") {
      await table.update(
        { status: "occupied", seatingTime: new Date() },
        { transaction }
      );
    }

    // ✅ ALWAYS build restaurant_table_number safely
    const actualRestaurantTableId =
      table.is_split && table.parent_table_id && table.split_name
        ? `${table.parent_table_id}${table.split_name}` // 132A
        : String(table.display_number);                 // normal table

    const section = sectionId
      ? await Section.findByPk(sectionId, { transaction })
      : null;

    const createdUser = userId
      ? await User.findByPk(userId, { transaction })
      : null;

    // 🧾 KOT logic
    const now = new Date();
    const istNow = new Date(
      now.toLocaleString("en-US", { timeZone: "Asia/Kolkata" })
    );
    let kotReset = new Date(istNow);
    kotReset.setHours(5, 0, 0, 0);
    if (istNow < kotReset) kotReset.setDate(kotReset.getDate() - 1);
    const kotResetUtc = new Date(
      kotReset.toLocaleString("en-US", { timeZone: "UTC" })
    );

    const lastDrinkKot = await OrderItem.findOne({
      where: { food: false, createdAt: { [Op.gte]: kotResetUtc } },
      order: [["kotNumber", "DESC"]],
      transaction,
    });

    const kotNumber = lastDrinkKot ? lastDrinkKot.kotNumber + 1 : 1;

    const createdOrderItems = [];
    let firstOrder = null;

    for (const item of items) {
      const itemId = item.itemId ? parseInt(item.itemId, 10) : null;
      const quantity = Number(item.quantity ?? 1);
      const priceProvided = Number(item.price ?? 0);
      const isCustomItem = !itemId;

      if (quantity <= 0 || priceProvided <= 0) {
        await transaction.rollback();
        return res.status(400).json({ message: "Invalid quantity or price" });
      }

      let drinkMenuItem = null;
      let actualPrice = priceProvided;
      let commissionTotal = 0;
      let categoryId = null;
      let categoryName = null;

      if (!isCustomItem) {
        drinkMenuItem = await DrinksMenu.findByPk(itemId, { transaction });
        if (!drinkMenuItem) {
          await transaction.rollback();
          return res.status(404).json({ message: "Drink item not found" });
        }

        categoryId = drinkMenuItem.categoryId;
        if (categoryId) {
          const category = await Category.findByPk(categoryId, { transaction });
          if (category) categoryName = category.name;
        }

        actualPrice = drinkMenuItem.isOffer
          ? drinkMenuItem.offerPrice
          : priceProvided;

        if (drinkMenuItem.isOffer) {
          const waiterCommission = drinkMenuItem.waiterCommission ?? 0;
          commissionTotal =
            drinkMenuItem.commissionType === "percentage"
              ? (actualPrice * waiterCommission * quantity) / 100
              : waiterCommission * quantity;
        }
      }

      const amount = actualPrice * quantity;

      const applyVAT = drinkMenuItem ? drinkMenuItem.applyVAT : (item.applyVat !== undefined ? item.applyVat : true); // custom items get VAT
      const taxRate = applyVAT ? 1.10 : 1.05;
      const taxedAmount = Math.round(actualPrice * quantity * taxRate);
      const taxedAmountPerItem = Math.round(actualPrice * taxRate * 100) / 100;



      // 🍺 CREATE DRINK ORDER
      const newDrinkOrder = await DrinksOrder.create(
        {
          userId,
          drinksMenuId: drinkMenuItem ? drinkMenuItem.id : null,
          item_desc: item.itemName ?? "",
          quantity,
          status: "pending",
          amount,
          applyVAT,
          table_number: actualTableId,
          restaurant_table_number: actualRestaurantTableId,
          section_number: sectionId,
          is_custom: isCustomItem,
          kotNumber,
        },
        { transaction }
      );

      if (!firstOrder) firstOrder = newDrinkOrder;

      // 📦 ORDER ITEM
      const orderItem = await OrderItem.create(
        {
          food: false,
          userId,
          menuId: drinkMenuItem ? drinkMenuItem.id : null,
          orderId: newDrinkOrder.id,
          quantity,
          price: actualPrice,
          amount_per_item: taxedAmountPerItem,
          commissionTotal,
          categoryId,
          name: item.itemName,
          desc: item.description ?? null,
          is_custom: isCustomItem,
          kotNumber,
        },
        { transaction }
      );

      createdOrderItems.push({
        orderItem: {
          ...orderItem.toJSON(),
          taxedAmount,                    // ✅ total with tax
          taxedActualAmount: taxedAmount, // ✅ for Flutter compatibility
          amount_per_item: taxedAmountPerItem, // ✅ per-item with tax
        },
        drinkMenu: drinkMenuItem
          ? {
              id: drinkMenuItem.id,
              name: drinkMenuItem.name,
              kotCategory: drinkMenuItem.kotCategory,
              categoryName,
              applyVAT: drinkMenuItem.applyVAT, // ✅ send VAT flag
              price: actualPrice,               // ✅ base price
            }
          : {
              id: null,
              name: item.itemName,
              kotCategory: null,
              categoryName: null,
              applyVAT: true,   // ✅ custom items default to VAT
              price: actualPrice,
            },
      });
    }

    await transaction.commit();

    // 🔌 SOCKET EMIT
    const io = req.app.get("io");
    if (io && firstOrder) {
      io.emit("new_drinks_order", {
        order: {
          id: firstOrder.id,
          user: createdUser
            ? { id: createdUser.id, name: createdUser.name }
            : null,
          section: section ? { id: section.id, name: section.name } : null,
          restaurant_table_number: actualRestaurantTableId,
          actual_table_number: actualTableId,
        },
        kotNumber,
        items: createdOrderItems,
      });
    }

    return res.status(201).json({
      message: "Drink order created successfully",
      kotNumber,
      created: createdOrderItems,
    });
  } catch (error) {
    console.error("Error creating drink order:", error);
    await transaction.rollback();
    return res.status(500).json({
      message: "Error creating drink order",
      error: error.message,
    });
  }
};



const updateDrinkOrder = async (req, res) => {
  try {
    const { id } = req.params;
    const { drinksMenuId, item_desc, quantity, status, amount, table_number } =
      req.body;

    const order = await DrinksOrder.findByPk(id);
    if (!order)
      return res.status(404).json({ message: "Drink order not found" });

    await order.update({
      drinksMenuId: drinksMenuId || order.drinksMenuId,
      item_desc: item_desc || order.item_desc,
      quantity: quantity || order.quantity,
      status: status || order.status,
      amount: amount || order.amount,
      table_number: table_number || order.table_number,
    });

    res.status(200).json(order);
  } catch (error) {
    console.error("Error updating drink order:", error);
    res
      .status(500)
      .json({ message: "Error updating drink order", error: error.message });
  }
};


// ✅ Delete drink order (updated to match deleteOrder behavior)
// controllers/FoodController/drinkController.js

const deleteDrinkOrder = async (req, res) => {
  const t = await sequelize.transaction();
  try {
    const {
      password,
      remarks = '',
      userId,
      quantity,
      table_id,
      drinksMenuId,
      drinkId, // alias
      status // optional
    } = req.body;

    console.log(req.body);

    const targetMenuId = drinksMenuId || drinkId;

    if (!userId || !password) {
      await t.rollback();
      return res.status(400).json({ message: "userId and password are required" });
    }

    const qtyRequested = Number.parseInt(quantity, 10);
    if (!Number.isInteger(qtyRequested) || qtyRequested <= 0) {
      await t.rollback();
      return res.status(400).json({ message: "quantity must be a positive integer" });
    }

    if (!targetMenuId && table_id == null) {
      await t.rollback();
      return res.status(400).json({ message: "One of (drinkId|drinksMenuId) and table_id are required" });
    }

    const user = await User.findOne({
      where: { id: userId },
      transaction: t,
      lock: t.LOCK.UPDATE,
    });
    if (!user) {
      await t.rollback();
      return res.status(404).json({ message: "User not found" });
    }

    const isMatch = await bcrypt.compare(password, user.password);
    if (!isMatch) {
      await t.rollback();
      return res.status(401).json({ message: "Wrong password!" });
    }

    const attemptWhere = (colName) => {
      const w = { table_number: table_id };
      if (targetMenuId) w[colName] = targetMenuId;
      if (status) w.status = status;
      return w;
    };

    // Step 1: find potential matches
    let ordersLight = await DrinksOrder.findAll({
      where: attemptWhere('drinksMenuId'),
      attributes: [
        'id', 'drinksMenuId', 'quantity', 'status', 'table_number',
        'item_desc', 'kotNumber', 'section_number', 'restaurant_table_number',
        'createdAt', 'userId', 'is_custom'
      ],
      order: [['createdAt', 'DESC']],
      transaction: t,
    });

    if (!ordersLight.length) {
      ordersLight = await DrinksOrder.findAll({
        where: attemptWhere('drinkId'),
        attributes: [
          'id', 'drinksMenuId', 'drinkId', 'quantity', 'status', 'table_number',
          'item_desc', 'kotNumber', 'section_number', 'restaurant_table_number',
          'createdAt', 'userId', 'is_custom'
        ],
        order: [['createdAt', 'DESC']],
        transaction: t,
      });
    }

    if (!ordersLight.length) {
      await t.rollback();
      return res.status(404).json({
        message: "No matching drink orders found for given drinksMenuId/drinkId and table",
        details: { tried: ['drinksMenuId', 'drinkId'], targetMenuId, table_id, status }
      });
    }

    const ids = ordersLight.map(o => o.id);
    const menuIds = [...new Set(ordersLight.map(o => o.drinksMenuId).filter(Boolean))];
    const menus = menuIds.length ? await DrinksMenu.findAll({ where: { id: menuIds }, transaction: t }) : [];
    const menuMap = new Map(menus.map(m => [m.id, m.name]));

    const matchingOrders = await DrinksOrder.findAll({
      where: { id: ids },
      order: [['createdAt', 'DESC']],
      transaction: t,
      lock: t.LOCK.UPDATE,
    });

    if (!matchingOrders.length) {
      await t.rollback();
      return res.status(409).json({ message: "No matching drink orders after re-fetch — concurrency conflict. Try again." });
    }

    const lightMap = new Map(ordersLight.map(o => [o.id, o]));
    const io = req.app.get('io');
    let qtyLeft = qtyRequested;
    const deletedRows = [];
    const updatedRows = [];

    for (const order of matchingOrders) {
      if (qtyLeft <= 0) break;

      const light = lightMap.get(order.id);
      const rowQty = (typeof order.quantity === 'number' && order.quantity > 0) ? order.quantity : 1;
      const menuKey = light?.drinksMenuId;
      let itemName = (light?.item_desc?.trim()) || (menuKey && menuMap.get(menuKey)) || 'Unnamed Item';

      const sectionNumberValue = order.section_number || light?.section_number || null;
      const restaurentTableNumberValue = order.restaurant_table_number || light?.restaurant_table_number || null;

      // 🧩 Custom drink deletion rule:
      if (order.is_custom === true && (order.drinksMenuId == null)) {
        const removed = Math.min(qtyLeft, rowQty);
        const newQty = rowQty - removed;

        const actualPrice = order.quantity > 0 ? (order.amount / order.quantity) : 0;
        const newAmount = actualPrice * newQty;

        if (newQty > 0) {
          await order.update({ quantity: newQty, amount: newAmount }, { transaction: t });
        } else {
          await order.destroy({ transaction: t });
        }

        await CanceledDrinkOrder.create({
          drinksMenuId: null,
          count: removed,
          userId: order.userId || userId,
          tableNumber: order.table_number,
          section_number: order.section_number || light?.section_number || null,
          restaurent_table_number: order.restaurant_table_number || light?.restaurant_table_number || null,
          remarks: (remarks && remarks.trim()) ? remarks.trim() : null,
          deletedBy: userId,
          is_custom: true,
          customName: order.item_desc || itemName,
        }, { transaction: t });

        // ✅ FIXED: use correct in-scope variables
        if (io) {
          const deletionPayload = {
            orderId: order.id,           // was: orderId (undefined)
            itemName,
            table_number: order.table_number,
            restaurant_table_number: order.restaurant_table_number || restaurentTableNumberValue,
            section_number: order.section_number || sectionNumberValue,
            removedAmount: actualPrice * removed,   // was: totalAmountToMove (undefined)
            removedQuantity: removed,               // was: qtyToDelete (undefined)
            status: order.status,
            orderType: 'drinks',
          };

          console.log(`[sockets] Emitting order_deleted for custom drinks:`, deletionPayload);
          io.emit('order_deleted', deletionPayload);
        }

        deletedRows.push({
          orderId: order.id,
          itemName,
          removed,
          is_custom: true,
          section_number: order.section_number,
          restaurent_table_number: order.restaurant_table_number,
        });

        qtyLeft -= removed;
        continue;
      }

      // 🧩 Normal drinks logic
      if (rowQty > qtyLeft) {
        const removed = qtyLeft;
        const newQty = rowQty - removed;

        // 🧮 Update amount also
        const actualPrice = order.quantity > 0 ? (order.amount / order.quantity) : 0;
        const newAmount = actualPrice * newQty;

        await order.update({ quantity: newQty, amount: newAmount }, { transaction: t });

        await CanceledDrinkOrder.create({
          drinksMenuId: order.drinksMenuId || menuKey || null,
          count: removed,
          userId: order.userId || userId,
          tableNumber: order.table_number,
          section_number: sectionNumberValue,
          restaurent_table_number: restaurentTableNumberValue,
          remarks: (remarks && remarks.trim()) ? remarks.trim() : null,
          deletedBy: userId,
          is_custom: order.is_custom || false,
          customName: order.is_custom ? order.item_desc || itemName : null,
        }, { transaction: t });

        if (io) {
          console.log(`[sockets] Emitting drinks_order_updated and order_updated for order ${order.id} table ${order.table_number}`);
          io.emit('drinks_order_updated', {
            orderId: order.id,
            drinksMenuId: menuKey,
            oldQuantity: rowQty,
            newQuantity: newQty,
            table_number: order.table_number,
            restaurant_table_number: order.restaurant_table_number,
            itemName,
          });
          // Mirror for generic table UI
          io.emit('order_updated', {
            orderId: order.id,
            menuId: menuKey,
            oldQuantity: rowQty,
            newQuantity: newQty,
            table_number: order.table_number,
            restaurant_table_number: order.restaurant_table_number,
            itemName,
          });
        }

        updatedRows.push({
          orderId: order.id,
          oldQty: rowQty,
          newQty,
          section_number: sectionNumberValue,
          restaurent_table_number: restaurentTableNumberValue,
        });

        qtyLeft = 0;
        break;
      } else {
        const removed = rowQty;
        const orderId = order.id;

        const actualPrice = order.quantity > 0 ? (order.amount / order.quantity) : 0;
        // amount not needed after deletion, but kept for clarity

        await order.destroy({ transaction: t });

        await CanceledDrinkOrder.create({
          drinksMenuId: order.drinksMenuId || menuKey || null,
          count: removed,
          userId: order.userId || userId,
          tableNumber: order.table_number,
          section_number: sectionNumberValue,
          restaurent_table_number: restaurentTableNumberValue,
          remarks: (remarks && remarks.trim()) ? remarks.trim() : null,
          deletedBy: userId,
          is_custom: order.is_custom || false,
          customName: order.is_custom ? order.item_desc || itemName : null,
        }, { transaction: t });

        if (io) {
          console.log(`[sockets] Emitting delete_drinks_orders and order_deleted for order ${orderId} table ${order.table_number}`);
          io.emit('delete_drinks_orders', {
            orderId,
            itemName,
            restaurant_table_number: order.restaurant_table_number,
          });
          // Generic deletion event for tables UI
          io.emit('order_deleted', {
            orderId,
            itemName,
            table_number: order.table_number,
            restaurant_table_number: order.restaurant_table_number,
          });
        }

        deletedRows.push({
          orderId,
          itemName,
          removed,
          section_number: sectionNumberValue,
          restaurent_table_number: restaurentTableNumberValue,
        });

        qtyLeft -= removed;
      }
    }

    await t.commit();

    const qtyRemoved = qtyRequested - qtyLeft;
    return res.json({
      message:
        qtyRemoved === qtyRequested
          ? `Removed ${qtyRemoved} drink item(s).`
          : `Removed ${qtyRemoved} drink item(s). Requested ${qtyRequested}, ${qtyLeft} remaining.`,
      requested: qtyRequested,
      removed: qtyRemoved,
      remainingToRemove: qtyLeft,
      deletedRows,
      updatedRows,
    });

  } catch (err) {
    console.error("Error deleting drink orders:", err);
    try { await t.rollback(); } catch {}
    return res.status(500).json({ message: "Error deleting drink orders", error: err.message });
  }
};



// ✅ Accept multiple orders and deduct ingredients
const acceptDrinkOrder = async (req, res) => {
  const { kotNumber } = req.body;
  console.log("🍸 Accepting drink orders for kotNumber:", kotNumber);

  if (!kotNumber) {
    return res.status(400).json({ message: "kotNumber is required" });
  }

  try {
    // 1) Find all drink orders with this kotNumber, include table relations
    const drinkOrders = await DrinksOrder.findAll({
      where: { kotNumber },
      include: [
        { 
          model: DrinksMenu, 
          as: "drink",
          attributes: ["id", "name", "price"]
        },
        {
          model: Table,
          as: "table",
          include: [{ model: Section, as: "section" }],
        },
      ],
      attributes: ["id", "kotNumber", "status", "amount", "drinksMenuId"],
    });

    if (!drinkOrders || drinkOrders.length === 0) {
      console.log(`No drink orders found for kotNumber ${kotNumber}`);
      return res
        .status(404)
        .json({ message: `No drink orders found for kotNumber ${kotNumber}` });
    }

    const orderIds = drinkOrders.map(o => o.id);
    console.log(`Found ${orderIds.length} drink order(s) for kotNumber ${kotNumber}:`, orderIds);

    // 2) Bulk update DrinksOrder table -> set status = 'accepted'
    const [ordersUpdatedCount] = await DrinksOrder.update(
      { status: 'accepted' },
      { where: { kotNumber } }
    );

    console.log(`Drink orders updated (status -> accepted): ${ordersUpdatedCount}`);

    // 3) Update OrderItems if model exists (drinks have food: false)
    let orderItemsUpdated = 0;
    try {
      if (typeof OrderItem !== 'undefined' && OrderItem) {
        const [count1] = await OrderItem.update(
          { status: 'accepted' },
          { where: { orderId: { [Op.in]: orderIds }, food: false } }
        );
        orderItemsUpdated += count1 || 0;

        // Try alternate column name if first attempt fails
        if (!orderItemsUpdated) {
          const [count2] = await OrderItem.update(
            { status: 'accepted' },
            { where: { OrderId: { [Op.in]: orderIds }, food: false } }
          );
          orderItemsUpdated += count2 || 0;
        }
        console.log(`OrderItems updated (status -> accepted, food:false): ${orderItemsUpdated}`);
      }
    } catch (itemErr) {
      console.error("Error updating OrderItem rows for drinks:", itemErr);
    }

    // 4) Emit socket events (matching food orders pattern)
    const io = req.app.get("io");
    
    try {
      if (io) {
        // Emit individual status updates for each drink order
        for (const order of drinkOrders) {
          if (order.table) {
            io.emit("update_order_status", {
              orderId: order.id.toString(),
              orderType: "drinks",
              newStatus: "ongoing", // accepted orders show as "ongoing"
              sectionId: order.table.section?.id || order.table.sectionId,
              tableId: order.table.actual_table_number || order.table.id,
              amount: parseFloat(order.amount || 0),
              kotNumber: order.kotNumber,
              drinkName: order.drink?.name || null, // Send drink name
              drinksMenuId: order.drinksMenuId?.toString() || null,
            });
          }
        }

        // Emit batch acceptance event for backward compatibility
        io.emit("drinks_order_accepted", { kotNumber, orderIds });
        console.log(`Socket events emitted for drink kotNumber ${kotNumber}`);
      } else {
        console.log("Socket instance not found; skipping emit");
      }
    } catch (emitErr) {
      console.error("Error emitting socket events:", emitErr);
    }

    // 5) Return summary (matching food orders response format)
    return res.status(200).json({
      message: `Drink orders with kotNumber ${kotNumber} processed successfully.`,
      kotNumber,
      totalOrdersFound: drinkOrders.length,
      ordersMarkedAccepted: ordersUpdatedCount,
      orderItemsUpdated,
    });
  } catch (error) {
    console.error("🚨 Error accepting drink orders:", error);
    return res.status(500).json({
      message: "Error accepting drink orders",
      error: error.message,
    });
  }
};



// Complete all drink orders/items by kotNumber and emit socket event
const completedDrinkOrder = async (req, res) => {
  const { kotNumber } = req.body;
  console.log("🍸 Completing drink orders for kotNumber:", kotNumber, "body:", req.body);

  if (!kotNumber) {
    return res.status(400).json({ message: "kotNumber is required in body" });
  }

  try {
    // 1) Find all drink orders with this kotNumber, including table relations
    const drinkOrders = await DrinksOrder.findAll({
      where: { kotNumber },
      include: [
        {
          model: Table,
          as: "table",
          include: [{ model: Section, as: "section" }],
        },
        {
          model: DrinksMenu,
          as: "drink",
          attributes: ["id", "name", "price"],
        },
      ],
      attributes: ["id", "kotNumber", "status", "amount", "drinksMenuId"],
    });

    if (!drinkOrders || drinkOrders.length === 0) {
      console.log(`No drink orders found for kotNumber ${kotNumber}`);
      return res
        .status(404)
        .json({ message: `No drink orders found for kotNumber ${kotNumber}` });
    }

    const orderIds = drinkOrders.map((o) => o.id);
    console.log(`Found ${orderIds.length} drink order(s) for kotNumber ${kotNumber}:`, orderIds);

    // 2) Bulk update the DrinksOrder table -> set status = 'completed'
    const [ordersUpdatedCount] = await DrinksOrder.update(
      { status: "completed" },
      { where: { kotNumber } }
    );

    console.log(`Drink orders updated (status -> completed): ${ordersUpdatedCount}`);

    // 3) Update OrderItems if model exists (drinks have food: false)
    let orderItemsUpdated = 0;
    try {
      if (typeof OrderItem !== "undefined" && OrderItem) {
        const [count1] = await OrderItem.update(
          { status: "completed" },
          { where: { orderId: { [Op.in]: orderIds }, food: false } }
        );
        orderItemsUpdated += count1 || 0;

        // Try alternate column name if first attempt fails
        if (!orderItemsUpdated) {
          const [count2] = await OrderItem.update(
            { status: "completed" },
            { where: { OrderId: { [Op.in]: orderIds }, food: false } }
          );
          orderItemsUpdated += count2 || 0;
        }
        console.log(`OrderItems updated (status -> completed, food:false): ${orderItemsUpdated}`);
      }
    } catch (itemErr) {
      console.error("Error updating OrderItem rows for drinks:", itemErr);
    }

    // 4) Emit socket events (matching food orders pattern)
    try {
      const io = req.app && req.app.get ? req.app.get("io") : null;
      if (io) {
        // Emit individual status updates for each drink order
        for (const order of drinkOrders) {
          if (order.table) {
            io.emit("update_order_status", {
              orderId: order.id.toString(),
              orderType: "drinks",
              newStatus: "completed",
              sectionId: order.table.section?.id || order.table.sectionId,
              tableId: order.table.actual_table_number || order.table.id,
              amount: parseFloat(order.amount || 0),
              kotNumber: order.kotNumber,
              drinkName: order.drink?.name || null,
              drinksMenuId: order.drinksMenuId?.toString() || null,
            });
          }
        }

        // Emit batch completion event for backward compatibility
        io.emit("drinks_order_completed", { kotNumber, orderIds });
        console.log(`Socket events emitted for drink kotNumber ${kotNumber}`);
      } else {
        console.log("Socket instance not found on req.app; skipping emit.");
      }
    } catch (emitErr) {
      console.error("Error emitting socket events for drinks:", emitErr);
    }

    // 5) Return summary (matching food orders response format)
    return res.status(200).json({
      message: `Drink orders with kotNumber ${kotNumber} marked completed.`,
      kotNumber,
      totalOrdersFound: drinkOrders.length,
      ordersUpdated: ordersUpdatedCount,
      orderItemsUpdated,
    });
  } catch (error) {
    console.error("🚨 Error completing drink orders:", error);
    return res
      .status(500)
      .json({ message: "Error completing drink orders", error: error.message });
  }
};


const completeSingleDrinkOrderItem = async (req, res) => {
  const { id } = req.params;

  console.log("🍸 Completing single drink order item:", id);

  if (!id) {
    return res
      .status(400)
      .json({ message: "Drink item ID (id) is required in the route parameter." });
  }

  try {
    // 1) Find the specific drink order with table + section included
    const drinkOrder = await DrinksOrder.findOne({
      where: { id },
      include: [
        {
          model: Table,
          as: "table",
          include: [{ model: Section, as: "section" }],
        },
        {
          model: DrinksMenu,
          as: "drink",
          attributes: ["name"],
        },
      ],
      attributes: ["id", "kotNumber", "status", "amount", "drinksMenuId"],
    });

    if (!drinkOrder) {
      return res
        .status(404)
        .json({ message: `No drink order found with ID ${id}` });
    }

    // 2) Update its status to 'completed'
    await drinkOrder.update({ status: "completed" });
    console.log(`✅ Drink order ID ${id} marked as completed.`);

    // 3) Emit socket event (matching food orders pattern - for SINGLE item, not entire KOT)
    try {
      const io = req.app?.get("io");
      if (io && drinkOrder.table) {
        // ✅ Emit with EXACT structure that TableScreen expects
        io.emit("order_item_completed", {
          orderId: drinkOrder.id.toString(), // ✅ The specific drink order ID
          orderType: "drinks", // ✅ CRITICAL: Must be "drinks" not "drink"
          newStatus: "completed",
          sectionId: drinkOrder.table.section?.id || drinkOrder.table.sectionId,
          tableId: drinkOrder.table.actual_table_number || drinkOrder.table.id,
          amount: parseFloat(drinkOrder.amount || 0),
          kotNumber: drinkOrder.kotNumber?.toString(),
          drinkName: drinkOrder.drink?.name || null,
          itemName: drinkOrder.drink?.name || null, // ✅ Add this for consistency
          menuName: drinkOrder.drink?.name || null, // ✅ Add this too
        });

        console.log(
          `🔊 Socket event 'order_item_completed' emitted for drink ID ${drinkOrder.id}`
        );
      }
    } catch (emitErr) {
      console.error("Error emitting socket event:", emitErr);
    }
    

    // 4) Respond success (matching food orders response format)
    return res.status(200).json({
      message: `Drink order item with ID ${id} marked as completed.`,
      item: {
        id: drinkOrder.id,
        kotNumber: drinkOrder.kotNumber,
        status: drinkOrder.status,
        amount: drinkOrder.amount,
      },
    });
  } catch (error) {
    console.error("🚨 Error completing single drink order item:", error);
    return res.status(500).json({
      message: "Error completing single drink order item",
      error: error.message,
    });
  }
};



// ✅ Get user drink order history
const getDrinkOrderHistoryByUser = async (req, res) => {
  const { userId } = req.params;

  try {
    const orderHistory = await DrinksOrder.findAll({
      where: { userId },
      include: [
        { model: DrinksMenu, as: "drink", attributes: ["name", "price"] },
      ],
      order: [["createdAt", "DESC"]],
    });

    if (!orderHistory.length) {
      return res
        .status(404)
        .json({ message: "No drink order history found for this user." });
    }

    res.status(200).json(orderHistory);
  } catch (error) {
    console.error("Error fetching drink order history:", error);
    res.status(500).json({
      message: "Error fetching drink order history",
      error: error.message,
    });
  }
};

module.exports = {
  getDrinksOrders,
  getDrinksOrderById,
  createDrinkOrder,
  updateDrinkOrder,
  deleteDrinkOrder,
  acceptDrinkOrder,
  completedDrinkOrder,
  completeSingleDrinkOrderItem,
  getDrinkOrderHistoryByUser,
};