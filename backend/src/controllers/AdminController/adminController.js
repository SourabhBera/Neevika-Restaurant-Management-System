const {
  User,
  Inventory,
  Order,
  Menu,
  Bill,
  Table,
  OrderItem,
  CustomerDetails,
  DaySummary,
  DrinksInventory,
  Section,
  DrinksMenu,
  DrinksOrder, User_role
} = require("../../models");
const bcrypt = require("bcryptjs");
const logger = require("../../configs/logger");
const { Op, fn, col, literal } = require("sequelize"); // ✅ Include fn and literal
const PDFDocument = require("pdfkit");
const ExcelJS = require("exceljs");

async function getTopSellingFoodItemToday(req, res) {
  try {
    const startOfDay = new Date();
    startOfDay.setHours(0, 0, 0, 0);

    const endOfDay = new Date();
    endOfDay.setHours(23, 59, 59, 999);

    // Step 1: Get total quantity of all food items sold today
    const totalResult = await OrderItem.findOne({
      where: {
        food: true,
        createdAt: {
          [Op.between]: [startOfDay, endOfDay],
        },
      },
      attributes: [[fn("SUM", col("OrderItem.quantity")), "totalSold"]], // Explicitly reference OrderItem.quantity
    });

    const totalQuantitySold = parseInt(totalResult?.get("totalSold") || 0);

    if (totalQuantitySold === 0) {
      return res.status(200).json({ message: "No food items sold today." });
    }

    // Step 2: Get top 10 selling food items
    const topItems = await OrderItem.findAll({
      where: {
        food: true,
        createdAt: {
          [Op.between]: [startOfDay, endOfDay],
        },
      },
      attributes: [
        "menuId",
        [fn("SUM", col("OrderItem.quantity")), "totalSold"],
      ], // Explicitly reference OrderItem.quantity
      group: ["OrderItem.menuId", "menu.id", "menu.name"],
      order: [[col("totalSold"), "DESC"]],
      include: [
        {
          model: Menu,
          as: "menu",
          attributes: ["id", "name"],
        },
      ],
      limit: 10,
    });

    // Step 3: Add percentage for each item
    const formattedItems = topItems.map((item) => {
      const quantitySold = parseInt(item.get("totalSold"));
      const percentage = ((quantitySold / totalQuantitySold) * 100).toFixed(2);
      return {
        menuId: item.menuId,
        name: item.menu?.name || "Unknown",
        quantitySold,
        percentage: `${percentage}%`,
      };
    });

    res.status(200).json({
      message: "Top 10 Selling Food Items Today",
      totalFoodItemsSold: totalQuantitySold,
      items: formattedItems,
    });
  } catch (error) {
    console.error("Error fetching top selling items:", error);
    res.status(500).json({
      message: "Error fetching top selling items",
      error: error.message,
    });
  }
}

// No. of Orders and Avg Orders
async function getTodaysOrderStats(req, res) {
  try {
    const startOfDay = new Date();
    startOfDay.setHours(0, 0, 0, 0);

    const endOfDay = new Date();
    endOfDay.setHours(23, 59, 59, 999);

    // 1. Count unique orders today
    const orderCountResult = await OrderItem.findAll({
      where: {
        createdAt: {
          [Op.between]: [startOfDay, endOfDay],
        },
      },
      attributes: [[fn("DISTINCT", col("orderId")), "orderId"]],
      raw: true,
    });

    const orderIds = orderCountResult.map((o) => o.orderId);
    const numberOfOrders = orderIds.length;

    if (numberOfOrders === 0) {
      return res.status(200).json({
        message: "No orders placed today.",
        numberOfOrders: 0,
        averageOrderValue: 0,
      });
    }

    // 2. Calculate total order value today (from OrderItem assuming price * quantity)
    const totalRevenueResult = await OrderItem.findOne({
      where: {
        createdAt: {
          [Op.between]: [startOfDay, endOfDay],
        },
      },
      attributes: [[fn("SUM", literal("price * quantity")), "totalRevenue"]],
      raw: true,
    });

    const totalRevenue = parseFloat(totalRevenueResult.totalRevenue || 0);

    // 3. Average order value
    const averageOrderValue = totalRevenue / numberOfOrders;

    return res.status(200).json({
      message: "Today's Order Stats",
      numberOfOrders,
      averageOrderValue: averageOrderValue.toFixed(2),
    });
  } catch (error) {
    console.error("Error fetching today's order stats:", error);
    res.status(500).json({
      message: "Error fetching today's order stats",
      error: error.message,
    });
  }
}

//----------------------------------------------------
// Customer Count and Payment Type Percentages
// Customer Count and Payment Type Percentages
async function getTodaysCustomerStats(req, res) {
  try {
    const startOfDay = new Date();
    startOfDay.setHours(0, 0, 0, 0);

    const endOfDay = new Date();
    endOfDay.setHours(23, 59, 59, 999);

    // 1. Find unique customers (by phone number) who placed orders today
    const customerResult = await CustomerDetails.findAll({
      where: {
        createdAt: {
          [Op.between]: [startOfDay, endOfDay],
        },
      },
      attributes: [
        [fn("DISTINCT", col("customer_phoneNumber")), "customer_phoneNumber"],
      ],
      raw: true,
    });

    const numberOfCustomers = customerResult.length;

    if (numberOfCustomers === 0) {
      return res.status(200).json({
        message: "No customers today.",
        numberOfCustomers: 0,
        paymentTypePercentages: {
          cash: "0%",
          card: "0%",
          upi: "0%",
        },
      });
    }

    // 2. Count of each payment type
    const paymentCounts = await CustomerDetails.findAll({
      where: {
        createdAt: {
          [Op.between]: [startOfDay, endOfDay],
        },
      },
      attributes: [
        "payment_method",
        [fn("COUNT", col("payment_method")), "count"],
      ],
      group: ["payment_method"],
      raw: true,
    });

    const totalPayments = paymentCounts.reduce(
      (sum, p) => sum + parseInt(p.count, 10),
      0
    );
    const paymentTypePercentages = {};

    for (const payment of paymentCounts) {
      const type = payment.payment_method.toLowerCase();
      const percentage =
        ((payment.count / totalPayments) * 100).toFixed(2) + "%";
      paymentTypePercentages[type] = percentage;
    }

    // Ensure all keys exist
    ["cash", "card", "upi"].forEach((type) => {
      if (!paymentTypePercentages[type]) {
        paymentTypePercentages[type] = "0%";
      }
    });

    return res.status(200).json({
      message: "Today's Customer Stats",
      numberOfCustomers,
      paymentTypePercentages,
    });
  } catch (error) {
    console.error("Error fetching today's customer stats:", error);
    res.status(500).json({
      message: "Error fetching today's customer stats",
      error: error.message,
    });
  }
}

