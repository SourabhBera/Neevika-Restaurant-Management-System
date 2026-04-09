const express = require("express");
const {
  getCanceledFoodOrders,
} = require("../../controllers/CanceledOrdersController/canceledFoodOrdersController");

const router = express.Router();

router.get("/", getCanceledFoodOrders);

module.exports = router;
