// controllers/FoodController/orderController.js
const bcrypt = require("bcryptjs");
const {
  Table,
  Order,
  Menu,
  MenuIngredient,
  Ingredient,
  KitchenInventory,
  Inventory, // ✅ Likely missing import for createOrder
  User,
  OrderItem,
  Section,
  DrinksMenu,
  DrinksOrder,
  CanceledFoodOrder,
  DrinksKitchenInventory,
  DrinksMenuIngredient,
  DrinksIngredient,
  Category,
  
} = require("../../models");
const section = require("../../models/section");
const { sequelize } = require('../../models'); // assuming sequelize is used for models
const { Op } = require('sequelize');

const { convertUnits } = require("../../utils/unitConverter");
const moment = require("moment-timezone");




const getOrCreateDuplicateTable = async (parentTable, transaction) => {
  // SAFETY CHECK
  if (!parentTable || !parentTable.id) {
    throw new Error("Invalid parent table instance passed");
  }

  // 1️⃣ Look for existing active split
  const existingSplit = await Table.findOne({
    where: {
      parent_table_id: parentTable.id,
      is_split: true,
      status: { [Op.notIn]: ["free", "settleUp"] },
    },
    transaction,
    lock: transaction.LOCK.UPDATE,
  });

  if (existingSplit) return existingSplit;

  // 2️⃣ Count existing splits
  const splitCount = await Table.count({
    where: { parent_table_id: parentTable.id },
    transaction,
  });

  const splitName = String.fromCharCode(65 + splitCount); // A, B, C...

  // 3️⃣ CREATE NEW ROW (NO ID PASSED)
  const newSplit = await Table.create(
    {
      sectionId: parentTable.sectionId,
      status: "occupied",
      seatingCapacity: parentTable.seatingCapacity,
      seatingTime: new Date(),
      is_split: true,
      parent_table_id: parentTable.id,
      split_name: splitName,
      display_number: parentTable.display_number,
      isComplimentary: false,
      merged_with: [],
    },
    { transaction }
  );

  return newSplit;
};


// ✅ Get all orders
const getOrders = async (req, res) => {
  try {
    const orders = await Order.findAll({
      include: [
        {
          model: Menu,
          as: "menu",
          attributes: ["name", "price", "kotCategory"],
        },
        {
          model: User,
          as: "user",
          attributes: ["name"],
        },
        {
          model: Section,
          as: "section",
          attributes: ["name"],
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
        },
      ],
      // ✅ ADD shifted_from_table here — without this it is stripped from the response
      attributes: {
        include: ["shifted_from_table", "restaurent_table_number"],
      },
      order: [["createdAt", "DESC"]],
    });

    const formattedOrders = orders.map((order) => {
  const orderJson = order.toJSON();

  // 🕒 timezone formatting
  orderJson.createdAt = moment(orderJson.createdAt)
    .tz("Asia/Kolkata")
    .format();
  orderJson.updatedAt = moment(orderJson.updatedAt)
    .tz("Asia/Kolkata")
    .format();

  // 🪑 TABLE DISPLAY NAME LOGIC
  if (orderJson.table) {
    const table = orderJson.table;

    if (table.is_split && table.parent_table_id && table.split_name) {
      // Example: 132 + A => 132A
      orderJson.table_display_name = `${table.parent_table_id}${table.split_name}`;
    } else {
      // Normal table
      orderJson.table_display_name = `${table.id}`;
      // OR use display_number if that’s your UI standard:
      // orderJson.table_display_name = `${table.display_number}`;
    }
  }

  return orderJson;
});


    res.json(formattedOrders);
  } catch (error) {
    console.error("Error fetching orders:", error);
    res
      .status(500)
      .json({ message: "Error fetching orders", error: error.message });
  }
};

// ✅ Get order by ID
const getOrderById = async (req, res) => {
  try {
    const order = await Order.findByPk(req.params.id, {
      include: [
        { model: Menu, as: "menu", attributes: ["name", "price", "kotCategory"] },
        { model: User, as: "user", attributes: ["name"] },
      ],
    });
    if (!order) {
      return res.status(404).json({ message: "Order not found" });
    }
    res.json(order);
  } catch (error) {
    console.error("Error fetching order by ID:", error);
    res
      .status(500)
      .json({ message: "Error fetching order", error: error.message });
  }
};