//ScoreBoard -- Daily
const getDailySalesScoreboard = async (req, res) => {
  try {
    // Today's date range
    const startOfDay = new Date();
    startOfDay.setHours(0, 0, 0, 0);

    const endOfDay = new Date();
    endOfDay.setHours(23, 59, 59, 999);

    // Query
    const results = await OrderItem.findAll({
      attributes: [
        "userId",
        [fn("SUM", literal("price * quantity")), "totalSales"],
        [fn("COUNT", col("OrderItem.id")), "totalOrders"],
        // Sum the commissionTotal for each user
        [fn("SUM", col("commissionTotal")), "commissionTotal"],
      ],
      where: {
        createdAt: {
          [Op.between]: [startOfDay, endOfDay],
        },
      },
      group: ["userId", "user.id"],
      include: [
        {
          model: User,
          as: "user",
          attributes: ["id", "name"],
        },
      ],
      order: [[col("totalSales"), "DESC"]],
    });

    // Format the result
    const scoreboard = results.map((entry, index) => ({
      rank: index + 1,
      userId: entry.userId,
      userName: entry.user?.name || "Unknown",
      totalSales: parseFloat(entry.get("totalSales")).toFixed(2),
      orders: parseInt(entry.get("totalOrders")),
      commissionTotal: parseFloat(entry.get("commissionTotal")).toFixed(2), // Display the commission
    }));

    return res.status(200).json({
      message: "Today's Sales Scoreboard",
      scoreboard,
    });
  } catch (error) {
    console.error("Error generating scoreboard:", error);
    return res
      .status(500)
      .json({ message: "Error generating scoreboard", error: error.message });
  }
};

const getSalesScoreboardByDate = async (req, res) => {
  try {
    // Get custom date range from query parameters
    const { startDate, endDate } = req.query;

    // Validate dates
    if (!startDate || !endDate) {
      return res
        .status(400)
        .json({ message: "startDate and endDate are required (YYYY-MM-DD)" });
    }

    const start = new Date(startDate);
    start.setHours(0, 0, 0, 0);

    const end = new Date(endDate);
    end.setHours(23, 59, 59, 999);

    // Query
    const results = await OrderItem.findAll({
      attributes: [
        "userId",
        [fn("SUM", literal("price * quantity")), "totalSales"],
        [fn("COUNT", col("OrderItem.id")), "totalOrders"],
        [fn("SUM", col("commissionTotal")), "commissionTotal"],
      ],
      where: {
        createdAt: {
          [Op.between]: [start, end],
        },
      },
      group: ["userId", "user.id"],
      include: [
        {
          model: User,
          as: "user",
          attributes: ["id", "name"],
        },
      ],
      order: [[col("totalSales"), "DESC"]],
    });

    // Format the result
    const scoreboard = results.map((entry, index) => ({
      rank: index + 1,
      userId: entry.userId,
      userName: entry.user?.name || "Unknown",
      totalSales: parseFloat(entry.get("totalSales")).toFixed(2),
      orders: parseInt(entry.get("totalOrders")),
      commissionTotal: parseFloat(entry.get("commissionTotal")).toFixed(2),
    }));

    return res.status(200).json({
      message: `Sales Scoreboard from ${startDate} to ${endDate}`,
      scoreboard,
    });
  } catch (error) {
    console.error("Error generating scoreboard:", error);
    return res
      .status(500)
      .json({ message: "Error generating scoreboard", error: error.message });
  }
};

//ScoreBoard -- Monthly
const getMonthlySalesScoreboard = async (req, res) => {
  try {
    // Get the start and end of the current month
    const now = new Date();
    const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
    const endOfMonth = new Date(
      now.getFullYear(),
      now.getMonth() + 1,
      0,
      23,
      59,
      59,
      999
    );

    const results = await OrderItem.findAll({
      attributes: [
        "userId",
        [fn("SUM", literal("price * quantity")), "totalSales"],
        [fn("COUNT", col("OrderItem.id")), "totalOrders"],
        // Sum the commissionTotal for each user
        [fn("SUM", col("commissionTotal")), "commissionTotal"],
      ],
      where: {
        createdAt: {
          [Op.between]: [startOfMonth, endOfMonth],
        },
      },
      group: ["userId", "user.id"],
      include: [
        {
          model: User,
          as: "user",
          attributes: ["id", "name"],
        },
      ],
      order: [[col("totalSales"), "DESC"]],
    });

    const scoreboard = results.map((entry, index) => ({
      rank: index + 1,
      userId: entry.userId,
      userName: entry.user?.name || "Unknown",
      totalSales: parseFloat(entry.get("totalSales")).toFixed(2),
      orders: parseInt(entry.get("totalOrders")),
      commissionTotal: parseFloat(entry.get("commissionTotal")).toFixed(2), // Display the commission
    }));

    return res.status(200).json({
      message: "This Month's Sales Scoreboard",
      scoreboard,
    });
  } catch (error) {
    console.error("Error generating monthly scoreboard:", error);
    return res
      .status(500)
      .json({ message: "Error generating scoreboard", error: error.message });
  }
};


//Get Todays Sales.


// Utility functions (reuse from getSections)
const getOrderMenuId = (o) => o.menuId ?? o.menu_id ?? (o.menu && o.menu.id);
const getDrinkId = (o) => o.drinkId ?? o.drink_id ?? (o.drink && o.drink.id);
const getQty = (o) => Number(o.quantity ?? o.qty ?? o.qty_no ?? 1);
const getAmount = (o) => Number(o.amount ?? 0);

