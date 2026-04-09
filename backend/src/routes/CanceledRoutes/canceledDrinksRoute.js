const express = require("express");
const {
  getCanceledDrinkOrders,
} = require("../../controllers/CanceledOrdersController/canceledDrinkOrdersController");

const router = express.Router();

router.get("/", getCanceledDrinkOrders);

module.exports = router;