// ✅ Create order
const createOrder = async (req, res) => {
  const transaction = await sequelize.transaction();
  try {
    const { userId, sectionId, restaurantTableId, tableId, items } = req.body;
    console.log(req.body);

    if (!tableId || !Array.isArray(items) || items.length === 0) {
      await transaction.rollback();
      return res
        .status(400)
        .json({ message: "Table ID and items are required" });
    }
    if (!restaurantTableId) {
      await transaction.rollback();
      return res
        .status(400)
        .json({ message: "Restaurant Table ID is required" });
    }

    let table = await Table.findByPk(tableId, { transaction });
    if (!table) {
      await transaction.rollback();
      return res.status(404).json({ message: "Table not found" });
    }

    let actualTableId = tableId;
    let actualRestaurantTableId = restaurantTableId;

    // NEW: If table is in settleUp, create duplicate
    if (table.status === "settleUp") {
      const duplicate = await getOrCreateDuplicateTable(table, transaction);
      actualTableId = duplicate.id;
      actualRestaurantTableId = duplicate.display_number;
      table = duplicate; // Use duplicate for subsequent operations
    } else if (table.status !== "occupied") {
      await table.update(
        { status: "occupied", seatingTime: new Date() },
        { transaction }
      );
    }

    const section = sectionId
      ? await Section.findByPk(sectionId, { transaction })
      : null;
    const createdOrderItems = [];

    let createdOrder = null;
    let createdUser = null;

    if (userId) {
      createdUser = await User.findByPk(userId, { transaction });
    }

    const createdOrderIds = [];
    let allItemsCanceled = true;

    const now = new Date();
    const istNow = new Date(
      now.toLocaleString("en-US", { timeZone: "Asia/Kolkata" })
    );

    let kotReset = new Date(istNow);
    kotReset.setHours(5, 0, 0, 0);

    if (istNow < kotReset) {
      kotReset.setDate(kotReset.getDate() - 1);
    }

    const kotResetUtc = new Date(
      kotReset.toLocaleString("en-US", { timeZone: "UTC" })
    );

    const lastFoodKot = await OrderItem.findOne({
      where: {
        food: true,
        createdAt: { [Op.gte]: kotResetUtc },
      },
      order: [["kotNumber", "DESC"]],
      transaction,
    });

    const kotNumber = lastFoodKot ? lastFoodKot.kotNumber + 1 : 1;

    const gstRate = 0.05;

    for (const item of items) {
      const itemIdRaw = item.itemId ?? item.menuId ?? null;
      const itemId = itemIdRaw ? parseInt(itemIdRaw, 10) : null;

      const rawName = item.itemName ?? item.name ?? null;
      const description = item.description ?? item.desc ?? null;
      const quantity = Number(item.quantity ?? 1);
      const priceProvided = Number(item.price ?? 0);
      const isCustomItem = !itemId;

      const itemName = item.openfood ? description : rawName;

      if (!Number.isFinite(quantity) || quantity <= 0) {
        await transaction.rollback();
        return res.status(400).json({
          message: "Each item must have a positive numeric quantity",
        });
      }
      if (!Number.isFinite(priceProvided) || priceProvided <= 0) {
        await transaction.rollback();
        return res
          .status(400)
          .json({ message: "Each item must have a positive numeric price" });
      }

      let menuItem = null;
      let actualPrice = priceProvided;
      let categoryName = null;
      let commissionTotal = 0;
      let categoryId = null;

      if (!isCustomItem) {
        menuItem = await Menu.findByPk(itemId, { transaction });
        if (!menuItem) {
          await transaction.rollback();
          return res
            .status(404)
            .json({ message: `Menu item with ID ${itemId} not found` });
        }

        categoryId = menuItem.categoryId;

        if (categoryId) {
          const category = await Category.findByPk(categoryId, { transaction });
          if (category) categoryName = category.name;
        }

        actualPrice = menuItem.isOffer ? menuItem.offerPrice : priceProvided;

        if (menuItem.isOffer) {
          const waiterCommission = menuItem.waiterCommission ?? 0;
          const commissionType = menuItem.commissionType ?? "flat";
          commissionTotal =
            commissionType === "percentage"
              ? (menuItem.offerPrice * waiterCommission * quantity) / 100
              : waiterCommission * quantity;
        }
      }

      const amount = actualPrice * quantity;

      const newOrder = await Order.create(
        {
          userId,
          menuId: menuItem ? menuItem.id : null,
          item_desc: itemName || "",
          quantity,
          amount,
          is_custom: !!isCustomItem,
          table_number: actualTableId,
          restaurent_table_number: actualRestaurantTableId,
          section_number: sectionId,
          kotNumber,
        },
        { transaction }
      );

      createdOrderIds.push(newOrder.id);

      const orderItem = await OrderItem.create(
        {
          food: true,
          userId,
          menuId: menuItem ? menuItem.id : null,
          orderId: newOrder.id,
          quantity,
          price: actualPrice,
          commissionTotal,
          categoryId,
          name: itemName,
          desc: description || null,
          is_custom: !!isCustomItem,
          kotNumber,
        },
        { transaction }
      );

      createdOrderItems.push({
        orderItem: {
          ...orderItem.toJSON(),
          price: actualPrice,
          amount_per_item: actualPrice,
        },
        menuItem: menuItem
          ? {
              id: menuItem.id,
              name: menuItem.name,
              kotCategory: menuItem.kotCategory,
              categoryName,
            }
          : {
              id: null,
              name: itemName,
              kotCategory: item.kotCategory ?? null,
              categoryName: item.categoryName ?? null,
            },
      });

      if (!createdOrder) createdOrder = newOrder;
    }

    await transaction.commit();

    const io = req.app.get("io");
    io.emit("new_foods_order", {
      order: {
        id: createdOrder.id,
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

    return res.status(201).json({
      message: "Food orders and items created successfully with kotNumbers",
      kotNumber,
      created: createdOrderItems,
      allItemsCanceled,
    });
  } catch (error) {
    try {
      await transaction.rollback();
    } catch {}
    console.error("Error creating order:", error);
    return res
      .status(500)
      .json({ message: "Error creating order", error: error.message });
  }
};





// ✅ Update order
const updateOrder = async (req, res) => {
  try {
    const { id } = req.params;
    const { MenuId, item_desc, quantity, status, amount, table_number } =
      req.body;

    const order = await Order.findByPk(id);
    if (!order) return res.status(404).json({ message: "Order not found" });

    await order.update({
      MenuId: MenuId || order.MenuId,
      item_desc: item_desc || order.item_desc,
      quantity: quantity || order.quantity,
      status: status || order.status,
      amount: amount || order.amount,
      table_number: table_number || order.table_number,
    });

    res.status(200).json(order);
  } catch (error) {
    console.error("Error updating order:", error);
    res
      .status(500)
      .json({ message: "Error updating order", error: error.message });
  }
};



//------------------------------------------------------------
// ✅ Delete order
const deleteOrder = async (req, res) => {
  const t = await sequelize.transaction();
  try {
    const {
      password,
      userId,
      quantity,
      table_id,
      menuId,
      remarks = '', 
      status // optional
    } = req.body;

    // 🔹 Validation
    if (!userId || !password) {
      await t.rollback();
      return res.status(400).json({ message: "userId and password are required" });
    }

    const qtyRequested = Number.parseInt(quantity, 10);
    if (!Number.isInteger(qtyRequested) || qtyRequested <= 0) {
      await t.rollback();
      return res.status(400).json({ message: "quantity must be a positive integer" });
    }

    if (table_id == null) {
      await t.rollback();
      return res.status(400).json({ message: "table_id is required" });
    }

    // 🔹 Case 1: Handle custom (open) orders with no menuId
    if (!menuId) {
      const customOrders = await Order.findAll({
        where: {
          table_number: table_id,
          is_custom: true,
          menuId: null,
        },
        order: [["createdAt", "DESC"]],
        transaction: t,
        lock: t.LOCK.UPDATE,
      });

      if (!customOrders.length) {
        await t.rollback();
        return res.status(404).json({
          message: "No custom (open) orders found to delete",
        });
      }

      const io = req.app.get("io");
      const deletedCustom = [];
      let qtyLeft = qtyRequested;

      for (const order of customOrders) {
        if (qtyLeft <= 0) break;

        const rowQty = typeof order.quantity === "number" && order.quantity > 0 ? order.quantity : 1;
        const customName = order.item_desc || "Custom Item";
        const sectionNumberValue = order.section_number || null;
        const restaurentTableNumberValue = order.restaurent_table_number || null;

        if (rowQty > qtyLeft) {
          // Partial delete
          const removed = qtyLeft;
          const newQty = rowQty - removed;

          // 🧮 Update amount properly
          const actualPrice = order.quantity > 0 ? (order.amount / order.quantity) : 0;
          const newAmount = actualPrice * newQty;

          await order.update({ quantity: newQty, amount: newAmount }, { transaction: t });

          await CanceledFoodOrder.create({
            menuId: null,
            count: removed,
            userId: order.userId || userId,
            tableNumber: order.table_number,
            section_number: sectionNumberValue,
            restaurent_table_number: restaurentTableNumberValue,
            customName,
            is_custom: true,
            deletedBy: userId,
          }, { transaction: t });

          if (io) {
            const deletionPayload = {
              orderId: orderId,
              kotNumber: kotNumber || null,
              itemName,
              table_number: order.table_number,
              restaurant_table_number: order.restaurent_table_number || restaurentTableNumberValue,
              section_number: order.section_number || sectionNumberValue,
              removedAmount: totalAmountToMove, // ✅ Add this to help frontend update totals
              removedQuantity: qtyToDelete,
              status: order.status, // ✅ Which list it was in (pending/ongoing/complete)
            };
            
            console.log(`[sockets] Emitting order_deleted:`, deletionPayload);
            io.emit('order_deleted', deletionPayload);
          }

          deletedCustom.push({ orderId: order.id, customName, removed, newQty });
          qtyLeft = 0;
          break;
        } else {
          // Full delete
          const removed = rowQty;
          await order.destroy({ transaction: t });

          await CanceledFoodOrder.create({
            menuId: null,
            count: removed,
            userId: order.userId || userId,
            tableNumber: order.table_number,
            section_number: sectionNumberValue,
            restaurent_table_number: restaurentTableNumberValue,
            customName,
            is_custom: true,
            deletedBy: userId,
          }, { transaction: t });

          if (io) {
            console.log(`[sockets] Emitting order_deleted for custom food order ${order.id} table ${order.table_number}`);
            io.emit("order_deleted", { orderId: order.id, itemName: customName, table_number: order.table_number, restaurant_table_number: order.restaurent_table_number });
          }

          deletedCustom.push({ orderId: order.id, customName, removed });
          qtyLeft -= removed;
        }
      }

      await t.commit();
      return res.json({
        message: qtyLeft === 0
          ? `Deleted ${deletedCustom.length} custom (open) order(s) successfully.`
          : `Partially deleted custom orders. ${qtyLeft} remaining.`,
        deletedCustom,
        remainingToRemove: qtyLeft,
      });
    }

    // 🔹 Case 2: Normal menu item orders

    // Authenticate user
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

    // Fetch candidate orders
    const whereForIds = { menuId, table_number: table_id };
    if (status) whereForIds.status = status;

    const ordersLight = await Order.findAll({
      where: whereForIds,
      attributes: [
        "id", "menuId", "quantity", "status", "table_number", "item_desc",
        "kotNumber", "createdAt", "userId", "section_number",
        "restaurent_table_number", "amount"
      ],
      order: [["createdAt", "DESC"]],
      transaction: t,
    });

    if (!ordersLight.length) {
      await t.rollback();
      return res.status(404).json({ message: "No matching orders found" });
    }

    const ids = ordersLight.map(o => o.id);
    const menuIds = [...new Set(ordersLight.map(o => o.menuId).filter(Boolean))];
    const menus = menuIds.length
      ? await Menu.findAll({ where: { id: menuIds }, transaction: t })
      : [];
    const menuMap = new Map(menus.map(m => [m.id, m.name]));

    // Lock orders
    const matchingOrders = await Order.findAll({
      where: { id: ids },
      order: [["createdAt", "DESC"]],
      transaction: t,
      lock: t.LOCK.UPDATE,
    });

    const io = req.app.get("io");
    let qtyLeft = qtyRequested;
    const deletedRows = [];
    const updatedRows = [];
    const lightMap = new Map(ordersLight.map(o => [o.id, o]));

    for (const order of matchingOrders) {
      if (qtyLeft <= 0) break;

      const rowQty = typeof order.quantity === "number" && order.quantity > 0 ? order.quantity : 1;
      const light = lightMap.get(order.id);
      const itemName = (light && light.item_desc?.toString().trim()) || menuMap.get(order.menuId) || "Unnamed Item";
      const sectionNumberValue = order.section_number || (light && light.section_number) || null;
      const restaurentTableNumberValue = order.restaurent_table_number || (light && light.restaurent_table_number) || null;
      const kotNumber = order.kotNumber || null;
      const orderId = order.id;

      if (rowQty > qtyLeft) {
        // Partial delete
        const removed = qtyLeft;
        const newQty = rowQty - removed;

        // 🧮 Update amount
        const actualPrice = order.quantity > 0 ? (order.amount / order.quantity) : 0;
        const newAmount = actualPrice * newQty;

        await order.update({ quantity: newQty, amount: newAmount }, { transaction: t });

        // Adjust order items
        let remainingToRemove = removed;
        const orderItems = await OrderItem.findAll({
          where: { orderId, food: true },
          order: [["createdAt", "DESC"]],
          transaction: t,
          lock: t.LOCK.UPDATE,
        });

        for (const oi of orderItems) {
          if (remainingToRemove <= 0) break;
          const oiQty = typeof oi.quantity === "number" && oi.quantity > 0 ? oi.quantity : 1;

          if (oiQty > remainingToRemove) {
            const newOiQty = oiQty - remainingToRemove;
            await oi.update({ quantity: newOiQty }, { transaction: t });

            await CanceledFoodOrder.create({
              menuId: order.menuId,
              count: remainingToRemove,
              userId: order.userId || userId,
              tableNumber: order.table_number,
              section_number: sectionNumberValue,
              restaurent_table_number: restaurentTableNumberValue,
              remarks: (remarks && remarks.trim()) ? remarks.trim() : null,
              deletedBy: userId,
            }, { transaction: t });

            remainingToRemove = 0;
            break;
          } else {
            await oi.destroy({ transaction: t });
            await CanceledFoodOrder.create({
              menuId: order.menuId,
              count: oiQty,
              userId: order.userId || userId,
              tableNumber: order.table_number,
              section_number: sectionNumberValue,
              restaurent_table_number: restaurentTableNumberValue,
              remarks: (remarks && remarks.trim()) ? remarks.trim() : null,
              deletedBy: userId,
            }, { transaction: t });
            remainingToRemove -= oiQty;
          }
        }

        if (remainingToRemove > 0) {
          await CanceledFoodOrder.create({
            menuId: order.menuId,
            count: remainingToRemove,
            userId: order.userId || userId,
            tableNumber: order.table_number,
            section_number: sectionNumberValue,
            restaurent_table_number: restaurentTableNumberValue,
            remarks: (remarks && remarks.trim()) ? remarks.trim() : null,
            deletedBy: userId,
          }, { transaction: t });
        }

        if (io) {
          io.emit("order_updated", {
            orderId,
            menuId: order.menuId,
            oldQuantity: rowQty,
            newQuantity: newQty,
            table_number: order.table_number,
            itemName,
          });
        }

        updatedRows.push({ orderId, oldQty: rowQty, newQty });
        qtyLeft = 0;
        break;
      } else {
        // Full delete
        const removed = rowQty;
        const orderItemsToDelete = await OrderItem.findAll({
          where: { orderId, food: true },
          transaction: t,
          lock: t.LOCK.UPDATE,
        });

        let sumOiQty = 0;
        for (const oi of orderItemsToDelete) {
          const oiQty = typeof oi.quantity === "number" && oi.quantity > 0 ? oi.quantity : 1;
          sumOiQty += oiQty;
        }

        await order.destroy({ transaction: t });
        for (const oi of orderItemsToDelete) await oi.destroy({ transaction: t });

        const canceledCount = sumOiQty > 0 ? sumOiQty : removed;
        await CanceledFoodOrder.create({
          menuId: order.menuId,
          count: canceledCount,
          userId: order.userId || userId,
          tableNumber: order.table_number,
          section_number: sectionNumberValue,
          restaurent_table_number: restaurentTableNumberValue,
          remarks: (remarks && remarks.trim()) ? remarks.trim() : null,
          deletedBy: userId,
        }, { transaction: t });

        if (io) {
          console.log(`[sockets] Emitting order_deleted for food order ${orderId} kot ${kotNumber} table ${order.table_number}`);
          io.emit("order_deleted", { orderId, kotNumber, itemName, table_number: order.table_number, restaurant_table_number: order.restaurent_table_number });
        }

        deletedRows.push({ orderId, kotNumber, itemName, removed, canceledCount });
        qtyLeft -= removed;
      }
    }

    await t.commit();
    const qtyRemoved = qtyRequested - qtyLeft;

    return res.json({
      message:
        qtyRemoved === qtyRequested
          ? `Removed ${qtyRemoved} item(s).`
          : `Removed ${qtyRemoved} item(s). Requested ${qtyRequested}, ${qtyLeft} remaining (not enough items).`,
      requested: qtyRequested,
      removed: qtyRemoved,
      remainingToRemove: qtyLeft,
      deletedRows,
      updatedRows,
    });

  } catch (err) {
    console.error("Error in deleteOrder:", err);
    try { await t.rollback(); } catch (e) {}
    return res.status(500).json({ message: "Error deleting orders", error: err.message });
  }
};





// ✅ Accept order and deduct ingredients (food)
const acceptOrder = async (req, res) => {
  const { kotNumber } = req.body;
  console.log("Accepting food orders for kotNumber:", kotNumber);

  if (!kotNumber) {
    return res.status(400).json({ message: "kotNumber is required" });
  }

  try {
    // 1️⃣ Fetch all orders for this KOT
    const orders = await Order.findAll({
      where: { kotNumber },
      include: [
        { model: Menu, as: "menu" },
        {
          model: Table,
          as: "table",
          include: [{ model: Section, as: "section" }],
        },
      ],
    });

    if (!orders || orders.length === 0) {
      return res
        .status(404)
        .json({ message: `No orders found for kotNumber ${kotNumber}` });
    }

    // 2️⃣ FILTER OUT COMPLETED ORDERS
    const activeOrders = orders.filter(
      (o) => o.status !== "completed"
    );

    // 🛑 If all orders are already completed → skip everything
    if (activeOrders.length === 0) {
      return res.status(200).json({
        message: `All orders for kotNumber ${kotNumber} are already completed. Skipping.`,
        skipped: true,
      });
    }

    // 3️⃣ Build aggregated ingredient requirements
    const aggregatedRequirements = new Map(); // inventoryId → total qty
    const menuIds = new Set();

    for (const order of activeOrders) {
      menuIds.add(order.menuId);
    }

    // 4️⃣ Fetch all menu ingredients
    const menuIngredients = await MenuIngredient.findAll({
      where: { MenuId: Array.from(menuIds) },
      attributes: ["MenuId", "inventoryId", "quantityRequired", "unit"],
    });

    const menuToIngredients = new Map();
    for (const mi of menuIngredients) {
      if (!menuToIngredients.has(mi.MenuId)) {
        menuToIngredients.set(mi.MenuId, []);
      }
      menuToIngredients.get(mi.MenuId).push(mi);
    }

    // 5️⃣ Aggregate ingredient quantities
    for (const order of activeOrders) {
      const qty = Number(order.quantity) || 1;
      const ingredients = menuToIngredients.get(order.menuId) || [];

      for (const ing of ingredients) {
        const required =
          (Number(ing.quantityRequired) || 0) * qty;

        aggregatedRequirements.set(
          ing.inventoryId,
          (aggregatedRequirements.get(ing.inventoryId) || 0) + required
        );
      }
    }

    // 6️⃣ Fetch kitchen inventory
    const inventoryIds = Array.from(aggregatedRequirements.keys());
    const kitchenInventories = await KitchenInventory.findAll({
      where: { inventoryId: inventoryIds },
    });

    const inventoryMap = new Map();
    kitchenInventories.forEach((ki) =>
      inventoryMap.set(ki.inventoryId, ki)
    );

    const shortages = [];
    const updates = [];

    // 7️⃣ Prepare inventory updates
    for (const [invId, required] of aggregatedRequirements.entries()) {
      const ki = inventoryMap.get(invId);

      if (!ki) {
        shortages.push({
          inventoryId: invId,
          required,
          available: 0,
        });
        continue;
      }

      const ingredient = menuIngredients.find(
        (m) => m.inventoryId === invId
      );
      const ingredientUnit = ingredient?.unit || "";

      let newQty = Number(ki.quantity) || 0;
      let newTotal = Number(ki.totalQuantityRemaining) || 0;

      if (
        ingredientUnit === "Kilogram (Kg)" &&
        ki.unit === "kg"
      ) {
        if (newQty < required) {
          shortages.push({
            inventoryId: invId,
            required,
            available: newQty,
          });
          continue;
        }
        newQty -= required;
        newTotal = newQty * (Number(ki.bagSize) || 1);
      } else if (ingredientUnit === "Bag") {
        if (newQty < required) {
          shortages.push({
            inventoryId: invId,
            required,
            available: newQty,
          });
          continue;
        }
        newQty -= required;
        newTotal = newQty * (Number(ki.bagSize) || 1);
      } else {
        if (newTotal < required) {
          shortages.push({
            inventoryId: invId,
            required,
            available: newTotal,
          });
          continue;
        }
        newTotal -= required;
        newQty = newTotal / (Number(ki.bagSize) || 1);
      }

      updates.push({
        inventoryId: invId,
        newQty,
        newTotal,
        deducted: required,
      });
    }

    // 8️⃣ Apply inventory updates transactionally
    const sequelize = Order.sequelize;
    let inventoriesUpdated = 0;

    await sequelize.transaction(async (t) => {
      for (const u of updates) {
        const ki = await KitchenInventory.findOne({
          where: { inventoryId: u.inventoryId },
          transaction: t,
          lock: t.LOCK.UPDATE,
        });

        if (!ki) continue;

        ki.quantity = u.newQty;
        ki.totalQuantityRemaining = u.newTotal;
        await ki.save({ transaction: t });
        inventoriesUpdated++;
      }
    });

    // 9️⃣ Mark ACTIVE orders as accepted
    const io = req.app.get("io");
    let updatedOrdersCount = 0;

    for (const order of activeOrders) {
      order.status = "accepted";
      await order.save();
      updatedOrdersCount++;

      if (io && order.table) {
        io.emit("update_order_status", {
          orderId: order.id.toString(),
          orderType: "food",
          newStatus: "ongoing",
          sectionId:
            order.table.section?.id ||
            order.table.sectionId,
          tableId:
            order.table.actual_table_number ||
            order.table.id,
          amount: parseFloat(
            ((order.amount || order.price || 0) * 1.05).toFixed(2)
          ),
          kotNumber: order.kotNumber,
          menuName: order.menu?.name || null,
        });
      }
    }

    //  🔁 Backward compatibility event
    if (io) {
      io.emit("order_accepted", { kotNumber });
    }

    // 🔚 Final response
    return res.status(200).json({
      message: `Orders with kotNumber ${kotNumber} processed successfully.`,
      totalOrders: orders.length,
      activeOrdersProcessed: activeOrders.length,
      inventoriesUpdated,
      shortages,
    });
  } catch (error) {
    console.error("🚨 Error accepting orders:", error);
    return res.status(500).json({
      message: "Error accepting orders",
      error: error.message,
    });
  }
};


const completedOrder = async (req, res) => {
  const { kotNumber } = req.body;
  console.log("Completing orders for kotNumber:", kotNumber, "body:", req.body);

  if (!kotNumber) {
    return res.status(400).json({ message: "kotNumber is required in body" });
  }

  try {
    // 1) Find all orders with this kotNumber, including table relations
    const orders = await Order.findAll({
      where: { kotNumber },
      include: [
        { 
          model: Table, 
          as: "table",
          include: [{ model: Section, as: "section" }]
        }
      ],
      attributes: ["id", "kotNumber", "status", "amount"], // Removed "price"
    });

    if (!orders || orders.length === 0) {
      console.log(`No orders found for kotNumber ${kotNumber}`);
      return res.status(404).json({ message: `No orders found for kotNumber ${kotNumber}` });
    }

    const orderIds = orders.map(o => o.id);
    console.log(`Found ${orderIds.length} order(s) for kotNumber ${kotNumber}:`, orderIds);

    // 2) Bulk update the Orders table -> set status = 'completed'
    const [ordersUpdatedCount] = await Order.update(
      { status: 'completed' },
      { where: { kotNumber } }
    );

    console.log(`Orders updated (status -> completed): ${ordersUpdatedCount}`);

    // 3) Update OrderItems if model exists
    let orderItemsUpdated = 0;
    try {
      if (typeof OrderItem !== 'undefined' && OrderItem) {
        const [count1] = await OrderItem.update(
          { status: 'completed' },
          { where: { orderId: { [Op.in]: orderIds } } }
        );
        orderItemsUpdated += count1 || 0;

        if (!orderItemsUpdated) {
          const [count2] = await OrderItem.update(
            { status: 'completed' },
            { where: { OrderId: { [Op.in]: orderIds } } }
          );
          orderItemsUpdated += count2 || 0;
        }
        console.log(`OrderItems updated (status -> completed): ${orderItemsUpdated}`);
      }
    } catch (itemErr) {
      console.error("Error updating OrderItem rows:", itemErr);
    }

    // 4) Emit socket events
    try {
      const io = req.app && req.app.get ? req.app.get('io') : null;
      if (io) {
        // Emit individual status updates for each order
        // In completedOrder function, around line 850
        for (const order of orders) {
          if (order.table) {
            io.emit('update_order_status', {
              orderId: order.id.toString(),
              orderType: 'food',
              newStatus: 'completed',
              sectionId: order.table.section?.id || order.table.sectionId,
              tableId: order.table.actual_table_number || order.table.id,
              amount: 0, // ✅ Don't send amount - Flutter will use stored values
              kotNumber: order.kotNumber,
              menuName: order.menu?.name || null, // ✅ Add menu name
              menuId: order.menuId?.toString() || null, // ✅ Add menuId for matching
            });
          }
        }
        // Emit batch completion event for backward compatibility
        io.emit('order_completed', { kotNumber, orderIds });
        console.log(`Socket events emitted for kotNumber ${kotNumber}`);
      } else {
        console.log('Socket instance not found on req.app; skipping emit.');
      }
    } catch (emitErr) {
      console.error('Error emitting socket events:', emitErr);
    }

    // 5) Return summary
    return res.status(200).json({
      message: `Orders with kotNumber ${kotNumber} marked completed.`,
      kotNumber,
      totalOrdersFound: orders.length,
      ordersUpdated: ordersUpdatedCount,
      orderItemsUpdated,
    });
  } catch (error) {
    console.error("🚨 Error completing orders:", error);
    return res.status(500).json({ message: "Error completing orders", error: error.message });
  }
};



const completeSingleOrderItem = async (req, res) => {
  const { id } = req.params;

  console.log("Completing single order item:", id);

  if (!id) {
    return res.status(400).json({ message: "Item ID (id) is required in the route parameter." });
  }

  try {
    const orderItem = await Order.findOne({
      where: { id },
      include: [
        {
          model: Table,
          as: "table",
          include: [{ model: Section, as: "section" }],
        },
        {
          model: Menu,
          as: "menu",
          attributes: ["name"],
        },
      ],
      attributes: ["id", "kotNumber", "status", "amount", "menuId"],
    });

    if (!orderItem) {
      return res.status(404).json({ message: `No order item found with ID ${id}` });
    }

    await orderItem.update({ status: "completed" });
    console.log(`✅ Order item ID ${id} marked as completed.`);

    try {
      const io = req.app?.get("io");
      if (io && orderItem.table) {
        // ✅ FIXED: Emit order_item_completed event instead of update_order_status
        io.emit("order_item_completed", {
          orderId: orderItem.id.toString(),
          orderType: "food",
          newStatus: "completed",
          sectionId: orderItem.table.section?.id || orderItem.table.sectionId,
          tableId: orderItem.table.actual_table_number || orderItem.table.id,
          amount: 0, // ✅ Don't send amount - Flutter will use stored values
          kotNumber: orderItem.kotNumber,
          menuName: orderItem.menu?.name || null,
          itemName: orderItem.menu?.name || null, // ✅ Add itemName for Flutter matching
        });

        console.log(
          `🔊 order_item_completed event emitted for order ID ${orderItem.id} (kot: ${orderItem.kotNumber})`
        );
      } else {
        console.log("Socket instance or table info missing; skipping emit.");
      }
    } catch (emitErr) {
      console.error("Error emitting socket event:", emitErr);
    }

    return res.status(200).json({
      message: `Order item with ID ${id} marked as completed.`,
      item: {
        id: orderItem.id,
        kotNumber: orderItem.kotNumber,
        status: orderItem.status,
        amount: orderItem.amount,
      },
    });
  } catch (error) {
    console.error("🚨 Error completing single order item:", error);
    return res.status(500).json({
      message: "Error completing single order item",
      error: error.message,
    });
  }
};



// ✅ Reject order and release table if all done
const rejectedOrder = async (req, res) => {
  const { orderId } = req.params;

  try {
    const order = await Order.findByPk(orderId);
    if (!order) return res.status(404).json({ message: "Order not found" });

    order.status = "rejected";
    await order.save();

    res.status(200).json({ message: "Order Rejected!" });
  } catch (error) {
    console.error("Error rejecting order:", error);
    res
      .status(500)
      .json({ message: "Error rejecting order", error: error.message });
  }
};

// ✅ Get user order history
const getOrderHistoryByUser = async (req, res) => {
  const { userId } = req.params;

  try {
    const orderHistory = await Order.findAll({
      where: { userId },
      include: [{ model: Menu, as: "menu", attributes: ["name", "price"] }],
      order: [["createdAt", "DESC"]],
    });

    if (!orderHistory.length) {
      return res
        .status(404)
        .json({ message: "No order history found for this user." });
    }

    res.status(200).json(orderHistory);
  } catch (error) {
    console.error("Error fetching order history:", error);
    res
      .status(500)
      .json({ message: "Error fetching order history", error: error.message });
  }
};

const getAllRunningOrders = async (req, res) => {
  try {
    // Fetch all food orders
    const foodOrders = await Order.findAll({
      include: [
        { model: Menu, as: "menu", attributes: ["name", "price"] },
        { model: User, as: "user", attributes: ["name"] },
        { model: Section, as: "section", attributes: ["name"] },
      ],
    });

    // Fetch all drink orders
    const drinkOrders = await DrinksOrder.findAll({
      include: [
        { model: DrinksMenu, as: "drink", attributes: ["name", "price"] },
        { model: User, as: "user", attributes: ["name"] },
        { model: Section, as: "section", attributes: ["name"] },
      ],
    });

    // Format food orders
    const formattedFoodOrders = foodOrders.map((order) => {
      const orderJson = order.toJSON();
      orderJson.createdAt = moment(orderJson.createdAt)
        .tz("Asia/Kolkata")
        .format();
      orderJson.updatedAt = moment(orderJson.updatedAt)
        .tz("Asia/Kolkata")
        .format();
      orderJson.orderType = "food"; // Add type for frontend distinction
      return orderJson;
    });

    // Format drink orders
    const formattedDrinkOrders = drinkOrders.map((order) => {
      const orderJson = order.toJSON();
      orderJson.createdAt = moment(orderJson.createdAt)
        .tz("Asia/Kolkata")
        .format();
      orderJson.updatedAt = moment(orderJson.updatedAt)
        .tz("Asia/Kolkata")
        .format();
      orderJson.orderType = "drink"; // Add type for frontend distinction
      return orderJson;
    });

    // Merge and sort all orders by creation date (newest first)
    const allOrders = [...formattedFoodOrders, ...formattedDrinkOrders].sort(
      (a, b) => new Date(b.createdAt) - new Date(a.createdAt)
    );

    // Send response
    res.json(allOrders);
  } catch (error) {
    console.error("Error fetching all orders:", error);
    res
      .status(500)
      .json({ message: "Error fetching all orders", error: error.message });
  }
};



const shiftOrder = async (req, res) => {
  const transaction = await sequelize.transaction();

  try {
    const {
      fromTableId,
      toTableId,
      orderIds,
      kotNumber,
      orderType = 'food'
    } = req.body;

    console.log('📦 Shift request:', req.body);

    if (!fromTableId || !toTableId) {
      await transaction.rollback();
      return res.status(400).json({ message: 'fromTableId and toTableId required' });
    }

    if (!orderIds?.length && !kotNumber) {
      await transaction.rollback();
      return res.status(400).json({ message: 'orderIds or kotNumber required' });
    }

    /* ------------------ LOCK TABLES ------------------ */
    const [fromTable, toTable] = await Promise.all([
      Table.findByPk(fromTableId, { transaction, lock: transaction.LOCK.UPDATE }),
      Table.findByPk(toTableId, { transaction, lock: transaction.LOCK.UPDATE })
    ]);

    if (!fromTable || !toTable) {
      await transaction.rollback();
      return res.status(404).json({ message: 'Table not found' });
    }

    console.log('✅ Tables locked:', {
      from: { id: fromTable.id, display: fromTable.display_number },
      to: { id: toTable.id, display: toTable.display_number }
    });

    /* ------------------ STEP 1: FETCH ORDER ITEMS ------------------ */
    const orderItemWhere = kotNumber
      ? { kotNumber }
      : { id: { [Op.in]: orderIds } };

    const orderItems = await OrderItem.findAll({
      where: orderItemWhere,
      transaction,
      lock: transaction.LOCK.UPDATE
    });

    if (!orderItems.length) {
      await transaction.rollback();
      return res.status(404).json({ message: 'No order items found' });
    }

    /* ------------------ STEP 2: EXTRACT ORDER IDS ------------------ */
    const uniqueOrderIds = [...new Set(orderItems.map(i => i.orderId))];

    console.log('🧾 Order IDs resolved:', uniqueOrderIds);

    /* ------------------ STEP 3: FETCH ORDERS ------------------ */
    const orders = await Order.findAll({
      where: {
        id: { [Op.in]: uniqueOrderIds },
        table_number: fromTableId,
        status: { [Op.in]: ['pending', 'ongoing', 'accepted'] }
      },
      include: [
        { model: Menu, as: 'menu', attributes: ['name'] },
        { model: Section, as: 'section', attributes: ['name'] }
      ],
      transaction,
      lock: transaction.LOCK.UPDATE
    });

    if (!orders.length) {
      await transaction.rollback();
      return res.status(404).json({
        message: 'No matching orders found for this table'
      });
    }

    /* ------------------ STEP 4: UPDATE ORDERS ------------------ */
    const updatedOrderIds = [];

    for (const order of orders) {
      await order.update(
        {
          table_number: toTableId,
          restaurent_table_number: toTable.display_number,
          shifted_from_table: fromTableId
        },
        { transaction }
      );

      updatedOrderIds.push(order.id);
    }

    /* ------------------ STEP 5: UPDATE TABLE STATES ------------------ */
    if (toTable.status === 'free') {
      await toTable.update(
        { status: 'occupied', seatingTime: new Date() },
        { transaction }
      );
    }

    const remainingFood = await Order.count({
      where: {
        table_number: fromTableId,
        status: { [Op.ne]: 'completed' }
      },
      transaction
    });

    const remainingDrinks = await DrinksOrder.count({
      where: {
        table_number: fromTableId,
        status: { [Op.ne]: 'completed' }
      },
      transaction
    });

    if (remainingFood === 0 && remainingDrinks === 0) {
      await fromTable.update(
        { status: 'free', seatingTime: null },
        { transaction }
      );
    }

    await transaction.commit();

    /* ------------------ SOCKET EVENT ------------------ */
    const io = req.app.get('io');
    io?.emit('order_shifted', {
      fromTableId,
      toTableId,
      orderIds: updatedOrderIds,
      kotNumber: kotNumber ?? null
    });

    return res.status(200).json({
      message: 'Orders shifted successfully',
      ordersShifted: updatedOrderIds.length,
      orderIds: updatedOrderIds
    });

  } catch (error) {
    await transaction.rollback();
    console.error('❌ Shift order error:', error);
    return res.status(500).json({
      message: 'Internal server error',
      error: error.message
    });
  }
};




module.exports = {
  getOrders,
  getOrderById,
  createOrder,
  updateOrder,
  deleteOrder,
  acceptOrder,
  completedOrder,
  completeSingleOrderItem,
  getOrderHistoryByUser,
  rejectedOrder,
  getAllRunningOrders,
  shiftOrder,
};