const getTaxedAmount = (o, kind = "food") => {
  const qty = getQty(o);
  let basePrice = 0;

  if (kind === "food") {
    basePrice = o.amount != null ? Number(o.amount) : (o.menu?.price ?? 0) * qty;
    return basePrice * 1.05; // 5% GST
  }
  if (kind === "drink") {
    basePrice = o.amount != null ? Number(o.amount) : (o.drink?.price ?? 0) * qty;
    if (o.drink?.applyVAT) return basePrice * 1.1; // 10% VAT
    return basePrice * 1.05; // 5% GST
  }

  return o.amount != null ? Number(o.amount) : 0;
};

const aggregatePreserveShape = (arr, status, kind = "food") => {
  const filtered = arr.filter((o) => o.status === status);
  const map = {};

  filtered.forEach((o) => {
    const isCustom = o.is_custom === true;
    let key;
    if (isCustom) {
      key = `custom_${o.item_desc ?? o.note ?? "Custom"}_${o.kotNumber ?? o.kot_number ?? ""}`;
    } else {
      key = kind === "food" ? getOrderMenuId(o) : getDrinkId(o);
      if (key == null) return;
    }

    if (!map[key]) {
      map[key] = {
        id: o.id,
        menuId: kind === "food" && !isCustom ? o.menuId ?? o.menu_id ?? key : undefined,
        drinkId: kind === "drink" && !isCustom ? o.drinkId ?? o.drink_id ?? key : undefined,
        item_desc: o.note || o.item_desc || (kind === "food" ? "Custom Item" : "Custom Drink"),
        quantity: 0,
        amount: 0,        // taxed total
        actualAmount: 0,  // raw total (no tax)
        kotNumbers: [],
        createdAt: o.createdAt,
        updatedAt: o.updatedAt,
        menu: kind === "food" ? (isCustom ? { name: o.item_desc } : o.menu) : undefined,
        drink: kind === "drink" ? (isCustom ? { name: o.item_desc } : o.drink) : undefined,
        mergedOrderIds: [],
      };
    }

    const entry = map[key];
    const qty = getQty(o);
    const taxedAmt = getTaxedAmount(o, kind);
    const actualAmt = o.amount != null ? Number(o.amount) : (kind === "food" ? o.menu?.price ?? 0 : o.drink?.price ?? 0) * qty;

    entry.quantity += qty;
    entry.amount += taxedAmt;
    entry.actualAmount += actualAmt;

    if (o.id != null) entry.mergedOrderIds.push(o.id);
    const kn = o.kotNumber ?? o.kot_number ?? null;
    if (kn != null) entry.kotNumbers.push(kn);
  });

  const aggregated = Object.values(map).map((it) => {
    it.kotNumbers = Array.from(new Set(it.kotNumbers));
    it.amount = Math.round(it.amount);
    it.actualAmount = Math.round(it.actualAmount);
    return it;
  });

  const totalAmount = Math.round(aggregated.reduce((s, it) => s + (it.amount || 0), 0));

  return { aggregated, totalAmount, rawFiltered: filtered };
};



const getTodaysSales = async (req, res) => {
  try {
    const IST_OFFSET = 5.5 * 60;
    const toIST = (utcDate) => new Date(utcDate.getTime() + IST_OFFSET * 60 * 1000);

    const now = toIST(new Date());
    const startOfSalesDay = new Date(now);
    startOfSalesDay.setHours(3, 10, 0, 0);

    if (now.getHours() < 3 || (now.getHours() === 3 && now.getMinutes() < 10)) {
      startOfSalesDay.setDate(startOfSalesDay.getDate() - 1);
    }

    const endOfSalesDay = new Date(startOfSalesDay);
    endOfSalesDay.setDate(endOfSalesDay.getDate() + 1);
    endOfSalesDay.setHours(3, 9, 59, 999);

    const startUTC = new Date(startOfSalesDay.getTime() - IST_OFFSET * 60 * 1000);
    const endUTC = new Date(endOfSalesDay.getTime() - IST_OFFSET * 60 * 1000);

    // 1️⃣ Fetch sections with tables
    const sections = await Section.findAll({
      include: [
        {
          model: Table,
          as: "tables",
          separate: true,
          order: [["createdAt", "ASC"]],
        },
      ],
    });

    // 2️⃣ Fetch all orders & drinksOrders today
    const [orders, drinksOrders, bills] = await Promise.all([
      Order.findAll({
        where: { createdAt: { [Op.between]: [startUTC, endUTC] } },
        include: [{ model: Menu, as: "menu", attributes: ["id", "name", "price"] }],
      }),
      DrinksOrder.findAll({
        where: { createdAt: { [Op.between]: [startUTC, endUTC] } },
        include: [{ model: DrinksMenu, as: "drink", attributes: ["id", "name", "price", "applyVAT"] }],
      }),
      Bill.findAll({
        where: { createdAt: { [Op.between]: [startUTC, endUTC] }, isComplimentary: false },
      }),
    ]);

    // 3️⃣ Aggregate orders by table_number
    const orderMap = orders.reduce((acc, order) => {
      (acc[order.table_number] = acc[order.table_number] || []).push(order);
      return acc;
    }, {});
    const drinksOrderMap = drinksOrders.reduce((acc, order) => {
      (acc[order.table_number] = acc[order.table_number] || []).push(order);
      return acc;
    }, {});

    // 4️⃣ Enrich sections with aggregated orders and amounts
    const enrichedSections = sections.map((section) => {
      const enrichedTables = section.tables.map((table) => {
        const tableOrders = orderMap[table.id] || [];
        const tableDrinks = drinksOrderMap[table.id] || [];

        const { aggregated: pendingOrders, totalAmount: pendingAmount } = aggregatePreserveShape(tableOrders, "pending", "food");
        const { aggregated: ongoingOrders, totalAmount: ongoingAmount } = aggregatePreserveShape(tableOrders, "accepted", "food");
        const { aggregated: completeOrders, totalAmount: completeAmount } = aggregatePreserveShape(tableOrders, "completed", "food");

        const { aggregated: pendingDrinksOrders, totalAmount: pendingDrinksAmount } = aggregatePreserveShape(tableDrinks, "pending", "drink");
        const { aggregated: ongoingDrinksOrders, totalAmount: ongoingDrinksAmount } = aggregatePreserveShape(tableDrinks, "accepted", "drink");
        const { aggregated: completeDrinksOrders, totalAmount: completeDrinksAmount } = aggregatePreserveShape(tableDrinks, "completed", "drink");

        const tableTotalAmount = pendingAmount + ongoingAmount + completeAmount + pendingDrinksAmount + ongoingDrinksAmount + completeDrinksAmount;

        return {
          ...table.toJSON(),
          orders: { pendingOrders, ongoingOrders, completeOrders },
          drinksOrders: { pendingDrinksOrders, ongoingDrinksOrders, completeDrinksOrders },
          orderAmounts: {
            pendingAmount, ongoingAmount, completeAmount,
            pendingDrinksAmount, ongoingDrinksAmount, completeDrinksAmount,
            totalAmount: tableTotalAmount,
          },
        };
      });

      const sectionTotalAmount = enrichedTables.reduce((sum, t) => sum + (t.orderAmounts?.totalAmount || 0), 0);

      return { ...section.toJSON(), tables: enrichedTables, sectionTotalAmount };
    });

    // 5️⃣ Calculate total and estimated sales
    const totalSales = bills.reduce((sum, bill) => sum + bill.final_amount, 0);
    const estimatedSales = enrichedSections.reduce((sum, s) => sum + (s.sectionTotalAmount || 0), 0);

    res.status(200).json({ totalSales, estimatedSales, sections: enrichedSections });
  } catch (error) {
    console.error("Error fetching today's sales:", error);
    res.status(500).json({ message: "Error fetching today's sales", error: error.message });
  }
};


