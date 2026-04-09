const { CanceledFoodOrder, Menu, User } = require("../../models");
const logger = require("../../configs/logger");

/**
 * Get all canceled food orders
 */
const getCanceledFoodOrders = async (req, res) => {
  try {
    const canceledOrders = await CanceledFoodOrder.findAll({
      include: [
        {
          model: Menu,
          as: "menu",
          attributes: ["id", "name", "price"],
        },
        {
          model: User,
          as: "user",
          attributes: ["id", "name", "email"],
        },
      ],
      order: [["createdAt", "DESC"]],
    });

    res.status(200).json({
      message: "Canceled food orders fetched successfully",
      data: canceledOrders,
    });
  } catch (error) {
    logger.error("Error fetching canceled food orders", error);
    res.status(500).json({
      message: "Error fetching canceled food orders",
      error: error.message,
    });
  }
};

module.exports = {
  getCanceledFoodOrders,
};
