const express = require("express");
const {
  getDrinksOrders,
  getDrinksOrderById,
  createDrinkOrder,
  updateDrinkOrder,
  deleteDrinkOrder,
  acceptDrinkOrder,
  completedDrinkOrder,
  completeSingleDrinkOrderItem,
  getDrinkOrderHistoryByUser,
} = require("../../controllers/DrinksController/drinksOrderController");
const authenticate = require("../../middlewares/authenticate");

const router = express.Router();

// Get all orders
router.get("/", getDrinksOrders);


// ✅ Accept order and deduct ingredients
router.put("/accept", acceptDrinkOrder);

// ✅ Mark order Complete
router.put("/complete", completedDrinkOrder);

// Get order by ID
router.get("/:id", getDrinksOrderById);

// Create new order
router.post("/", createDrinkOrder);

// Complete Single order
router.put("/:id/complete", completeSingleDrinkOrderItem);

// Update order
router.put("/:id", updateDrinkOrder);

// Delete order
router.delete("/:id", deleteDrinkOrder);



// ✅ get DrinkOrder History By User
router.get("/:userId/order-history", getDrinkOrderHistoryByUser);

module.exports = router;