//Sales for last 7 days
const getSalesOverview = async (req, res) => {
  try {
    const { option = "today", startDate, endDate } = req.query;

    const IST_OFFSET = 5.5 * 60; // minutes
    const toIST = (utcDate) => new Date(utcDate.getTime() + IST_OFFSET * 60 * 1000);

    const now = toIST(new Date());
    const START_HOUR = 3;
    const START_MINUTE = 10;
    const END_MINUTE = 9;

    let start, end;

    switch (option) {
      case "today":
        start = new Date(now);
        start.setHours(START_HOUR, START_MINUTE, 0, 0);
        if (now < start) start.setDate(start.getDate() - 1);
        end = new Date(start);
        end.setDate(end.getDate() + 1);
        end.setHours(START_HOUR, END_MINUTE, 59, 999);
        break;

      case "yesterday":
        start = new Date(now);
        start.setHours(START_HOUR, START_MINUTE, 0, 0);
        start.setDate(start.getDate() - 1);
        end = new Date(start);
        end.setDate(end.getDate() + 1);
        end.setHours(START_HOUR, END_MINUTE, 59, 999);
        break;

      case "last7days":
        end = new Date(now);
        end.setHours(START_HOUR, END_MINUTE, 59, 999);
        start = new Date(end);
        start.setDate(start.getDate() - 6);
        start.setHours(START_HOUR, START_MINUTE, 0, 0);
        break;

      case "last30days":
        end = new Date(now);
        end.setHours(START_HOUR, END_MINUTE, 59, 999);
        start = new Date(end);
        start.setDate(start.getDate() - 29);
        start.setHours(START_HOUR, START_MINUTE, 0, 0);
        break;

      case "thisMonth":
        start = new Date(now.getFullYear(), now.getMonth(), 1, START_HOUR, START_MINUTE, 0, 0);
        end = new Date(now);
        break;

      case "lastMonth":
        const lastMonthDate = new Date(now.getFullYear(), now.getMonth() - 1, 1);
        start = new Date(lastMonthDate.getFullYear(), lastMonthDate.getMonth(), 1, START_HOUR, START_MINUTE, 0, 0);
        end = new Date(lastMonthDate.getFullYear(), lastMonthDate.getMonth() + 1, 0, START_HOUR, END_MINUTE, 59, 999);
        break;

      case "custom":
        if (!startDate || !endDate)
          return res.status(400).json({ message: "Provide startDate and endDate for custom range (YYYY-MM-DD)." });
        start = new Date(startDate);
        start.setHours(START_HOUR, START_MINUTE, 0, 0);
        end = new Date(endDate);
        end.setHours(START_HOUR, END_MINUTE, 59, 999);
        break;

      default:
        start = new Date(now);
        start.setHours(START_HOUR, START_MINUTE, 0, 0);
        if (now < start) start.setDate(start.getDate() - 1);
        end = new Date(start);
        end.setDate(end.getDate() + 1);
        end.setHours(START_HOUR, END_MINUTE, 59, 999);
    }

    if (!start || !end) return res.status(500).json({ message: "Start or end date is invalid." });

    const startUTC = new Date(start.getTime() - IST_OFFSET * 60 * 1000);
    const endUTC = new Date(end.getTime() - IST_OFFSET * 60 * 1000);

    const bills = await Bill.findAll({
      where: { createdAt: { [Op.between]: [startUTC, endUTC] } },
    });

    const totalSales = bills.reduce((acc, bill) => acc + bill.final_amount, 0);
    const totalBills = bills.length;

    // Total payment breakdown
    const totalCash = bills.reduce((acc, bill) => acc + (bill.payment_breakdown?.cash || 0), 0);
    const totalCard = bills.reduce((acc, bill) => acc + (bill.payment_breakdown?.card || 0), 0);
    const totalUPI = bills.reduce((acc, bill) => acc + (bill.payment_breakdown?.upi || 0), 0);
    const totalTip = bills.reduce((acc, bill) => acc + (bill.tip_amount || 0), 0);

    // Total tax
    const totalGST = bills.reduce((acc, bill) => acc + (bill.tax_amount || 0), 0);
    const totalVAT = bills.reduce((acc, bill) => acc + (bill.vat_amount || 0), 0);
    const totalTax = totalGST + totalVAT;

    // Total discount
    const totalDiscount = bills.reduce(
      (acc, bill) =>
        acc +
        (bill.discount_amount || 0) +
        (bill.food_discount_flat_amount || 0) +
        (bill.drink_discount_flat_amount || 0),
      0
    );

    // NEW: total complimentary amount (sums final_amount where isComplimentary === true)
    const totalComplimentaryAmount = bills.reduce(
      (acc, bill) => acc + (bill.isComplimentary ? bill.final_amount : 0),
      0
    );

    // Daily breakdown (3-hour slots for today/yesterday, else daily totals)
    let dailyBreakdown = [];

    if (option === "today" || option === "yesterday") {
      let currentSlotStart = new Date(start);

      const formatHour = (h) => {
        if (h === 0 || h === 24) return "12AM";
        if (h === 12) return "12PM";
        if (h > 12) return `${h - 12}PM`;
        return `${h}AM`;
      };

      for (let i = 0; i < 8; i++) {
        const currentSlotEnd = new Date(currentSlotStart);
        currentSlotEnd.setHours(currentSlotStart.getHours() + 3);

        const slotStartUTC = new Date(currentSlotStart.getTime() - IST_OFFSET * 60 * 1000);
        const slotEndUTC = new Date(currentSlotEnd.getTime() - IST_OFFSET * 60 * 1000);

        const slotBills = bills.filter((b) => {
          const billTime = new Date(b.createdAt);
          return billTime >= slotStartUTC && billTime < slotEndUTC;
        });

        const label = `${formatHour(currentSlotStart.getHours())}-${formatHour(currentSlotEnd.getHours() === 0 ? 24 : currentSlotEnd.getHours())}`;

        dailyBreakdown.push({
          date: currentSlotStart.toISOString().split("T")[0],
          timeSlot: label,
          total: slotBills.reduce((acc, bill) => acc + bill.final_amount, 0),
          totalBills: slotBills.length,
          cash: slotBills.reduce((acc, b) => acc + (b.payment_breakdown?.cash || 0), 0),
          card: slotBills.reduce((acc, b) => acc + (b.payment_breakdown?.card || 0), 0),
          upi: slotBills.reduce((acc, b) => acc + (b.payment_breakdown?.upi || 0), 0),
          tip: slotBills.reduce((acc, b) => acc + (b.tip_amount || 0), 0),
          CGST: slotBills.reduce((acc, b) => acc + (b.tax_amount || 0), 0),
          SGST: slotBills.reduce((acc, b) => acc + (b.vat_amount || 0), 0),
          totalTax: slotBills.reduce((acc, b) => acc + (b.tax_amount || 0) + (b.vat_amount || 0), 0),
          totalDiscount: slotBills.reduce(
            (acc, b) =>
              acc + (b.discount_amount || 0) + (b.food_discount_flat_amount || 0) + (b.drink_discount_flat_amount || 0),
            0
          ),
          // NEW: complimentary amount for this slot
          complimentary: slotBills.reduce((acc, b) => acc + (b.isComplimentary ? b.final_amount : 0), 0),
        });

        currentSlotStart = currentSlotEnd;
      }
    } else {
      let currentDay = new Date(start);
      const daysDiff = Math.ceil((end - start) / (24 * 60 * 60 * 1000));

      for (let i = 0; i < daysDiff; i++) {
        const dayEnd = new Date(currentDay);
        dayEnd.setDate(currentDay.getDate() + 1);
        dayEnd.setHours(START_HOUR, END_MINUTE, 59, 999);
        const dayEndUTC = new Date(dayEnd.getTime() - IST_OFFSET * 60 * 1000);
        const dayStartUTC = new Date(currentDay.getTime() - IST_OFFSET * 60 * 1000);

        const dailyBills = bills.filter((b) => {
          const billTime = new Date(b.createdAt);
          return billTime >= dayStartUTC && billTime < dayEndUTC;
        });

        dailyBreakdown.push({
          date: currentDay.toISOString().split("T")[0],
          total: dailyBills.reduce((acc, bill) => acc + bill.final_amount, 0),
          totalBills: dailyBills.length,
          cash: dailyBills.reduce((acc, b) => acc + (b.payment_breakdown?.cash || 0), 0),
          card: dailyBills.reduce((acc, b) => acc + (b.payment_breakdown?.card || 0), 0),
          upi: dailyBills.reduce((acc, b) => acc + (b.payment_breakdown?.upi || 0), 0),
          tip: dailyBills.reduce((acc, b) => acc + (b.tip_amount || 0), 0),
          CGST: dailyBills.reduce((acc, b) => acc + (b.tax_amount || 0), 0),
          SGST: dailyBills.reduce((acc, b) => acc + (b.vat_amount || 0), 0),
          totalTax: dailyBills.reduce((acc, b) => acc + (b.tax_amount || 0) + (b.vat_amount || 0), 0),
          totalDiscount: dailyBills.reduce(
            (acc, b) =>
              acc + (b.discount_amount || 0) + (b.food_discount_flat_amount || 0) + (b.drink_discount_flat_amount || 0),
            0
          ),
          // NEW: complimentary amount for this day
          complimentary: dailyBills.reduce((acc, b) => acc + (b.isComplimentary ? b.final_amount : 0), 0),
        });

        currentDay.setDate(currentDay.getDate() + 1);
        currentDay.setHours(START_HOUR, START_MINUTE, 0, 0);
      }
    }

    res.status(200).json({
      totalSales,
      totalBills,
      totalCash,
      totalCard,
      totalUPI,
      totalTip,
      totalGST,
      totalVAT,
      totalTax,
      totalDiscount,
      // NEW top-level complimentary total
      totalComplimentaryAmount,
      dailyBreakdown,
    });
  } catch (error) {
    console.error("Error fetching sales overview:", error);
    res.status(500).json({
      message: "Error fetching sales overview",
      error: error.message,
    });
  }
};


