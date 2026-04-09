const express = require('express');
const authenticate = require('../../middlewares/authenticate');
const authorize = require('../../middlewares/authorize');
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
const {
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
} = require('../../controllers/FoodController/orderController');

const router = express.Router();



// Get all running orders (fixed route)

router.get('/all-running', getAllRunningOrders);

// Get all orders
router.get('/', getOrders);

// Accept order and deduct ingredients
router.put('/accept', acceptOrder);


// Add this route (place it before the dynamic :id routes)
router.put('/shift', shiftOrder);

// Mark order Complete
// router.put('/complete', completedOrder);

// Get order history by user (fixed route to avoid conflict)
router.get('/user/:userId/order-history', getOrderHistoryByUser);


// ✅ NEW: Complete single OrderItem by OrderItem.id
router.put('/item/:id/complete', async (req, res) => {
  const { id } = req.params;
  
  console.log("=== COMPLETE SINGLE ITEM DEBUG ===");
  console.log("Order.id received:", id);

  if (!id) {
    return res.status(400).json({ 
      message: "Order ID is required in the route parameter." 
    });
  }

  try {
    // 1) Find the Order (parent) that needs to be completed
    const order = await Order.findOne({
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
          attributes: ["name", "id"],
        },
      ],
      attributes: ["id", "kotNumber", "status", "amount", "menuId", "quantity", "item_desc"],
    });

    if (!order) {
      return res.status(404).json({ 
        message: `Order with ID ${id} not found` 
      });
    }

    console.log("Found Order:", {
      id: order.id,
      kotNumber: order.kotNumber,
      menuId: order.menuId,
      itemName: order.item_desc || order.menu?.name,
    });

    // 2) Update Order status to 'completed'
    await order.update({ status: "completed" });
    console.log(`✅ Order ID ${order.id} marked as completed.`);

    // 3) Emit socket event with complete information
    try {
      const io = req.app?.get("io");
      if (io && order.table) {
        const eventPayload = {
          orderId: order.id.toString(), // ✅ This is the Order.id
          orderType: "food",
          newStatus: "completed",
          sectionId: order.table.section?.id || order.table.sectionId,
          tableId: order.table.actual_table_number || order.table.id,
          amount: parseFloat(order.amount || 0),
          kotNumber: order.kotNumber,
          itemName: order.item_desc || order.menu?.name || 'Item',
          menuId: order.menuId?.toString() || null,
          quantity: order.quantity || 1,
        };

        console.log("Emitting order_item_completed:", eventPayload);
        io.emit("order_item_completed", eventPayload);

        console.log(
          `🔊 Socket event emitted for Order ID ${order.id} (kot: ${order.kotNumber})`
        );
      } else {
        console.log("Socket instance or table info missing; skipping emit.");
      }
    } catch (emitErr) {
      console.error("Error emitting socket event:", emitErr);
    }

    // 4) Respond success
    return res.status(200).json({
      message: `Order item with ID ${id} marked as completed.`,
      item: {
        id: order.id,
        kotNumber: order.kotNumber,
        status: order.status,
        amount: order.amount,
        itemName: order.item_desc || order.menu?.name,
      },
    });
  } catch (error) {
    console.error("🚨 Error completing single order item:", error);
    return res.status(500).json({
      message: "Error completing single order item",
      error: error.message,
    });
  }
});


router.put('/:id/complete', completeSingleOrderItem);


// Get order by ID (dynamic route, placed after fixed routes)
router.get('/:id', getOrderById);

// Create new order
router.post('/', createOrder);

// Update order
router.put('/:id', updateOrder);

// Delete order
router.delete('/:id', deleteOrder);


// Mark order Rejected
router.put('/:orderId/reject', rejectedOrder);

module.exports = router;
