const { CanceledDrinkOrder, DrinksMenu, User } = require("../../models");
const logger = require("../../configs/logger");

/**
 * Get all canceled drink orders
 */
const getCanceledDrinkOrders = async (req, res) => {
  try {
    const canceledOrders = await CanceledDrinkOrder.findAll({
      include: [
        {
          model: DrinksMenu,
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
      message: "Canceled drink orders fetched successfully",
      data: canceledOrders,
    });
  } catch (error) {
    logger.error("Error fetching canceled drink orders", error);
    res.status(500).json({
      message: "Error fetching canceled drink orders",
      error: error.message,
    });
  }
};

module.exports = {
  getCanceledDrinkOrders,
};