const getTodaysHourlySales = async (req, res) => {
  try {
    const startOfToday = new Date();
    startOfToday.setHours(0, 0, 0, 0);

    const endOfToday = new Date();
    endOfToday.setHours(23, 59, 59, 999);

    const hourlySales = await Bill.findAll({
      attributes: [
        [literal(`DATE_TRUNC('hour', "createdAt")`), "hour"],
        [fn("SUM", col("final_amount")), "total"],
      ],
      where: {
        createdAt: {
          [Op.between]: [startOfToday, endOfToday],
        },
      },
      group: [literal(`DATE_TRUNC('hour', "createdAt")`)],
      order: [[literal(`hour`), "ASC"]],
    });

    res.status(200).json({ hourlySales });
  } catch (error) {
    console.error("Error fetching hourly sales:", error);
    res
      .status(500)
      .json({ message: "Error fetching hourly sales", error: error.message });
  }
};

//Get Tables details
const getTables = async (req, res) => {
  try {
    const allTables = await Table.findAll();
    const total = allTables.length;
    const free = allTables.filter((t) => t.status === "free").length;
    const occupied = allTables.filter((t) => t.status === "occupied").length;
    const reserved = allTables.filter((t) => t.status === "reserved").length;

    // Compute avg occupied time from tables with seatingTime
    const now = new Date();
    const occupiedWithTime = allTables.filter(
      (t) => t.status === "occupied" && t.seatingTime
    );
    let avgOccupiedMinutes = 0;
    if (occupiedWithTime.length > 0) {
      const totalMinutes = occupiedWithTime.reduce((sum, t) => {
        return sum + (now - new Date(t.seatingTime)) / 60000;
      }, 0);
      avgOccupiedMinutes = Math.round(totalMinutes / occupiedWithTime.length);
    }

    res.status(200).json({ total, free, reserved, occupied, avgOccupiedMinutes });
  } catch (error) {
    console.error("Error in fetching Tables:", error);
    res
      .status(500)
      .json({ message: "Error fetching tables", error: error.message });
  }
};


//Orders Count
const getOrders = async (req, res) => {
  try {
    const [pendingCount, acceptedCount] = await Promise.all([
      Order.count({ where: { status: "pending" } }),
      Order.count({ where: { status: "accepted" } }),
    ]);

    res.status(200).json({
      pending: pendingCount,
      accepted: acceptedCount,
      total: pendingCount + acceptedCount,
    });
  } catch (error) {
    console.error("Error fetching order counts:", error);
    res
      .status(500)
      .json({ message: "Error fetching order counts", error: error.message });
  }
};

const lowStock = async (req, res) => {
  try {
    const inventory = await Inventory.findAll();
    console.log("Inventory fetched:", inventory.length, inventory);

    let low = 0;
    let out = 0;
    const outOfStockItems = [];

    for (const item of inventory) {
      console.log(
        `Checking item: id=${item.id}, quantity=${item.quantity}, minimum_quantity=${item.minimum_quantity}`
      );
      if (item.quantity === 0) {
        out++;
        outOfStockItems.push(item);
        console.log("Item is out of stock");
      } else if (item.quantity <= item.minimum_quantity) {
        // changed here
        low++;
        console.log("Item is low stock");
      }
    }

    const drinksInventory = await DrinksInventory.findAll();
    // console.log(
    //   "DrinksInventory fetched:",
    //   drinksInventory.length,
    //   drinksInventory
    // );

    let drinkslow = 0;
    let drinksout = 0;
    const drinksOutOfStockItems = [];

    for (const drinksItem of drinksInventory) {
      // console.log(
      //   `Checking drinksItem: id=${drinksItem.id}, quantity=${drinksItem.quantity}, minimumQuantity=${drinksItem.minimumQuantity}`
      // );
      if (drinksItem.quantity === 0) {
        drinksout++;
        drinksOutOfStockItems.push(drinksItem);
        // console.log("Drinks item is out of stock");
      } else if (drinksItem.quantity <= drinksItem.minimumQuantity) {
        // and here
        drinkslow++;
        // console.log("Drinks item is low stock");
      }
    }
    // console.log(`Low stock count: ${low}, Out of stock count: ${out}`);
    // console.log(
    //   `Drinks low stock count: ${drinkslow}, Drinks out of stock count: ${drinksout}`
    // );

    res.status(200).json({
      lowStockCount: low,
      outOfStockCount: out,
      totalAffected: low + out,
      outOfStockItems,
      lowStockItems: inventory.filter(
        (item) => item.quantity <= item.minimum_quantity && item.quantity > 0
      ),

      drinkslowStockCount: drinkslow,
      drinksoutOfStockCount: drinksout,
      drinkstotalAffected: drinkslow + drinksout,
      drinksOutOfStockItems,
      drinkslowStockItems: drinksInventory.filter(
        (item) => item.quantity <= item.minimumQuantity && item.quantity > 0
      ),
    });
  } catch (error) {
    console.error("Error fetching inventory:", error);
    res
      .status(500)
      .json({ message: "Error fetching inventory", error: error.message });
  }
};



// 👉 Get all users, ordered by id ascending

const getAllUsers = async (req, res) => {
  try {
    const users = await User.findAll({
      attributes: { exclude: ["password"] },
      include: [
        {
          model: User_role,
          as: "role",        // must match alias in User model
          attributes: ["name"],
        },
      ],
      order: [["id", "ASC"]],
    });

    res.status(200).json(users);
  } catch (error) {
    console.error("Error fetching users:", error);
    res.status(500).json({
      message: "Error fetching users",
      error: error.message,
    });
  }
};


// 👉 Create new user
const createUser = async (req, res) => {
  try {
    const { name, email, password, role } = req.body;

    // Check if email already exists
    const existingUser = await User.findOne({ where: { email } });
    if (existingUser) {
      return res.status(400).json({ message: "Email already exists" });
    }

    // Hash password
    const hashedPassword = await bcrypt.hash(password, 10);

    // Create user
    const newUser = await User.create({
      name,
      email,
      password: hashedPassword,
      role: role || "user",
    });

    res
      .status(201)
      .json({ message: "User created successfully", user: newUser });
  } catch (error) {
    console.error("Error creating user:", error);
    logger.error("Error creating user:", error);
    res
      .status(500)
      .json({ message: "Error creating user", error: error.message });
  }
};

// 👉 Update user by ID
const updateUser = async (req, res) => {
  try {
    const { id } = req.params;

    const {
      name,
      email,
      roleId,
      phone_number,
      address,
      salary,
      isActive,
      isVerified
    } = req.body;

    const user = await User.findByPk(id);

    if (!user) {
      return res.status(404).json({ message: "User not found" });
    }

    let parsedRoleId = roleId !== undefined ? parseInt(roleId, 10) : user.roleId;

    const updatedUser = await user.update({
      name: name || user.name,
      email: email || user.email,
      roleId: isNaN(parsedRoleId) ? user.roleId : parsedRoleId,
      phone_number: phone_number || user.phone_number,
      address: address || user.address,
      salary: salary || user.salary,

      // boolean fields
      isActive: isActive !== undefined ? isActive : user.isActive,
      isVerified: isVerified !== undefined ? isVerified : user.isVerified,
    });

    res.status(200).json({
      message: "User updated successfully",
      updatedUser
    });

  } catch (error) {
    console.error("Error updating user:", error);
    logger.error("Error updating user:", error);

    res.status(500).json({
      message: "Error updating user",
      error: error.message
    });
  }
};


// 👉 Delete user by ID
const deleteUser = async (req, res) => {
  try {
    const { id } = req.params;

    const user = await User.findByPk(id);
    if (!user) {
      return res.status(404).json({ message: "User not found" });
    }

    await user.destroy();
    res.status(200).json({ message: "User deleted successfully" });
  } catch (error) {
    console.error("Error deleting user:", error);
    logger.error("Error deleting user:", error);
    res
      .status(500)
      .json({ message: "Error deleting user", error: error.message });
  }
};

const aadharCard = async (req, res) => {
  const userId = req.params.id;

  if (!userId) {
    return res.status(400).json({ error: "User ID is required in the URL." });
  }

  if (!req.file) {
    return res.status(400).json({ error: "No PDF file uploaded." });
  }

  try {
    const user = await User.findByPk(userId);

    if (!user) {
      return res.status(404).json({ error: "User not found." });
    }

    // Save the relative path to the appointment letter
    const relativePath = `/uploads/aadharCard/${req.file.filename}`;
    user.aadhar_card_path = relativePath;
    await user.save();

    return res.status(200).json({
      message: "Aadhar Card uploaded successfully.",
      aadhar_card_path: relativePath,
    });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: "Failed to upload Aadhar Card." });
  }
};

const panCard = async (req, res) => {
  const userId = req.params.id;

  if (!userId) {
    return res.status(400).json({ error: "User ID is required in the URL." });
  }

  if (!req.file) {
    return res.status(400).json({ error: "No PDF file uploaded." });
  }

  try {
    const user = await User.findByPk(userId);

    if (!user) {
      return res.status(404).json({ error: "User not found." });
    }

    // Save the relative path to the appointment letter
    const relativePath = `/uploads/panCard/${req.file.filename}`;
    user.pan_card_path = relativePath;
    await user.save();

    return res.status(200).json({
      message: "Pan card uploaded successfully.",
      pan_card_path: relativePath,
    });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: "Failed to upload Pan card." });
  }
};

// =========================
// 🎯 INVENTORY MANAGEMENT
// =========================

// 👉 Get all inventory items
const getInventory = async (req, res) => {
  try {
    const inventoryItems = await Inventory.findAll();
    res.status(200).json(inventoryItems);
  } catch (error) {
    console.error("Error fetching inventory:", error);
    logger.error("Error fetching inventory:", error);
    res
      .status(500)
      .json({ message: "Error fetching inventory", error: error.message });
  }
};

// 👉 Add new inventory item
const addInventory = async (req, res) => {
  try {
    const { itemName, quantity, unit } = req.body;

    // Check if item already exists
    const existingItem = await Inventory.findOne({ where: { itemName } });
    if (existingItem) {
      return res
        .status(400)
        .json({ message: "Item already exists in inventory" });
    }

    const inventoryItem = await Inventory.create({ itemName, quantity, unit });
    res
      .status(201)
      .json({ message: "Inventory item added successfully", inventoryItem });
  } catch (error) {
    console.error("Error adding inventory:", error);
    logger.error("Error adding inventory:", error);
    res
      .status(500)
      .json({ message: "Error adding inventory", error: error.message });
  }
};

// 👉 Update inventory item by ID
const updateInventory = async (req, res) => {
  try {
    const { id } = req.params;
    const { itemName, quantity, unit } = req.body;

    const inventoryItem = await Inventory.findByPk(id);
    if (!inventoryItem) {
      return res.status(404).json({ message: "Inventory item not found" });
    }

    await inventoryItem.update({
      itemName: itemName || inventoryItem.itemName,
      quantity: quantity !== undefined ? quantity : inventoryItem.quantity,
      unit: unit || inventoryItem.unit,
    });

    res
      .status(200)
      .json({ message: "Inventory item updated successfully", inventoryItem });
  } catch (error) {
    console.error("Error updating inventory:", error);
    logger.error("Error updating inventory:", error);
    res
      .status(500)
      .json({ message: "Error updating inventory", error: error.message });
  }
};

// 👉 Delete inventory item by ID
const deleteInventory = async (req, res) => {
  try {
    const { id } = req.params;

    const inventoryItem = await Inventory.findByPk(id);
    if (!inventoryItem) {
      return res.status(404).json({ message: "Inventory item not found" });
    }

    await inventoryItem.destroy();
    res.status(200).json({ message: "Inventory item deleted successfully" });
  } catch (error) {
    console.error("Error deleting inventory:", error);
    logger.error("Error deleting inventory:", error);
    res
      .status(500)
      .json({ message: "Error deleting inventory", error: error.message });
  }
};

// =========================
// 🎯 ORDER MANAGEMENT
// =========================

// 👉 Get all orders
const getAllOrders = async (req, res) => {
  try {
    const orders = await Order.findAll({
      include: [
        {
          model: Menu,
          as: "menu",
          attributes: ["name", "price"],
        },
      ],
    });
    res.status(200).json(orders);
  } catch (error) {
    console.error("Error fetching orders:", error);
    logger.error("Error fetching orders:", error);
    res
      .status(500)
      .json({ message: "Error fetching orders", error: error.message });
  }
};

// 👉 Update order status
const updateOrderStatus = async (req, res) => {
  try {
    const { id } = req.params;
    const { status } = req.body;

    const order = await Order.findByPk(id);
    if (!order) {
      return res.status(404).json({ message: "Order not found" });
    }

    // ✅ Check valid status
    const validStatuses = [
      "pending",
      "accepted",
      "preparing",
      "completed",
      "cancelled",
    ];
    if (!validStatuses.includes(status)) {
      return res.status(400).json({ message: "Invalid order status" });
    }

    await order.update({ status });
    res
      .status(200)
      .json({ message: "Order status updated successfully", order });
  } catch (error) {
    console.error("Error updating order status:", error);
    logger.error("Error updating order status:", error);
    res
      .status(500)
      .json({ message: "Error updating order status", error: error.message });
  }
};

// 👉 Delete order by ID
const deleteOrder = async (req, res) => {
  try {
    const { id } = req.params;

    const order = await Order.findByPk(id);
    if (!order) {
      return res.status(404).json({ message: "Order not found" });
    }

    await order.destroy();
    res.status(200).json({ message: "Order deleted successfully" });
  } catch (error) {
    console.error("Error deleting order:", error);
    logger.error("Error deleting order:", error);
    res
      .status(500)
      .json({ message: "Error deleting order", error: error.message });
  }
};

const getDayEndSummary = async (req, res) => {
  try {
    const summaries = await DaySummary.findAll({
      order: [["date", "DESC"]],
      raw: true,
    });

    const enrichedSummaries = await Promise.all(
      summaries.map(async (summary) => {
        // Get the date from summary
        const dayStart = new Date(summary.date);
        dayStart.setHours(0, 0, 0, 0);

        const dayEnd = new Date(summary.date);
        dayEnd.setHours(23, 59, 59, 999);

        // Fetch invoice data for that day
        const invoiceData = await Bill.findAll({
          where: {
            createdAt: { [Op.between]: [dayStart, dayEnd] },
          },
          attributes: [
            [fn("COUNT", col("id")), "totalBills"],
            [fn("MIN", col("id")), "firstBillId"],
            [fn("MAX", col("id")), "lastBillId"],
          ],
          raw: true,
        });
        // console.log(invoiceData);
        const { totalBills, firstBillId, lastBillId } = invoiceData[0] || {
          totalBills: 0,
          firstBillId: null,
          lastBillId: null,
        };

        return {
          ...summary,
          invoiceNo: `${firstBillId}-${lastBillId}`,
        };
      })
    );
    console.log(enrichedSummaries);
    res.status(200).json({
      message: "Day-End Summary History",
      data: enrichedSummaries,
    });
  } catch (error) {
    console.error("Error fetching day-end summary history:", error);
    res.status(500).json({ error: "Internal Server Error" });
  }
};

const downloadDayEndSummary = async (req, res) => {
  const { date } = req.params; // Get the date from URL parameters

  if (!date) {
    return res.status(400).json({ message: "Date parameter is required" });
  }

  try {
    // Fetch the summary from the database where the date matches the provided date
    const summary = await DaySummary.findOne({
      where: {
        date: date, // Filter by the provided date
      },
    });

    console.log(summary); // Log the result to check what was fetched

    if (!summary) {
      return res
        .status(404)
        .json({ message: "Day Summary not found for the given date" });
    }

    // Create a new Excel workbook and worksheet
    const workbook = new ExcelJS.Workbook();
    const worksheet = workbook.addWorksheet("Day-End-Summary");

    // Define columns based on the structure of the response data
    worksheet.columns = [
      { header: "ID", key: "id", width: 10 },
      { header: "Date", key: "date", width: 15 },
      { header: "Order Count", key: "orderCount", width: 15 },
      { header: "Sub Total", key: "subTotal", width: 15 },
      { header: "Discount", key: "discount", width: 15 },
      { header: "Service Charges", key: "serviceCharges", width: 20 },
      { header: "Tax", key: "tax", width: 15 },
      { header: "Round Off", key: "roundOff", width: 15 },
      { header: "Grand Total", key: "grandTotal", width: 15 },
      {
        header: "Grand Total Percent Type",
        key: "grandTotalPercentType",
        width: 25,
      },
      { header: "Grand Total Percent", key: "grandTotalPercent", width: 20 },
      { header: "Net Sales", key: "netSales", width: 15 },
      { header: "Cash", key: "cash", width: 15 },
      { header: "Card", key: "card", width: 15 },
      { header: "UPI", key: "upi", width: 15 },
      { header: "Created At", key: "createdAt", width: 25 },
      { header: "Updated At", key: "updatedAt", width: 25 },
    ];

    // Add the data row to the worksheet
    const dataRow = {
      id: summary.id,
      date: summary.date,
      orderCount: summary.orderCount,
      subTotal: summary.subTotal,
      discount: summary.discount,
      serviceCharges: summary.serviceCharges,
      tax: summary.tax,
      roundOff: summary.roundOff,
      grandTotal: summary.grandTotal,
      grandTotalPercentType: summary.grandTotalPercentType,
      grandTotalPercent: summary.grandTotalPercent,
      netSales: summary.netSales,
      cash: summary.cash,
      card: summary.card,
      upi: summary.upi,
      createdAt: summary.createdAt,
      updatedAt: summary.updatedAt,
    };

    worksheet.addRow(dataRow);

    // Set headers for downloading the file as an Excel file
    res.setHeader(
      "Content-Type",
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    );
    res.setHeader(
      "Content-Disposition",
      "attachment; filename=DayEndSummary.xlsx"
    );

    // Write the Excel file to the response
    await workbook.xlsx.write(res);
    res.status(200).end();
  } catch (error) {
    console.error("Error downloading day end summary:", error);
    res.status(500).json({
      message: "Error downloading day end summary",
      error: error.message,
    });
  }
};

module.exports = {
  getDayEndSummary,
  getTodaysOrderStats,
  getTodaysCustomerStats,
  downloadDayEndSummary,

  //Sales Management
  getTodaysSales,
  getSalesOverview,

  getTodaysHourlySales,

  //Tables
  getTables,

  //orders
  getOrders,

  //lowStock
  lowStock,

  // ✅ User Management
  getAllUsers,
  createUser,
  updateUser,
  deleteUser,
  aadharCard,
  panCard,

  // ✅ Inventory Management
  getInventory,
  addInventory,
  updateInventory,
  deleteInventory,

  // ✅ Order Management
  getAllOrders,
  updateOrderStatus,
  deleteOrder,

  //Score Board
  getDailySalesScoreboard,
  getSalesScoreboardByDate,
  getMonthlySalesScoreboard,

  //top selling item
  getTopSellingFoodItemToday,
};
