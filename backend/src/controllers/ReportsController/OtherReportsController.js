// controllers/itemReportController.js
const {
  sequelize,
  OrderItem,
  Menu,
  DrinksMenu,
  Category,
  DrinksCategory,
  DaySummary,
  Bill,
  Table,
  Section,
  User,
  Inventory,
  DrinksInventory,
  CanceledFoodOrder, CanceledDrinkOrder 
} = require("../../models");

const { Op, fn, col } = require("sequelize");
const { Parser } = require("json2csv");
const ExcelJS = require("exceljs");
const PDFDocument = require("pdfkit");
const moment = require("moment-timezone");
const TZ = "Asia/Kolkata";
const DATE_ONLY_RE = /^\d{4}-\d{2}-\d{2}$/; // matches "2025-09-29"


const toNumber = (v) => {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
};

// robust truthy check for flags that may be boolean, string, or number
const isTruthy = (v) => v === true || v === "true" || v === 1 || v === "1";

function buildWindowFromQuery({ startDate, endDate }) {
  let startMoment, endMoment;

  if (startDate) {
    if (DATE_ONLY_RE.test(startDate)) {
      // date-only -> that date at 03:30 IST
      startMoment = moment.tz(startDate, TZ).hour(3).minute(30).second(0).millisecond(0);
    } else {
      // datetime or ISO -> parse in IST timezone
      startMoment = moment.tz(startDate, TZ);
      if (!startMoment.isValid()) startMoment = moment().tz(TZ).hour(3).minute(30).second(0).millisecond(0);
    }
  } else {
    // default: today at 03:30 IST
    startMoment = moment().tz(TZ).hour(3).minute(30).second(0).millisecond(0);
  }

  if (endDate) {
    if (DATE_ONLY_RE.test(endDate)) {
      // date-only end -> that date at 03:30 IST then +24h (so it's a full 24h window for that date)
      endMoment = moment.tz(endDate, TZ).hour(3).minute(30).second(0).millisecond(0).add(24, "hours");
    } else {
      endMoment = moment.tz(endDate, TZ);
      if (!endMoment.isValid()) endMoment = moment(startMoment).add(24, "hours");
    }
  } else {
    // default end = start + 24h
    endMoment = moment(startMoment).add(24, "hours");
  }

  // safety: ensure end > start
  if (!endMoment.isAfter(startMoment)) {
    endMoment = moment(startMoment).add(24, "hours");
  }

  return { startMoment, endMoment };
}

// Normalize for grouping but keep original display values for output
function normalizeString(s) {
  return (s || "").toString().trim().toLowerCase();
}

const buildGroupedItemWiseData = async ({ startDate, endDate, foodType }) => {
  const { startMoment, endMoment } = buildWindowFromQuery({ startDate, endDate });

  // 1) Fetch bills within window
  const bills = await Bill.findAll({
    where: {
      generated_at: { [Op.between]: [startMoment.toDate(), endMoment.toDate()] },
    },
    attributes: ["id", "order_details", "generated_at", "final_amount"],
  });

  // 2) Collect entries
  const entriesList = [];
  for (const bill of bills) {
    let items = bill.order_details;
    if (!items) continue;
    if (typeof items === "string") {
      try {
        items = JSON.parse(items);
      } catch (err) {
        console.warn(`Skipping malformed order_details for bill ${bill.id}`);
        continue;
      }
    }
    if (!Array.isArray(items)) continue;
    for (const entry of items) entriesList.push({ entry, billId: bill.id });
  }

  // 3) Collect candidate drink identifiers (menu ids and names)
  const drinkMenuIdsToLookup = new Set();
  const drinkNamesToLookup = new Set();

  for (const { entry } of entriesList) {
    const rawType = (entry.type || "").toString().trim().toLowerCase();
    const isDrink = rawType === "drink";
    if (!isDrink) continue;

    // Capture explicit menu id if present
    const maybeMenuId = Number(entry.menuId || entry.drinksMenuId || entry.menu_id || entry.drinks_menu_id);
    if (maybeMenuId && Number.isFinite(maybeMenuId)) drinkMenuIdsToLookup.add(maybeMenuId);

    // Capture item name fields
    const rawItemName = (entry.item || entry.item_desc || entry.name || "").toString().trim();
    if (rawItemName) drinkNamesToLookup.add(rawItemName);
  }

  // 4) Batch fetch DrinksMenu rows using ids and flexible name matches
  const drinksById = new Map(); // id -> DrinksMenu row (with category)
  const drinkNameToRowCandidates = []; // array of fetched rows to attempt matching against names

  if (drinkMenuIdsToLookup.size > 0 || drinkNamesToLookup.size > 0) {
    const idArray = Array.from(drinkMenuIdsToLookup).map((v) => Number(v)).filter(Boolean);
    const namesArray = Array.from(drinkNamesToLookup);
    // normalize & dedupe lowercase names
    const namesArrayLower = Array.from(new Set(namesArray.map((n) => normalizeString(n)).filter(Boolean)));

    const orConditions = [];
    if (idArray.length) orConditions.push({ id: { [Op.in]: idArray } });
    if (namesArrayLower.length) {
      // exact lower matches against DrinksMenu.name qualified
      orConditions.push(sequelize.where(fn("LOWER", col("DrinksMenu.name")), { [Op.in]: namesArrayLower }));
      // and fallback LIKE matches for suffixes/prefixes; qualify column here too
      for (const n of namesArrayLower) {
        orConditions.push(sequelize.where(fn("LOWER", col("DrinksMenu.name")), { [Op.like]: `%${n}%` }));
      }
    }

    try {
      const drinksRows = await DrinksMenu.findAll({
        where: {
          [Op.or]: orConditions.length ? orConditions : [{ id: -999999 }],
        },
        include: [
          {
            model: DrinksCategory,
            as: "category", // matches your model
            attributes: ["id", "name"],
          },
        ],
        attributes: ["id", "name", "drinksCategoryId"],
      });

      // populate maps/lists
      for (const d of drinksRows) {
        drinksById.set(d.id, d);
        drinkNameToRowCandidates.push(d);
      }
    } catch (err) {
      console.warn("DrinksMenu lookup failed:", err && err.message ? err.message : err);
      // proceed - we'll fallback to entry.category when mapping not found
    }
  }

  // 5) Helper to resolve a category for a drink entry (prefers DrinksMenu.category.name)
  function resolveDrinkCategoryForEntry(entry) {
    // try explicit menu id first
    const maybeMenuId = Number(entry.menuId || entry.drinksMenuId || entry.menu_id || entry.drinks_menu_id);
    if (maybeMenuId && drinksById.has(maybeMenuId)) {
      const d = drinksById.get(maybeMenuId);
      if (d && d.category && d.category.name) return d.category.name.toString().trim();
      if (d && d.name) return d.name.toString().trim(); // fallback to drink name if category missing
    }

    // try name-based heuristics
    const rawItemName = (entry.item || entry.item_desc || entry.name || "").toString().trim();
    const normItem = normalizeString(rawItemName);
    if (!normItem) return null;

    // exact match first
    let candidate = drinkNameToRowCandidates.find((r) => normalizeString(r.name) === normItem);
    if (!candidate) {
      // then try candidate whose name contains the order item (dbName includes orderItem)
      candidate = drinkNameToRowCandidates.find((r) => normalizeString(r.name).includes(normItem));
    }
    if (!candidate) {
      // then try reverse (order item includes dbName)
      candidate = drinkNameToRowCandidates.find((r) => normItem.includes(normalizeString(r.name)));
    }

    if (candidate && candidate.category && candidate.category.name) return candidate.category.name.toString().trim();
    if (candidate && candidate.name) return candidate.name.toString().trim();

    // no mapping found
    return null;
  }

  // 6) Grouping
  const grouped = new Map();

  for (const { entry } of entriesList) {
    const rawType = (entry.type || "").toString().trim().toLowerCase();
    const isFood = rawType === "food";
    const isDrink = rawType === "drink";

    // filter by foodType if requested
    if (foodType === "food" && !isFood) continue;
    if (foodType === "drink" && !isDrink) continue;

    const rawCategory = (entry.category || "").toString().trim();
    const rawItemName = (entry.item || entry.item_desc || entry.name || "").toString().trim();

    // compute category display:
    let categoryDisplay = rawCategory; // start with provided category

    if (isDrink) {
      // If this entry is marked custom, show Open Bar immediately
      const entryIsCustom = isTruthy(entry.is_custom);
      if (entryIsCustom) {
        categoryDisplay = "Open Bar";
      } else {
        // Always attempt to resolve from DrinksMenu first (prefer canonical category)
        const resolved = resolveDrinkCategoryForEntry(entry);
        if (resolved) {
          categoryDisplay = resolved;
        } else {
          // if no resolved category, keep provided category unless it's empty
          categoryDisplay = rawCategory || "Drinks";
        }
      }
    } else {
      // FOOD: If the entry is a custom item, show "Open Food".
      // This covers newly generated bills (we now store is_custom), and also
      // treats entries that already have category set to "Open Food".
      const entryIsCustom = isTruthy(entry.is_custom);
      const catLower = normalizeString(rawCategory);
      if (entryIsCustom || catLower === "open food") {
        categoryDisplay = "Open Food";
      } else if (!rawCategory || rawCategory.toUpperCase() === "N/A") {
        categoryDisplay = rawItemName || "Open Item";
      } else if (!rawCategory) {
        categoryDisplay = "Uncategorized";
      }
    }

    // compute price per unit robustly
    const quantity = Number(entry.quantity) || 0;
    let pricePerUnit = toNumber(entry.pricePerUnit);
    if (!pricePerUnit) {
      pricePerUnit = quantity ? toNumber(entry.totalAmount) / quantity : 0;
    }
    const totalAmount = toNumber(entry.totalAmount) || quantity * pricePerUnit;

    // grouping key
    const key = [
      normalizeString(categoryDisplay),
      normalizeString(rawItemName),
      pricePerUnit.toFixed(2),
      isFood ? "food" : "drink",
    ].join("||");

    if (!grouped.has(key)) {
      grouped.set(key, {
        categoryName: categoryDisplay,
        itemName: rawItemName,
        totalQuantity: 0,
        pricePerItem: pricePerUnit,
        totalAmount: 0,
        foodType: isFood ? "food" : "drink",
      });
    }

    const rec = grouped.get(key);
    rec.totalQuantity += quantity;
    rec.totalAmount += totalAmount;
  }

  // Convert to array and sort (food first)
  let result = Array.from(grouped.values());
  if (!foodType || foodType === "all") {
    result.sort((a, b) => {
      if (a.foodType === b.foodType) return 0;
      if (a.foodType === "food") return -1;
      return 1;
    });
  }

  return {
    window: { start: startMoment, end: endMoment },
    rows: result,
  };
};


// ---------- Helper: getCancelledMaps ----------
const getCancelledMaps = async (startDate, endDate) => {
  const foodCancelled = await CanceledFoodOrder.findAll({
    attributes: [
      "menuId",
      [fn("SUM", col("count")), "cancelledQty"],
    ],
    where: {
      isApproved: true,
      createdAt: {
        [Op.between]: [startDate, endDate],
      },
    },
    group: ["menuId"],
    raw: true,
  });

  const drinkCancelled = await CanceledDrinkOrder.findAll({
    attributes: [
      "drinksMenuId",
      [fn("SUM", col("count")), "cancelledQty"],
    ],
    where: {
      isApproved: true,
      createdAt: {
        [Op.between]: [startDate, endDate],
      },
    },
    group: ["drinksMenuId"],
    raw: true,
  });

  const foodMap = {};
  foodCancelled.forEach((i) => {
    if (i.menuId) foodMap[i.menuId] = Number(i.cancelledQty || 0);
  });

  const drinkMap = {};
  drinkCancelled.forEach((i) => {
    if (i.drinksMenuId)
      drinkMap[i.drinksMenuId] = Number(i.cancelledQty || 0);
  });

  return { foodMap, drinkMap };
};

// ---------- Endpoint: getItemWiseReport ----------

const getItemWiseReport = async (req, res) => {
  try {
    const { startDate, endDate, foodType } = req.query;

    const { window, rows } = await buildGroupedItemWiseData({
      startDate,
      endDate,
      foodType,
    });

    // 🔥 Fetch cancelled quantities
    const { foodMap, drinkMap } = await getCancelledMaps(
      window.start.toDate(),
      window.end.toDate()
    );

    // 🔥 Remove cancelled quantities
    const filteredRows = rows
      .map((item) => {
        const totalQty = toNumber(item.totalQuantity);
        const totalAmount = toNumber(item.totalAmount);

        let cancelledQty = 0;

        if (item.foodType === "food") {
          cancelledQty = foodMap[item.menuId] || 0;
        } else {
          cancelledQty = drinkMap[item.menuId] || 0;
        }

        const netQty = totalQty - cancelledQty;
        if (netQty <= 0) return null;

        const pricePerUnit = totalQty > 0 ? totalAmount / totalQty : 0;

        return {
          ...item,
          totalQuantity: netQty,
          totalAmount: (pricePerUnit * netQty).toFixed(2),
        };
      })
      .filter(Boolean);

    // 🔥 Enrich with tax / GST / VAT
    const enrichedData = filteredRows.map((item) => {
      const totalAmount = toNumber(item.totalAmount);
      const discount = toNumber(item.discount || 0);
      const taxableAmount = Math.max(0, totalAmount - discount);

      let tax = 0,
        cgst = 0,
        sgst = 0,
        vat = 0;

      const category = normalizeString(item.categoryName);
      const isFood = item.foodType === "food";

      if (isFood) {
        cgst = taxableAmount * 0.025;
        sgst = taxableAmount * 0.025;
        tax = cgst + sgst;
      } else if (category === "juices" || category === "mocktails") {
        cgst = taxableAmount * 0.025;
        sgst = taxableAmount * 0.025;
        tax = cgst + sgst;
      } else {
        vat = taxableAmount * 0.1;
        tax = vat;
      }

      const grossSale = totalAmount + tax;

      return {
        ...item,
        discount: discount.toFixed(2),
        tax: tax.toFixed(2),
        cgst: cgst.toFixed(2),
        sgst: sgst.toFixed(2),
        vat: vat.toFixed(2),
        grossSale: grossSale.toFixed(2),
      };
    });

    // 🔥 Summary
    const quantities = enrichedData.map((d) => toNumber(d.totalQuantity));
    const totalAmounts = enrichedData.map((d) => toNumber(d.totalAmount));
    const taxes = enrichedData.map((d) => toNumber(d.tax));
    const grossSales = enrichedData.map((d) => toNumber(d.grossSale));

    const summary = [
      {
        label: "Total",
        totalQuantity: quantities.reduce((a, b) => a + b, 0),
        totalAmount: totalAmounts.reduce((a, b) => a + b, 0),
        tax: taxes.reduce((a, b) => a + b, 0),
        grossSale: grossSales.reduce((a, b) => a + b, 0),
      },
      {
        label: "Min",
        totalQuantity: quantities.length ? Math.min(...quantities) : 0,
        totalAmount: totalAmounts.length ? Math.min(...totalAmounts) : 0,
        tax: taxes.length ? Math.min(...taxes) : 0,
        grossSale: grossSales.length ? Math.min(...grossSales) : 0,
      },
      {
        label: "Max",
        totalQuantity: quantities.length ? Math.max(...quantities) : 0,
        totalAmount: totalAmounts.length ? Math.max(...totalAmounts) : 0,
        tax: taxes.length ? Math.max(...taxes) : 0,
        grossSale: grossSales.length ? Math.max(...grossSales) : 0,
      },
      {
        label: "Avg",
        totalQuantity: quantities.length
          ? quantities.reduce((a, b) => a + b, 0) / quantities.length
          : 0,
        totalAmount: totalAmounts.length
          ? totalAmounts.reduce((a, b) => a + b, 0) / totalAmounts.length
          : 0,
        tax: taxes.length
          ? taxes.reduce((a, b) => a + b, 0) / taxes.length
          : 0,
        grossSale: grossSales.length
          ? grossSales.reduce((a, b) => a + b, 0) / grossSales.length
          : 0,
      },
    ];

    return res.status(200).json({
      message: "Item-wise report (cancelled items excluded)",
      window: {
        startIST: window.start.tz(TZ).format("YYYY-MM-DD HH:mm"),
        endIST: window.end.tz(TZ).format("YYYY-MM-DD HH:mm"),
      },
      data: enrichedData,
      summary,
    });
  } catch (error) {
    console.error("getItemWiseReport error:", error);
    return res.status(500).json({
      message: "Failed to fetch item report",
      error: error.message,
    });
  }
};


// ---------- Endpoint: downloadItemWiseReport ----------
const downloadItemWiseReport = async (req, res) => {
  try {
    const { startDate, endDate, foodType, exportType } = req.query;

    // fetch grouped data + window
    const { window, rows } = await buildGroupedItemWiseData({
      startDate,
      endDate,
      foodType,
    });

    // 🔥 fetch cancelled quantities
    const { foodMap, drinkMap } = await getCancelledMaps(
      window.start.toDate(),
      window.end.toDate()
    );

    // 🔥 remove cancelled qty
    const filteredRows = rows
      .map((item) => {
        const totalQty = toNumber(item.totalQuantity);
        const totalAmount = toNumber(item.totalAmount);

        let cancelledQty = 0;
        if (item.foodType === "food") {
          cancelledQty = foodMap[item.menuId] || 0;
        } else {
          cancelledQty = drinkMap[item.menuId] || 0;
        }

        const netQty = totalQty - cancelledQty;
        if (netQty <= 0) return null;

        const pricePerUnit = totalQty > 0 ? totalAmount / totalQty : 0;

        return {
          ...item,
          totalQuantity: netQty,
          totalAmount: pricePerUnit * netQty,
          pricePerItem: pricePerUnit,
        };
      })
      .filter(Boolean);

    // 🔥 enrich rows
    const enrichedData = filteredRows.map((item) => {
      const totalAmount = toNumber(item.totalAmount);
      const discount = toNumber(item.discount || 0);
      const taxableAmount = Math.max(0, totalAmount - discount);

      let tax = 0,
        cgst = 0,
        sgst = 0,
        vat = 0;

      const category = normalizeString(item.categoryName);
      const isFood = item.foodType === "food";

      if (isFood) {
        cgst = taxableAmount * 0.025;
        sgst = taxableAmount * 0.025;
        tax = cgst + sgst;
      } else if (category === "juices" || category === "mocktails") {
        cgst = taxableAmount * 0.025;
        sgst = taxableAmount * 0.025;
        tax = cgst + sgst;
      } else {
        vat = taxableAmount * 0.1;
        tax = vat;
      }

      const grossSale = totalAmount + tax;

      return {
        categoryName: item.categoryName,
        itemName: item.itemName,
        totalQuantity: toNumber(item.totalQuantity),
        pricePerItem: toNumber(item.pricePerItem),
        totalAmount,
        discount,
        tax,
        cgst,
        sgst,
        vat,
        grossSale,
        foodType: item.foodType,
      };
    });

    // filename
    const startStr = window.start.tz(TZ).format("YYYYMMDD_HHmm");
    const endStr = window.end.tz(TZ).format("YYYYMMDD_HHmm");
    const filename = `item_report_${startStr}_${endStr}`;

    // ================= CSV =================
    if (exportType === "csv") {
      const rowsForCsv = enrichedData.map((r) => ({
        categoryName: r.categoryName || "",
        itemName: r.itemName || "",
        totalQuantity: r.totalQuantity,
        pricePerItem: r.pricePerItem.toFixed(2),
        totalAmount: r.totalAmount.toFixed(2),
        discount: r.discount.toFixed(2),
        tax: r.tax.toFixed(2),
        grossSale: r.grossSale.toFixed(2),
        foodType: r.foodType || "",
      }));

      const parser = new Parser();
      const csv = parser.parse(rowsForCsv);

      res.setHeader("Content-Type", "text/csv; charset=utf-8");
      res.setHeader(
        "Content-Disposition",
        `attachment; filename="${filename}.csv"`
      );
      return res.status(200).send(csv);
    }

    // ================= EXCEL =================
    if (exportType === "excel") {
      const workbook = new ExcelJS.Workbook();
      const sheet = workbook.addWorksheet("Item Report");

      sheet.columns = [
        { header: "Category", key: "categoryName", width: 30 },
        { header: "Item", key: "itemName", width: 40 },
        { header: "Qty", key: "totalQuantity", width: 10 },
        { header: "Price/Item", key: "pricePerItem", width: 15 },
        { header: "Total Amount", key: "totalAmount", width: 15 },
        { header: "Discount", key: "discount", width: 12 },
        { header: "Tax", key: "tax", width: 12 },
        { header: "Gross Sale", key: "grossSale", width: 15 },
        { header: "Type", key: "foodType", width: 10 },
      ];

      enrichedData.forEach((row) => {
        sheet.addRow({
          categoryName: row.categoryName || "",
          itemName: row.itemName || "",
          totalQuantity: row.totalQuantity,
          pricePerItem: row.pricePerItem,
          totalAmount: row.totalAmount,
          discount: row.discount,
          tax: row.tax,
          grossSale: row.grossSale,
          foodType: row.foodType || "",
        });
      });

      res.setHeader(
        "Content-Type",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      );
      res.setHeader(
        "Content-Disposition",
        `attachment; filename="${filename}.xlsx"`
      );

      await workbook.xlsx.write(res);
      return res.end();
    }

    // ================= PDF =================
    if (exportType === "pdf") {
      const doc = new PDFDocument({ margin: 30, size: "A4" });

      res.setHeader("Content-Type", "application/pdf");
      res.setHeader(
        "Content-Disposition",
        `attachment; filename="${filename}.pdf"`
      );

      doc.pipe(res);

      doc.fontSize(14).text("Item-Wise Report", { align: "center" });
      doc.moveDown(0.5);
      doc.fontSize(10).text(
        `Window: ${window.start.tz(TZ).format("YYYY-MM-DD HH:mm")} — ${window.end
          .tz(TZ)
          .format("YYYY-MM-DD HH:mm")} (IST)`
      );
      doc.moveDown(0.5);

      doc
        .fontSize(10)
        .text(
          "Category".padEnd(28) +
            "Item".padEnd(40) +
            "Qty".padEnd(6) +
            "Price".padEnd(12) +
            "Total"
        );

      doc.moveDown(0.3);

      enrichedData.forEach((r) => {
        const line =
          (r.categoryName || "").slice(0, 26).padEnd(28) +
          (r.itemName || "").slice(0, 36).padEnd(40) +
          String(r.totalQuantity).padEnd(6) +
          `₹${r.pricePerItem.toFixed(2)}`.padEnd(12) +
          `₹${r.totalAmount.toFixed(2)}`;

        doc.fontSize(9).text(line);
      });

      doc.end();
      return;
    }

    return res
      .status(400)
      .json({ message: "Unsupported exportType. Use csv | excel | pdf" });
  } catch (error) {
    console.error("downloadItemWiseReport error:", error);
    return res.status(500).json({
      message: "Failed to export item report",
      error: error.message,
    });
  }
};



// ---------- Sales Report (updated to include payment_breakdown & tip_amount) ----------
// Robust JSON parser for payment_breakdown (object, JSON string, double-encoded)
function safeParseJsonMaybeString(value) {
  if (value == null) return {};
  if (typeof value === "object") return value;
  if (typeof value !== "string") return {};

  // Some DB drivers return double-escaped JSON strings like "\"{\\\"cash\\\":2000}\""
  // Try straightforward parse first, then try forgiving unescape and parse.
  try {
    return JSON.parse(value);
  } catch (e1) {
    try {
      // Try to fix common double-escape patterns.
      // Replace '\"' sequences and unescape backslashes an extra time, then parse.
      const unescaped = value.replace(/\\"/g, '"').replace(/\\+/g, "\\");
      const once = JSON.parse(unescaped);
      if (typeof once === "string") {
        // if still a string, try parse again
        return JSON.parse(once);
      }
      return typeof once === "object" ? once : {};
    } catch (e2) {
      // final fallback: try minimal cleanup (remove wrapping quotes)
      try {
        const trimmed = value.trim();
        const maybe = trimmed.startsWith('"') && trimmed.endsWith('"') ? trimmed.slice(1, -1) : trimmed;
        return JSON.parse(maybe);
      } catch (e3) {
        return {};
      }
    }
  }
}

// ---------- Sales Report (fixed totals using Bills fallback) ----------
const getSalesReport = async (req, res) => {
  try {
    const { startDate, endDate, status } = req.query;
    const { startMoment, endMoment } = buildWindowFromQuery({ startDate, endDate });

    const attrs = Object.keys(Bill.rawAttributes || {});
const compField = attrs.includes("isComplimentary")
  ? "isComplimentary"
  : attrs.includes("is_complimentary")
  ? "is_complimentary"
  : null;

// time range clause (always present)
const timeWhere = { time_of_bill: { [Op.between]: [startMoment.toDate(), endMoment.toDate()] } };

// Build billsWhere according to requested status:
// - status === 'all'           => include all bills (complimentary and non-complimentary)
// - status === 'complimentary' => include only complimentary bills
// - otherwise                  => exclude complimentary bills
let billsWhere = timeWhere;

const statusLower = String(status).toLowerCase();

if (statusLower === "all") {
  // Include all bills - no complimentary filter
  billsWhere = timeWhere;
} else if (compField) {
  // Prefer explicit complimentary column when present
  if (statusLower === "complimentary") {
    // include only rows where compField is true
    const compFilter = sequelize.where(sequelize.col(compField), { [Op.eq]: true });
    billsWhere = { [Op.and]: [timeWhere, compFilter] };
  } else {
    // exclude rows where compField is true
    const compFilter = sequelize.where(sequelize.col(compField), { [Op.not]: true });
    billsWhere = { [Op.and]: [timeWhere, compFilter] };
  }
} else {
  // No complimentary column exists on model. Use final_amount === 0 as fallback marker.
  if (statusLower === "complimentary") {
    billsWhere = { [Op.and]: [timeWhere, { final_amount: 0 }] };
  } else if (statusLower !== "all") {
    // exclude final_amount === 0 (only for non-'all' statuses)
    billsWhere = { [Op.and]: [timeWhere, { final_amount: { [Op.ne]: 0 } }] };
  }
}
    // fetch bills
    const bills = await Bill.findAll({
      where: billsWhere,
      attributes: [
        "id",
        "payment_breakdown",
        "tip_amount",
        "total_amount",
        "discount_amount",
        "final_amount",
        "tax_amount",
        "vat_amount",
        "service_charge_amount",
        ...(compField ? [compField] : []),
      ],
      raw: true,
    });

    // invoice info
    const billIds = bills.map((b) => Number(b.id)).filter(Boolean).sort((a, b) => a - b);
    const firstBillId = billIds.length ? billIds[0] : "";
    const lastBillId = billIds.length ? billIds[billIds.length - 1] : "";
    const totalBills = billIds.length;

    // aggregate and reconcile per-bill payments
    let totalAmount = 0;
    let totalDiscount = 0;
    let totalSales = 0; // sum of final_amount
    let gst = 0;
    let vat = 0;
    let serviceCharges = 0;
    let roundOff = 0;
    let wavedOff = 0;
    let totalTips = 0;

    let cashTotal = 0;
    let cardTotal = 0;
    let upiTotal = 0;
    let otherPaymentsTotal = 0;
    let roundingAdjustment = 0;

    for (const b of bills) {
      // If status is 'all' and bill is complimentary, set final_amount to 0
      let finalAmt = toNumber(b.final_amount || 0);
      if (statusLower === "all" && compField && b[compField]) {
        finalAmt = 0;
      }
      finalAmt = Number((finalAmt).toFixed(2));
      
      totalAmount += toNumber(b.total_amount || 0);
      totalDiscount += toNumber(b.discount_amount || b.discount || 0);
      totalSales += finalAmt;
      gst += toNumber(b.tax_amount || 0);
      vat += toNumber(b.vat_amount || 0);
      serviceCharges += toNumber(b.service_charge_amount || 0);
      totalTips += toNumber(b.tip_amount || 0);

      const pbRaw = b.payment_breakdown;
      const pb = safeParseJsonMaybeString(pbRaw);
      const norm = {};
      for (const k of Object.keys(pb || {})) {
        const key = (k || "").toString().trim().toLowerCase();
        norm[key] = toNumber(pb[k]);
      }

      // accumulate known buckets
      cashTotal += toNumber(norm.cash);
      cardTotal += toNumber(norm.card);
      upiTotal += toNumber(norm.upi);

      // sum all parsed payment pieces
      let pbSum = 0;
      for (const k of Object.keys(norm)) {
        pbSum += toNumber(norm[k]);
      }

      // diff between authoritative final_amount and payment_breakdown pieces
      // attach diff to otherPaymentsTotal so totals reconcile
      const diff = Number((finalAmt - pbSum).toFixed(2));
      if (Math.abs(diff) >= 0.005) { // tolerate micro FP noise
        otherPaymentsTotal += diff;
        roundingAdjustment += diff;
      }

      // add explicit non-cash/card/upi keys to otherPayments
      for (const k of Object.keys(norm)) {
        if (!["cash", "card", "upi"].includes(k)) {
          otherPaymentsTotal += toNumber(norm[k]);
        }
      }
    }

    // enforce final equality (avoid tiny FP residue)
    const paymentsTotalBeforeAdjust = Number((cashTotal + cardTotal + upiTotal + otherPaymentsTotal).toFixed(2));
    const salesTotalRounded = Number(totalSales.toFixed(2));
    const paymentDelta = Number((salesTotalRounded - paymentsTotalBeforeAdjust).toFixed(2));
    if (Math.abs(paymentDelta) >= 0.005) {
      otherPaymentsTotal += paymentDelta;
      roundingAdjustment += paymentDelta;
    }

    // final numeric rounding
    totalAmount = Number(totalAmount.toFixed(2));
    totalDiscount = Number(totalDiscount.toFixed(2));
    const netSales = Number(Math.max(0, totalAmount - totalDiscount).toFixed(2));
    totalSales = Number(totalSales.toFixed(2));
    gst = Number(gst.toFixed(2));
    vat = Number(vat.toFixed(2));
    const totalTax = Number((gst + vat).toFixed(2));
    serviceCharges = Number(serviceCharges.toFixed(2));
    roundOff = Number(roundOff).toFixed(2);
    wavedOff = Number(wavedOff).toFixed(2);
    totalTips = Number(totalTips.toFixed(2));

    cashTotal = Number(cashTotal.toFixed(2));
    cardTotal = Number(cardTotal.toFixed(2));
    upiTotal = Number(upiTotal.toFixed(2));
    otherPaymentsTotal = Number(otherPaymentsTotal.toFixed(2));
    roundingAdjustment = Number(roundingAdjustment.toFixed(2));

    const summaryRow = {
      label: "Total",
      invoiceNos: firstBillId && lastBillId ? `${firstBillId}-${lastBillId}` : "",
      totalBills,
      totalAmount: totalAmount.toFixed(2),
      totalDiscount: totalDiscount.toFixed(2),
      netSales: netSales.toFixed(2),
      gst: gst.toFixed(2),
      vat: vat.toFixed(2),
      totalTax: totalTax.toFixed(2),
      serviceCharges: serviceCharges.toFixed(2),
      roundOff: roundOff.toString(),
      wavedOff: wavedOff.toString(),
      totalSales: totalSales.toFixed(2),
      payments: {
        cash: cashTotal.toFixed(2),
        card: cardTotal.toFixed(2),
        upi: upiTotal.toFixed(2),
        other: otherPaymentsTotal.toFixed(2),
        roundingAdjustment: roundingAdjustment.toFixed(2),
      },
      cash: cashTotal.toFixed(2),
      card: cardTotal.toFixed(2),
      upi: upiTotal.toFixed(2),
      paymentsFromSummary: {
        cash: Number(0).toFixed(2),
        card: Number(0).toFixed(2),
        upi: Number(0).toFixed(2),
      },
      totalTips: totalTips.toFixed(2),
    };

    return res.status(200).json({
      message: "Sales Report (calculated from Bills)",
      window: {
        startIST: startMoment.tz(TZ).format("YYYY-MM-DD HH:mm"),
        endIST: endMoment.tz(TZ).format("YYYY-MM-DD HH:mm"),
      },
      summary: [summaryRow],
    });
  } catch (error) {
    console.error("Error fetching sales report:", error);
    res.status(500).json({
      message: "Failed to fetch sales report",
      error: error.message,
    });
  }
};


// ---------- downloadSalesReport (aligned with getSalesReport calculation) ----------
async function exportSalesSummary(summaryRow, startMoment, endMoment, exportType, res) {
  const startStr = startMoment.format("DD-MM-YY");
  const endStr = endMoment.format("DD-MM-YY");
  const filenameBase = `Sales-Report_${startStr}_${endStr}`;

  if (exportType === "excel") {
    const workbook = new ExcelJS.Workbook();
    const sheet = workbook.addWorksheet("Sales Summary");
    sheet.addRow(Object.keys(summaryRow));
    sheet.addRow(Object.values(summaryRow));

    res.setHeader(
      "Content-Type",
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    );
    res.setHeader("Content-Disposition", `attachment; filename=${filenameBase}.xlsx`);

    await workbook.xlsx.write(res);
    res.end();
  } else if (exportType === "csv") {
    const parser = new Parser();
    const csv = parser.parse([summaryRow]);
    res.setHeader("Content-Type", "text/csv");
    res.setHeader("Content-Disposition", `attachment; filename=${filenameBase}.csv`);
    res.send(csv);
  } else if (exportType === "pdf") {
    const doc = new PDFDocument();
    res.setHeader("Content-Type", "application/pdf");
    res.setHeader("Content-Disposition", `attachment; filename=${filenameBase}.pdf`);
    doc.pipe(res);
    doc.text(JSON.stringify(summaryRow, null, 2));
    doc.end();
  } else {
    res.status(400).json({ message: "Invalid export type" });
  }
}

// ----------------- main controller -----------------

const XLSX = require("xlsx");
const path = require("path");
const fs = require("fs");
const exportSalesSummary1 = async (rows, startMoment, endMoment, exportType, res) => {
  try {
    // Convert array of objects -> worksheet
    const ws = XLSX.utils.json_to_sheet(rows, {
      header: Object.keys(rows[0]), // ensures consistent column order
      skipHeader: false,
    });

    // Auto column width
    const colWidths = Object.keys(rows[0]).map((key) => ({
      wch: Math.max(
        key.length,
        ...rows.map((r) => String(r[key] ?? "").length)
      ) + 2,
    }));
    ws["!cols"] = colWidths;

    // Create workbook and append sheet
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, "Sales Summary");

    // Generate filename
    const fileName = `Sales_Summary_${startMoment.format("YYYYMMDD")}_${endMoment.format("YYYYMMDD")}.xlsx`;
    const filePath = path.join(__dirname, "../../exports", fileName);

    // Write file to disk
    XLSX.writeFile(wb, filePath);

    // Send file to client
    res.download(filePath, fileName, (err) => {
      if (err) console.error("File download error:", err);
      fs.unlink(filePath, () => {}); // delete after sending
    });
  } catch (error) {
    console.error("Error exporting Excel:", error);
    res.status(500).json({ message: "Failed to export Excel file", error: error.message });
  }
};

const downloadSalesReport = async (req, res) => {
  try {
    const { startDate, endDate, status, exportType } = req.query;
    const { startMoment, endMoment } = buildWindowFromQuery({ startDate, endDate });

    // detect complimentary field
    const attrs = Object.keys(Bill.rawAttributes || {});
    const compField = attrs.includes("isComplimentary")
      ? "isComplimentary"
      : attrs.includes("is_complimentary")
      ? "is_complimentary"
      : null;

    const timeWhere = { time_of_bill: { [Op.between]: [startMoment.toDate(), endMoment.toDate()] } };
    let billsWhere = timeWhere;

    const statusLower = status?.toLowerCase() || '';

    if (statusLower === "all") {
      // Include all bills - no complimentary filter
      billsWhere = timeWhere;
    } else if (compField) {
      billsWhere =
        statusLower === "complimentary"
          ? { [Op.and]: [timeWhere, sequelize.where(sequelize.col(compField), true)] }
          : { [Op.and]: [timeWhere, sequelize.where(sequelize.col(compField), { [Op.not]: true })] };
    } else {
      billsWhere =
        statusLower === "complimentary"
          ? { [Op.and]: [timeWhere, { final_amount: 0 }] }
          : statusLower === "all"
          ? timeWhere
          : { [Op.and]: [timeWhere, { final_amount: { [Op.ne]: 0 } }] };
    }

    // fetch bills
    const bills = await Bill.findAll({
      where: billsWhere,
      attributes: [
        "id",
        "time_of_bill",
        "payment_breakdown",
        "tip_amount",
        "total_amount",
        "discount_amount",
        "final_amount",
        "tax_amount",
        "vat_amount",
        "service_charge_amount",
        ...(compField ? [compField] : []),
      ],
      raw: true,
    });

    const billIds = bills.map((b) => Number(b.id)).filter(Boolean).sort((a, b) => a - b);
    const firstBillId = billIds[0] || "";
    const lastBillId = billIds[billIds.length - 1] || "";
    const totalBills = billIds.length;

    // totals
    let totalAmount = 0,
      totalDiscount = 0,
      totalSales = 0,
      gst = 0,
      vat = 0,
      serviceCharges = 0,
      totalTips = 0,
      cashTotal = 0,
      cardTotal = 0,
      upiTotal = 0,
      otherPaymentsTotal = 0;

    const rows = [];

    for (const b of bills) {
      const totalAmt = toNumber(b.total_amount);
      const discount = toNumber(b.discount_amount);
      const gstAmt = toNumber(b.tax_amount);
      const vatAmt = toNumber(b.vat_amount);
      const serviceAmt = toNumber(b.service_charge_amount);
      let finalAmt = toNumber(b.final_amount);
      const tipAmt = toNumber(b.tip_amount);

      // If status is 'all' and bill is complimentary, set final_amount to 0
      if (statusLower === "all" && compField && b[compField]) {
        finalAmt = 0;
      }

      // Parse payment breakdown
      const pb =
        typeof b.payment_breakdown === "string"
          ? JSON.parse(b.payment_breakdown)
          : b.payment_breakdown || {};
      const payments = Object.fromEntries(
        Object.entries(pb).map(([k, v]) => [k.toLowerCase(), toNumber(v)])
      );

      const cash = payments.cash || 0;
      const card = payments.card || 0;
      const upi = payments.upi || 0;

      // accumulate totals
      totalAmount += totalAmt;
      totalDiscount += discount;
      totalSales += finalAmt;
      gst += gstAmt;
      vat += vatAmt;
      serviceCharges += serviceAmt;
      totalTips += tipAmt;
      cashTotal += cash;
      cardTotal += card;
      upiTotal += upi;

      rows.push({
        "Bill ID": b.id,
        "Date/Time": new Date(b.time_of_bill).toLocaleString("en-IN", {
          timeZone: "Asia/Kolkata",
        }),
        "Total Amount": totalAmt.toFixed(2),
        "Discount": discount.toFixed(2),
        "Net Sales": (totalAmt - discount).toFixed(2),
        "GST": gstAmt.toFixed(2),
        "VAT": vatAmt.toFixed(2),
        "Total Tax": (gstAmt + vatAmt).toFixed(2),
        "Service Charges": serviceAmt.toFixed(2),
        "Final Amount": finalAmt.toFixed(2),
        "Cash": cash.toFixed(2),
        "Card": card.toFixed(2),
        "UPI": upi.toFixed(2),
        "Tip": tipAmt.toFixed(2),
      });
    }

    // Add final total row
    rows.push({
      "Bill ID": "",
      "Date/Time": "Total",
      "Total Amount": totalAmount.toFixed(2),
      "Discount": totalDiscount.toFixed(2),
      "Net Sales": (totalAmount - totalDiscount).toFixed(2),
      "GST": gst.toFixed(2),
      "VAT": vat.toFixed(2),
      "Total Tax": (gst + vat).toFixed(2),
      "Service Charges": serviceCharges.toFixed(2),
      "Final Amount": totalSales.toFixed(2),
      "Cash": cashTotal.toFixed(2),
      "Card": cardTotal.toFixed(2),
      "UPI": upiTotal.toFixed(2),
      "Tip": totalTips.toFixed(2),
    });

    // Sort rows by Bill ID (numeric), excluding the Total row which has empty Bill ID
    const totalRow = rows[rows.length - 1];
    const detailRows = rows.slice(0, rows.length - 1);
    detailRows.sort((a, b) => Number(a["Bill ID"]) - Number(b["Bill ID"]));
    const sortedRows = [...detailRows, totalRow];

    // Pass structured tabular data
    return await exportSalesSummary1(sortedRows, startMoment, endMoment, exportType, res);
  } catch (error) {
    console.error("Error downloading sales report:", error);
    return res.status(500).json({
      message: "Failed to export sales report",
      error: error.message,
    });
  }
};




//---------------------------------------------------------------------------------------

const buildInvoiceSummary = async (startDate, endDate) => {
  const start = startDate
    ? moment(startDate).startOf("day").toDate()
    : moment().startOf("day").toDate();
  const end = endDate
    ? moment(endDate).endOf("day").toDate()
    : moment().endOf("day").toDate();

  const bills = await Bill.findAll({
    where: {
      time_of_bill: {
        [Op.between]: [start, end],
      },
    },
    order: [["id", "ASC"]],
  });
  console.log(bills);
  return {
    idStart: bills.length ? bills[0].id : null,
    idEnd: bills.length ? bills[bills.length - 1].id : null,
    totalBills: bills.length,
    totalAmount: bills.reduce((sum, b) => sum + b.total_amount, 0),
    totalDiscountAmount: bills.reduce((sum, b) => sum + b.discount_amount, 0),
    totalServiceChargeAmount: bills.reduce(
      (sum, b) => sum + b.service_charge_amount,
      0
    ),
  };
};

const getInvoiceReport = async (req, res) => {
  try {
    const { startDate, endDate } = req.query;
    const summary = await buildInvoiceSummary(startDate, endDate);
    res.status(200).json({ message: "Invoice report summary", data: summary });
  } catch (error) {
    console.error("Error fetching invoice report:", error);
    res.status(500).json({
      message: "Failed to fetch invoice report",
      error: error.message,
    });
  }
};

const downloadInvoiceReport = async (req, res) => {
  try {
    const { startDate, endDate, exportType } = req.query;

    const summary = await buildInvoiceSummary(startDate, endDate);
    const filenameBase = `invoice_report_${moment(
      startDate || new Date()
    ).format("YYYYMMDD")}-${moment(endDate || new Date()).format("YYYYMMDD")}`;

    if (exportType === "csv") {
      const parser = new Parser();
      const csv = parser.parse([summary]);
      res.setHeader("Content-Type", "text/csv");
      res.setHeader(
        "Content-Disposition",
        `attachment; filename=${filenameBase}.csv`
      );
      return res.send(csv);
    }

    if (exportType === "excel" || exportType === "xlsx") {
      const workbook = new ExcelJS.Workbook();
      const sheet = workbook.addWorksheet("Invoice Report");
      sheet.columns = [
        { header: "Invoice Start", key: "idStart", width: 10 },
        { header: "Invoice End", key: "idEnd", width: 10 },
        { header: "Total Bills", key: "totalBills", width: 15 },
        { header: "Total Amount", key: "totalAmount", width: 15 },
        { header: "Discount Amount", key: "totalDiscountAmount", width: 20 },
        {
          header: "Service Charge Amount",
          key: "totalServiceChargeAmount",
          width: 25,
        },
      ];
      sheet.addRow(summary);

      res.setHeader(
        "Content-Type",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      );
      res.setHeader(
        "Content-Disposition",
        `attachment; filename=${filenameBase}.xlsx`
      );
      await workbook.xlsx.write(res);
      return res.end();
    }

    if (exportType === "pdf") {
      const doc = new PDFDocument({ margin: 30, size: "A4" });
      const buffers = [];
      doc.on("data", buffers.push.bind(buffers));
      doc.on("end", () => {
        const pdfData = Buffer.concat(buffers);
        res.setHeader("Content-Type", "application/pdf");
        res.setHeader(
          "Content-Disposition",
          `attachment; filename=${filenameBase}.pdf`
        );
        res.send(pdfData);
      });

      doc
        .fontSize(16)
        .text("Invoice Report Summary", { align: "center" })
        .moveDown();
      doc.fontSize(12);
      Object.entries(summary).forEach(([key, value]) => {
        doc.text(`${key}: ${value}`);
      });

      doc.end();
      return;
    }

    return res.status(400).json({ message: "Unsupported exportType" });
  } catch (error) {
    console.error("Error downloading invoice report:", error);
    res.status(500).json({
      message: "Failed to export invoice report",
      error: error.message,
    });
  }
};

//------------------------------------------------------------------------------

const subOrderWiseReport = async (req, res) => {
  try {
    let { startDate, endDate } = req.query;

    const today = new Date();
    if (!startDate) startDate = today.toISOString().slice(0, 10);
    if (!endDate) endDate = today.toISOString().slice(0, 10);

    const start = new Date(startDate);
    const end = new Date(endDate);
    end.setHours(23, 59, 59, 999);

    const bills = await Bill.findAll({
      where: {
        time_of_bill: {
          [Op.between]: [start, end],
        },
      },
      include: [
        {
          model: Table,
          as: "table",
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

    const sectionData = {};

    for (const bill of bills) {
      const section = bill.table?.section?.name || "Unknown";

      if (!sectionData[section]) {
        sectionData[section] = {
          sectionName: section,
          billCount: 0,
          totalAmount: 0,
          totalDiscount: 0,
        };
      }

      sectionData[section].billCount += 1;
      sectionData[section].totalAmount += bill.total_amount || 0;
      sectionData[section].totalDiscount += bill.discount_amount || 0;
    }

    const finalResult = Object.values(sectionData);
    return res.json({ data: finalResult });
  } catch (err) {
    console.error("Error fetching sub order wise report:", err);
    res.status(500).json({ message: "Internal server error" });
  }
};

const downloadSubOrderWiseReport = async (req, res) => {
  try {
    let { startDate, endDate, exportType } = req.query;

    const today = new Date();
    if (!startDate) startDate = today.toISOString().slice(0, 10);
    if (!endDate) endDate = today.toISOString().slice(0, 10);

    if (!exportType) {
      return res
        .status(400)
        .json({ message: "exportType is required (csv, xlsx, pdf)" });
    }

    const start = new Date(startDate);
    const end = new Date(endDate);
    end.setHours(23, 59, 59, 999);

    const bills = await Bill.findAll({
      where: {
        time_of_bill: {
          [Op.between]: [start, end],
        },
      },
      include: [
        {
          model: Table,
          as: "table",
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

    const sectionMap = {};

    for (const bill of bills) {
      const section = bill.table?.section?.name || "Unknown";
      if (!sectionMap[section]) {
        sectionMap[section] = {
          Section: section,
          BillCount: 0,
          Amount: 0,
          Discount: 0,
        };
      }

      sectionMap[section].BillCount += 1;
      sectionMap[section].Amount += bill.total_amount || 0;
      sectionMap[section].Discount += bill.discount_amount || 0;
    }

    const finalData = Object.values(sectionMap);

    // CSV Export
    if (exportType === "csv") {
      const parser = new Parser();
      const csv = parser.parse(finalData);

      res.setHeader("Content-Type", "text/csv");
      res.setHeader(
        "Content-Disposition",
        `attachment; filename=SubOrderWiseReport_${startDate}_to_${endDate}.csv`
      );
      return res.send(csv);
    }

    // Excel Export
    if (exportType === "xlsx") {
      const workbook = new ExcelJS.Workbook();
      const sheet = workbook.addWorksheet("Sub Order Report");

      sheet.columns = Object.keys(finalData[0]).map((key) => ({
        header: key,
        key,
        width: 20,
      }));

      sheet.addRows(finalData);
      sheet.getRow(1).font = { bold: true };

      res.setHeader(
        "Content-Type",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      );
      res.setHeader(
        "Content-Disposition",
        `attachment; filename=SubOrderWiseReport_${startDate}_to_${endDate}.xlsx`
      );

      await workbook.xlsx.write(res);
      return res.end();
    }

    // PDF Export (keep file-based logic if necessary)
    if (exportType === "pdf") {
      const filename = `SubOrderWiseReport_${startDate}_to_${endDate}.pdf`;
      const filepath = path.join(__dirname, "..", "exports", filename);
      fs.mkdirSync(path.dirname(filepath), { recursive: true });

      const doc = new PDFDocument();
      const stream = fs.createWriteStream(filepath);
      doc.pipe(stream);

      doc.fontSize(16).text("Sub Order Wise Report", { align: "center" });
      doc.moveDown();

      finalData.forEach((item) => {
        doc.fontSize(12).text(`Section: ${item.Section}`);
        doc.text(`Bills: ${item.BillCount}`);
        doc.text(`Amount: ₹${item.Amount.toFixed(2)}`);
        doc.text(`Discount: ₹${item.Discount.toFixed(2)}`);
        doc.moveDown();
      });

      doc.end();

      stream.on("finish", () => {
        res.download(filepath, filename, () => {
          setTimeout(() => fs.unlink(filepath, () => {}), 5000);
        });
      });

      return;
    }

    return res.status(400).json({ message: "Invalid exportType" });
  } catch (err) {
    console.error("Download error:", err);
    res.status(500).json({ message: "Internal server error" });
  }
};

//------------------------------------------------------------------------------

const getEmployeePerformanceReport = async (req, res) => {
  try {
    const { startDate, endDate, filter, category, item } = req.query;

    let start, end;
    if (startDate && endDate) {
      start = new Date(startDate);
      end   = new Date(endDate);
    } else {
      start = new Date(); start.setHours(0,  0,  0,   0);
      end   = new Date(); end.setHours(23, 59, 59, 999);
    }

    // ── Single query on OrderItem; `food` boolean distinguishes food vs drink ──
    const performance = await OrderItem.findAll({
      attributes: [
        "userId",
        "food",                                                          // ← THE FIX
        [fn("COUNT", col("OrderItem.id")),             "totalOrders"],
        [fn("SUM",   col("OrderItem.price")),           "totalAmount"],
        [fn("AVG",   col("OrderItem.price")),           "avgOrderAmount"],
        [fn("SUM",   col("OrderItem.quantity")),        "totalQuantity"],
        [fn("SUM",   col("OrderItem.commissionTotal")), "commissionTotal"],
      ],
      where: {
        createdAt: { [Op.between]: [start, end] },
        userId:    { [Op.ne]: null },
      },
      include: [
        {
          model: User,
          as: "user",
          attributes: ["id", "name"],
        },
        {
          // Populated when food = true
          model: Menu,
          as: "menu",
          attributes: ["id", "name"],
          required: false,
          include: [
            { model: Category, as: "category", attributes: ["id", "name"] },
          ],
        },
        {
          // Populated when food = false
          model: DrinksMenu,
          as: "drink",
          attributes: ["id", "name"],
          required: false,
          include: [
            { model: DrinksCategory, as: "category", attributes: ["id", "name"] },
          ],
        },
      ],
      group: [
        "OrderItem.food",           // ← must be in GROUP BY
        "userId",
        "user.id",
        "menu.id",
        "menu->category.id",
        "drink.id",
        "drink->category.id",
      ],
      raw:  true,
      nest: true,
    });

    // ── Optional search filters ───────────────────────────────────────────────
    const catFilter  = (category || "").trim().toLowerCase();
    const itemFilter = (item     || "").trim().toLowerCase();

    const result = performance
      .map((p) => {
        // Use the `food` column — reliable, same approach as scoreboard
        const isFood =
          p.food === true || p.food === 1 ||
          p.food === "true" || p.food === "1";

        const itemName     = isFood ? p.menu?.name     : p.drink?.name;
        const categoryName = isFood
          ? p.menu?.category?.name
          : p.drink?.category?.name;

        // Apply search filters
        if (catFilter  && !(categoryName || "").toLowerCase().includes(catFilter))  return null;
        if (itemFilter && !(itemName     || "").toLowerCase().includes(itemFilter)) return null;

        return {
          employeeId:      p.user?.id   || p.userId,
          employeeName:    p.user?.name || "Unknown",
          categoryName:    categoryName || (isFood ? "Uncategorized" : "Drinks"),
          itemName:        itemName     || "Unknown",
          type:            isFood ? "food" : "drink",   // Flutter reads this
          totalOrders:     parseInt(p.totalOrders)   || 0,
          totalQuantity:   parseInt(p.totalQuantity) || 0,
          totalAmount:     parseFloat(p.totalAmount  || 0).toFixed(2),
          avgOrderAmount:  parseFloat(p.avgOrderAmount || 0).toFixed(2),
          commissionTotal: parseFloat(p.commissionTotal || 0).toFixed(2),
        };
      })
      .filter(Boolean);

    console.log(`Employee performance: ${result.length} rows`);
    return res.status(200).json({ data: result });

  } catch (error) {
    console.error("Error fetching employee performance:", error);
    return res.status(500).json({
      message: "Failed to fetch employee performance",
      error: error.message,
    });
  }
};


const downloadEmployeePerformanceReport = async (req, res) => {
  try {
    const { startDate, endDate, exportType = "xlsx", category, item } = req.query;

    let start, end;
    if (startDate && endDate) {
      start = new Date(startDate);
      end   = new Date(endDate);
    } else {
      start = new Date(); start.setHours(0,  0,  0,   0);
      end   = new Date(); end.setHours(23, 59, 59, 999);
    }

    // ── Same query as GET ─────────────────────────────────────────────────────
    const performance = await OrderItem.findAll({
      attributes: [
        "userId",
        "food",
        [fn("COUNT", col("OrderItem.id")),             "totalOrders"],
        [fn("SUM",   col("OrderItem.price")),           "totalAmount"],
        [fn("AVG",   col("OrderItem.price")),           "avgOrderAmount"],
        [fn("SUM",   col("OrderItem.quantity")),        "totalQuantity"],
        [fn("SUM",   col("OrderItem.commissionTotal")), "commissionTotal"],
      ],
      where: {
        createdAt: { [Op.between]: [start, end] },
        userId:    { [Op.ne]: null },
      },
      include: [
        { model: User,       as: "user",  attributes: ["id", "name"] },
        {
          model: Menu, as: "menu", attributes: ["id", "name"], required: false,
          include: [{ model: Category, as: "category", attributes: ["id", "name"] }],
        },
        {
          model: DrinksMenu, as: "drink", attributes: ["id", "name"], required: false,
          include: [{ model: DrinksCategory, as: "category", attributes: ["id", "name"] }],
        },
      ],
      group: [
        "OrderItem.food", "userId", "user.id",
        "menu.id", "menu->category.id",
        "drink.id", "drink->category.id",
      ],
      raw:  true,
      nest: true,
    });

    // ── Build export rows ─────────────────────────────────────────────────────
    const catFilter  = (category || "").trim().toLowerCase();
    const itemFilter = (item     || "").trim().toLowerCase();

    const rows = performance
      .map((p) => {
        const isFood =
          p.food === true || p.food === 1 ||
          p.food === "true" || p.food === "1";

        const iName = isFood ? p.menu?.name : p.drink?.name;
        const cName = isFood ? p.menu?.category?.name : p.drink?.category?.name;

        if (catFilter  && !(cName  || "").toLowerCase().includes(catFilter))  return null;
        if (itemFilter && !(iName  || "").toLowerCase().includes(itemFilter)) return null;

        return {
          Employee:        p.user?.name || "Unknown",
          Type:            isFood ? "Food" : "Drink",
          Category:        cName  || (isFood ? "Uncategorized" : "Drinks"),
          Item:            iName  || "Unknown",
          Orders:          parseInt(p.totalOrders)   || 0,
          Qty:             parseInt(p.totalQuantity) || 0,
          "Total (₹)":    parseFloat(p.totalAmount   || 0).toFixed(2),
          "Avg (₹)":      parseFloat(p.avgOrderAmount || 0).toFixed(2),
          "Incentive (₹)":parseFloat(p.commissionTotal || 0).toFixed(2),
        };
      })
      .filter(Boolean);

    const startStr = startDate ? startDate.slice(0, 10) : new Date(start).toISOString().slice(0, 10);
    const endStr   = endDate   ? endDate.slice(0, 10)   : new Date(end).toISOString().slice(0, 10);
    const filename  = `EmployeePerformance_${startStr}_${endStr}`;

    // ── XLSX ──────────────────────────────────────────────────────────────────
    if (exportType === "xlsx") {
      const workbook  = new ExcelJS.Workbook();
      const worksheet = workbook.addWorksheet("Employee Performance");

      const colKeys = rows.length > 0 ? Object.keys(rows[0]) : [
        "Employee","Type","Category","Item","Orders","Qty","Total (₹)","Avg (₹)","Incentive (₹)"
      ];

      worksheet.columns = colKeys.map((key) => ({
        header: key,
        key,
        width: Math.max(key.length + 4, 16),
      }));

      // Header
      const hRow = worksheet.getRow(1);
      hRow.font   = { bold: true, color: { argb: "FFFFFFFF" } };
      hRow.fill   = { type: "pattern", pattern: "solid", fgColor: { argb: "FF5E35B1" } };
      hRow.height = 20;

      rows.forEach((row) => {
        const added  = worksheet.addRow(row);
        const isFood = row["Type"] === "Food";

        added.eachCell((cell) => {
          cell.fill = {
            type: "pattern", pattern: "solid",
            fgColor: { argb: isFood ? "FFFFF8F0" : "FFF0F7FF" },
          };
        });
        added.getCell("Type").fill = {
          type: "pattern", pattern: "solid",
          fgColor: { argb: isFood ? "FFFFF3E0" : "FFE3F2FD" },
        };
        added.getCell("Type").font = {
          bold: true,
          color: { argb: isFood ? "FF8E5300" : "FF0D47A1" },
        };
        added.getCell("Incentive (₹)").font = { bold: true, color: { argb: "FF2E7D32" } };
      });

      worksheet.views = [{ state: "frozen", ySplit: 1 }];

      res.setHeader("Content-Type",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
      res.setHeader("Content-Disposition",
        `attachment; filename="${filename}.xlsx"`);
      await workbook.xlsx.write(res);
      return res.end();
    }

    // ── PDF ───────────────────────────────────────────────────────────────────
    if (exportType === "pdf") {
      const doc = new PDFDocument({ margin: 28, size: "A4", layout: "landscape" });
      res.setHeader("Content-Type", "application/pdf");
      res.setHeader("Content-Disposition", `attachment; filename="${filename}.pdf"`);
      doc.pipe(res);

      doc.fontSize(14).font("Helvetica-Bold")
         .text("Employee Performance Report", { align: "center" });
      doc.moveDown(0.25);
      doc.fontSize(9).font("Helvetica").fillColor("#555")
         .text(`Period: ${startStr}  →  ${endStr}   |   Total rows: ${rows.length}`, { align: "center" });
      doc.fillColor("black").moveDown(0.6);

      const PDF_COLS = [
        { label: "Employee",  width: 100, key: "Employee"        },
        { label: "Type",      width:  44, key: "Type"            },
        { label: "Category",  width: 105, key: "Category"        },
        { label: "Item",      width: 150, key: "Item"            },
        { label: "Orders",    width:  46, key: "Orders"          },
        { label: "Qty",       width:  36, key: "Qty"             },
        { label: "Total (₹)", width:  80, key: "Total (₹)"      },
        { label: "Avg (₹)",   width:  76, key: "Avg (₹)"        },
        { label: "Incentive", width:  76, key: "Incentive (₹)"  },
      ];
      const ROW_H  = 16;
      const START_X = 28;
      const totalW  = PDF_COLS.reduce((s, c) => s + c.width, 0);

      const drawHLine = (y) =>
        doc.moveTo(START_X, y).lineTo(START_X + totalW, y)
           .strokeColor("#CCCCCC").lineWidth(0.4).stroke();

      const drawRow = (values, y, { bgColor, bold, fontSize = 7.5 } = {}) => {
        if (bgColor) doc.save().rect(START_X, y, totalW, ROW_H).fill(bgColor).restore();
        doc.font(bold ? "Helvetica-Bold" : "Helvetica").fontSize(fontSize).fillColor("black");
        let x = START_X;
        PDF_COLS.forEach((col, i) => {
          doc.text(String(values[i] ?? "").slice(0, 32), x + 2, y + 4, {
            width: col.width - 4, lineBreak: false, ellipsis: true,
          });
          x += col.width;
        });
        drawHLine(y + ROW_H);
      };

      const printHeader = (y) => {
        drawRow(PDF_COLS.map((c) => c.label), y, { bgColor: "#D1C4E9", bold: true, fontSize: 8 });
        return y + ROW_H;
      };

      let curY = printHeader(doc.y);

      rows.forEach((row, idx) => {
        if (curY > 520) { doc.addPage({ layout: "landscape" }); curY = printHeader(28); }
        const isFood = row["Type"] === "Food";
        const bg     = idx % 2 === 0 ? (isFood ? "#FFF8F0" : "#F0F7FF") : null;
        drawRow(PDF_COLS.map((c) => row[c.key]), curY, { bgColor: bg });
        curY += ROW_H;
      });

      doc.end();
      return;
    }

    return res.status(400).json({ message: "Unsupported exportType. Use: xlsx | pdf" });

  } catch (error) {
    console.error("Error downloading employee performance:", error);
    return res.status(500).json({
      message: "Failed to download employee performance",
      error: error.message,
    });
  }
};


//-------------------------------------------------------------------------------

const getInventoryItems = async (req, res) => {
  try {
    const items = await Inventory.findAll();

    const processed = items.map((item) => {
      let status = "normal";
      if (item.quantity === 0) status = "critical";
      else if (item.quantity <= item.minimum_quantity) status = "warning";

      return {
        id: item.id,
        itemName: item.itemName,
        quantity: item.quantity,
        minimum_quantity: item.minimum_quantity,
        unit: item.unit,
        status,
      };
    });

    // Sort: critical (0 qty), warning, then normal
    processed.sort((a, b) => {
      const priority = { critical: 0, warning: 1, normal: 2 };
      return priority[a.status] - priority[b.status];
    });

    res.status(200).json({ message: "Inventory fetched", data: processed });
  } catch (err) {
    console.error("Error fetching inventory:", err);
    res
      .status(500)
      .json({ message: "Failed to fetch inventory", error: err.message });
  }
};

const downloadInventoryItems = async (req, res) => {
  try {
    const items = await Inventory.findAll();

    const processed = items.map((item) => {
      let status = "normal";
      if (item.quantity === 0) status = "critical";
      else if (item.quantity <= item.minimum_quantity) status = "warning";

      return {
        itemName: item.itemName,
        quantity: item.quantity,
        minimum_quantity: item.minimum_quantity,
        unit: item.unit,
        status,
      };
    });

    // Sort
    processed.sort((a, b) => {
      const priority = { critical: 0, warning: 1, normal: 2 };
      return priority[a.status] - priority[b.status];
    });

    const { exportType = "excel" } = req.query;
    const filename = `inventory_report_${
      new Date().toISOString().split("T")[0]
    }`;

    // CSV Export
    if (exportType === "csv") {
      const parser = new Parser();
      const csv = parser.parse(processed);
      res.setHeader("Content-Type", "text/csv");
      res.setHeader(
        "Content-Disposition",
        `attachment; filename=${filename}.csv`
      );
      return res.send(csv);
    }

    // Excel Export
    if (exportType === "excel" || exportType === "xlsx") {
      const workbook = new ExcelJS.Workbook();
      const sheet = workbook.addWorksheet("Inventory");

      sheet.columns = [
        { header: "Item Name", key: "itemName", width: 30 },
        { header: "Quantity", key: "quantity", width: 15 },
        { header: "Min Quantity", key: "minimum_quantity", width: 15 },
        { header: "Unit", key: "unit", width: 10 },
      ];

      processed.forEach((item) => {
        const row = sheet.addRow(item);

        if (item.status === "critical") {
          row.eachCell((cell) => {
            cell.fill = {
              type: "pattern",
              pattern: "solid",
              fgColor: { argb: "FFFFCCCC" }, // Light red
            };
          });
        } else if (item.status === "warning") {
          row.eachCell((cell) => {
            cell.fill = {
              type: "pattern",
              pattern: "solid",
              fgColor: { argb: "FFFFFF99" }, // Light yellow
            };
          });
        }
      });

      sheet.getRow(1).font = { bold: true };

      res.setHeader(
        "Content-Type",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      );
      res.setHeader(
        "Content-Disposition",
        `attachment; filename=${filename}.xlsx`
      );

      await workbook.xlsx.write(res);
      return res.end();
    }

    // PDF Export
    if (exportType === "pdf") {
      const doc = new PDFDocument({ margin: 30, size: "A4" });
      const buffers = [];

      doc.on("data", buffers.push.bind(buffers));
      doc.on("end", () => {
        const pdfData = Buffer.concat(buffers);
        res.setHeader("Content-Type", "application/pdf");
        res.setHeader(
          "Content-Disposition",
          `attachment; filename=${filename}.pdf`
        );
        res.send(pdfData);
      });

      doc.fontSize(16).text("Inventory Report", { align: "center" });
      doc.moveDown();

      processed.forEach((item) => {
        let line = `Item: ${item.itemName}, Qty: ${item.quantity}, Min: ${item.minimum_quantity}, Unit: ${item.unit}`;
        if (item.status === "critical") {
          doc.fillColor("red").text(line);
        } else if (item.status === "warning") {
          doc.fillColor("orange").text(line);
        } else {
          doc.fillColor("black").text(line);
        }
      });

      doc.end();
      return;
    }

    return res.status(400).json({ message: "Unsupported export type" });
  } catch (err) {
    console.error("Download inventory error:", err);
    res
      .status(500)
      .json({ message: "Failed to download inventory", error: err.message });
  }
};

//---------------------------------------------------------

const getDrinksInventoryItems = async (req, res) => {
  try {
    const items = await DrinksInventory.findAll();

    const processed = items.map((item) => {
      let status = "normal";
      if (item.quantity === 0) status = "critical";
      else if (item.quantity <= item.minimum_quantity) status = "warning";

      return {
        id: item.id,
        itemName: item.itemName,
        quantity: item.quantity,
        minimum_quantity: item.minimumQuantity,
        unit: item.unit,
        status,
      };
    });

    // Sort: critical (0 qty), warning, then normal
    processed.sort((a, b) => {
      const priority = { critical: 0, warning: 1, normal: 2 };
      return priority[a.status] - priority[b.status];
    });

    res
      .status(200)
      .json({ message: "Drinks Inventory fetched", data: processed });
  } catch (err) {
    console.error("Error fetching drinks inventory:", err);
    res.status(500).json({
      message: "Failed to fetch drinks inventory",
      error: err.message,
    });
  }
};

const downloadDrinksInventoryItems = async (req, res) => {
  try {
    const items = await DrinksInventory.findAll();

    const processed = items.map((item) => {
      let status = "normal";
      if (item.quantity === 0) status = "critical";
      else if (item.quantity <= item.minimumQuantity) status = "warning";

      return {
        itemName: item.itemName,
        quantity: item.quantity,
        minimum_quantity: item.minimumQuantity,
        unit: item.unit,
        status,
      };
    });

    // Sort
    processed.sort((a, b) => {
      const priority = { critical: 0, warning: 1, normal: 2 };
      return priority[a.status] - priority[b.status];
    });

    const { exportType = "excel" } = req.query;
    const filename = `drinks_inventory_report_${
      new Date().toISOString().split("T")[0]
    }`;

    // CSV Export
    if (exportType === "csv") {
      const parser = new Parser();
      const csv = parser.parse(processed);
      res.setHeader("Content-Type", "text/csv");
      res.setHeader(
        "Content-Disposition",
        `attachment; filename=${filename}.csv`
      );
      return res.send(csv);
    }

    // Excel Export
    if (exportType === "excel" || exportType === "xlsx") {
      const workbook = new ExcelJS.Workbook();
      const sheet = workbook.addWorksheet("Drinks_Inventory");

      sheet.columns = [
        { header: "Item Name", key: "itemName", width: 30 },
        { header: "Quantity", key: "quantity", width: 15 },
        { header: "Min Quantity", key: "minimum_quantity", width: 15 },
        { header: "Unit", key: "unit", width: 10 },
      ];

      processed.forEach((item) => {
        const row = sheet.addRow(item);

        if (item.status === "critical") {
          row.eachCell((cell) => {
            cell.fill = {
              type: "pattern",
              pattern: "solid",
              fgColor: { argb: "FFFFCCCC" }, // Light red
            };
          });
        } else if (item.status === "warning") {
          row.eachCell((cell) => {
            cell.fill = {
              type: "pattern",
              pattern: "solid",
              fgColor: { argb: "FFFFFF99" }, // Light yellow
            };
          });
        }
      });

      sheet.getRow(1).font = { bold: true };

      res.setHeader(
        "Content-Type",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      );
      res.setHeader(
        "Content-Disposition",
        `attachment; filename=${filename}.xlsx`
      );

      await workbook.xlsx.write(res);
      return res.end();
    }

    // PDF Export
    if (exportType === "pdf") {
      const doc = new PDFDocument({ margin: 30, size: "A4" });
      const buffers = [];

      doc.on("data", buffers.push.bind(buffers));
      doc.on("end", () => {
        const pdfData = Buffer.concat(buffers);
        res.setHeader("Content-Type", "application/pdf");
        res.setHeader(
          "Content-Disposition",
          `attachment; filename=${filename}.pdf`
        );
        res.send(pdfData);
      });

      doc.fontSize(16).text("Drinks Inventory Report", { align: "center" });
      doc.moveDown();

      processed.forEach((item) => {
        let line = `Item: ${item.itemName}, Qty: ${item.quantity}, Min: ${item.minimumQuantity}, Unit: ${item.unit}`;
        if (item.status === "critical") {
          doc.fillColor("red").text(line);
        } else if (item.status === "warning") {
          doc.fillColor("orange").text(line);
        } else {
          doc.fillColor("black").text(line);
        }
      });

      doc.end();
      return;
    }

    return res.status(400).json({ message: "Unsupported export type" });
  } catch (err) {
    console.error("Download drinks inventory error:", err);
    res.status(500).json({
      message: "Failed to download drinks inventory",
      error: err.message,
    });
  }
};

//---------------------------------------------------------

const IST_OFFSET = 5.5 * 60 * 60000;
const getDayWiseReport = async (req, res) => {
  try {
    const startDateStr = req.query.startDate;
    const endDateStr = req.query.endDate;

    if (!startDateStr || !endDateStr) {
      return res
        .status(400)
        .json({ error: "startDate and endDate are required" });
    }

    const startIST = new Date(`${startDateStr}T03:05:00+05:30`);
    const endIST = new Date(`${endDateStr}T03:05:00+05:30`);
    const startUTC = new Date(startIST.getTime() - IST_OFFSET);
    const endUTC = new Date(endIST.getTime() + 24 * 60 * 60000 - IST_OFFSET);

    const bills = await Bill.findAll({
      where: {
        time_of_bill: {
          [Op.between]: [startUTC, endUTC],
        },
      },
      order: [["id", "ASC"]],
    });

    if (!bills.length) {
      return res.json({
        message: "No bills found for selected range",
        total: null,
      });
    }

    const summary = bills.reduce(
      (acc, bill) => {
        acc.count++;
        acc.subTotal += bill.total_amount || 0;
        acc.discount += bill.discount_amount || 0;
        acc.serviceCharges += bill.service_charge_amount || 0;

        const tax =
          (bill.final_amount || 0) -
          (bill.total_amount || 0) -
          (bill.service_charge_amount || 0);
        acc.tax += tax;
        acc.roundOff += bill.round_off || 0;
        acc.grandTotal += bill.final_amount || 0;
        acc.netSales +=
          (bill.final_amount || 0) -
          (bill.discount_amount || 0) -
          (bill.service_charge_amount || 0);

        if (bill.payment_method === "cash") acc.cash += bill.final_amount || 0;
        if (bill.payment_method === "card") acc.card += bill.final_amount || 0;
        if (bill.payment_method === "upi") acc.upi += bill.final_amount || 0;

        return acc;
      },
      {
        count: 0,
        subTotal: 0,
        discount: 0,
        serviceCharges: 0,
        tax: 0,
        roundOff: 0,
        grandTotal: 0,
        netSales: 0,
        cash: 0,
        card: 0,
        upi: 0,
      }
    );

    return res.json({
      total: {
        invoiceRange: {
          start: bills[0].id,
          end: bills[bills.length - 1].id,
        },
        orderCount: summary.count.toString(),
        subTotal: summary.subTotal.toFixed(2),
        discount: summary.discount.toFixed(2),
        serviceCharges: summary.serviceCharges.toFixed(2),
        tax: summary.tax.toFixed(2),
        roundOff: summary.roundOff.toFixed(2),
        grandTotal: summary.grandTotal.toFixed(2),
        netSales: summary.netSales.toFixed(2),
        cash: summary.cash.toFixed(2),
        card: summary.card.toFixed(2),
        upi: summary.upi.toFixed(2),
      },
    });
  } catch (err) {
    console.error("❌ Error generating total day-wise report:", err);
    res.status(500).json({ error: "Internal server error" });
  }
};

const downloadDayWiseReport = async (req, res) => {
  try {
    const startDateStr = req.query.startDate;
    const endDateStr = req.query.endDate;
    const { exportType = "excel" } = req.query;

    if (!startDateStr || !endDateStr) {
      return res
        .status(400)
        .json({ error: "startDate and endDate are required in query" });
    }

    const startIST = new Date(`${startDateStr}T03:05:00+05:30`);
    const endIST = new Date(`${endDateStr}T03:05:00+05:30`);
    const startUTC = new Date(startIST.getTime() - IST_OFFSET);
    const endUTC = new Date(endIST.getTime() + 24 * 60 * 60000 - IST_OFFSET);

    const bills = await Bill.findAll({
      where: {
        time_of_bill: {
          [Op.between]: [startUTC, endUTC],
        },
      },
      order: [["id", "ASC"]],
    });

    if (!bills.length) {
      return res
        .status(404)
        .json({ message: "No bills found in selected range" });
    }

    const summary = bills.reduce(
      (acc, bill) => {
        acc.count++;
        acc.subTotal += bill.total_amount || 0;
        acc.discount += bill.discount_amount || 0;
        acc.serviceCharges += bill.service_charge_amount || 0;
        const tax =
          (bill.final_amount || 0) -
          (bill.total_amount || 0) -
          (bill.service_charge_amount || 0);
        acc.tax += tax;
        acc.roundOff += bill.round_off || 0;
        acc.grandTotal += bill.final_amount || 0;
        acc.netSales +=
          (bill.final_amount || 0) -
          (bill.discount_amount || 0) -
          (bill.service_charge_amount || 0);

        if (bill.payment_method === "cash") acc.cash += bill.final_amount || 0;
        if (bill.payment_method === "card") acc.card += bill.final_amount || 0;
        if (bill.payment_method === "upi") acc.upi += bill.final_amount || 0;

        return acc;
      },
      {
        count: 0,
        subTotal: 0,
        discount: 0,
        serviceCharges: 0,
        tax: 0,
        roundOff: 0,
        grandTotal: 0,
        netSales: 0,
        cash: 0,
        card: 0,
        upi: 0,
      }
    );

    const processed = [
      {
        "Date Range": `${startDateStr} to ${endDateStr}`,
        "Invoice Range": `${bills[0].id} - ${bills[bills.length - 1].id}`,
        "Total Orders": summary.count,
        "Sub Total": summary.subTotal.toFixed(2),
        Discount: summary.discount.toFixed(2),
        "Service Charges": summary.serviceCharges.toFixed(2),
        Tax: summary.tax.toFixed(2),
        "Round Off": summary.roundOff.toFixed(2),
        "Grand Total": summary.grandTotal.toFixed(2),
        "Net Sales": summary.netSales.toFixed(2),
        Cash: summary.cash.toFixed(2),
        Card: summary.card.toFixed(2),
        UPI: summary.upi.toFixed(2),
      },
    ];

    const filename = `daywise_report_${startDateStr}_to_${endDateStr}`;

    // === CSV Export ===
    if (exportType === "csv") {
      const parser = new Parser();
      const csv = parser.parse(processed);
      res.setHeader("Content-Type", "text/csv");
      res.setHeader(
        "Content-Disposition",
        `attachment; filename=${filename}.csv`
      );
      return res.send(csv);
    }

    // === Excel Export ===
    if (exportType === "excel" || exportType === "xlsx") {
      const workbook = new ExcelJS.Workbook();
      const sheet = workbook.addWorksheet("DayWise_Report");

      sheet.columns = Object.keys(processed[0]).map((key) => ({
        header: key,
        key,
        width: 20,
      }));

      processed.forEach((row) => sheet.addRow(row));
      sheet.getRow(1).font = { bold: true };

      res.setHeader(
        "Content-Type",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      );
      res.setHeader(
        "Content-Disposition",
        `attachment; filename=${filename}.xlsx`
      );

      await workbook.xlsx.write(res);
      return res.end();
    }

    // === PDF Export ===
    if (exportType === "pdf") {
      const doc = new PDFDocument({ margin: 30, size: "A4" });
      const buffers = [];

      doc.on("data", buffers.push.bind(buffers));
      doc.on("end", () => {
        const pdfData = Buffer.concat(buffers);
        res.setHeader("Content-Type", "application/pdf");
        res.setHeader(
          "Content-Disposition",
          `attachment; filename=${filename}.pdf`
        );
        res.send(pdfData);
      });

      doc
        .fontSize(16)
        .text("Day Wise Summary Report", { align: "center" })
        .moveDown();

      Object.entries(processed[0]).forEach(([key, value]) => {
        doc.fontSize(11).text(`${key}: ${value}`);
      });

      doc.end();
      return;
    }

    return res.status(400).json({ message: "Unsupported export type" });
  } catch (err) {
    console.error("❌ Error exporting day-wise report:", err);
    res
      .status(500)
      .json({ message: "Failed to download report", error: err.message });
  }
};

//---------------------------------------------------------

// controllers/masterReportController.js

const generateMasterReport = async (req, res) => {
  try {
    const { startDate, endDate } = req.query;
    if (!startDate || !endDate) {
      return res
        .status(400)
        .json({ message: "startDate and endDate are required" });
    }

    const workbook = new ExcelJS.Workbook();

    // ===== 1. Day Wise Report =====
    const start = new Date(`${startDate}T00:00:00`);
    const end = new Date(`${endDate}T23:59:59`);
    const bills = await Bill.findAll({
      where: { time_of_bill: { [Op.between]: [start, end] } },
      order: [["id", "ASC"]],
    });
    const summary = bills.reduce(
      (acc, bill) => {
        acc.count++;
        acc.subTotal += bill.total_amount || 0;
        acc.discount += bill.discount_amount || 0;
        acc.serviceCharges += bill.service_charge_amount || 0;
        acc.tax +=
          (bill.final_amount || 0) -
          (bill.total_amount || 0) -
          (bill.service_charge_amount || 0);
        acc.roundOff += bill.round_off || 0;
        acc.grandTotal += bill.final_amount || 0;
        acc.netSales +=
          (bill.final_amount || 0) -
          (bill.discount_amount || 0) -
          (bill.service_charge_amount || 0);
        if (bill.payment_method === "cash") acc.cash += bill.final_amount || 0;
        if (bill.payment_method === "card") acc.card += bill.final_amount || 0;
        if (bill.payment_method === "upi") acc.upi += bill.final_amount || 0;
        return acc;
      },
      {
        count: 0,
        subTotal: 0,
        discount: 0,
        serviceCharges: 0,
        tax: 0,
        roundOff: 0,
        grandTotal: 0,
        netSales: 0,
        cash: 0,
        card: 0,
        upi: 0,
      }
    );
    const sheet1 = workbook.addWorksheet("DayWise_Report");
    sheet1.addRow(["Date Range", `${startDate} to ${endDate}`]);
    sheet1.addRow([
      "Invoice Range",
      bills.length ? `${bills[0].id} - ${bills[bills.length - 1].id}` : "N/A",
    ]);
    sheet1.addRow(["Total Orders", summary.count]);
    sheet1.addRow(["Sub Total", summary.subTotal]);
    sheet1.addRow(["Discount", summary.discount]);
    sheet1.addRow(["Service Charges", summary.serviceCharges]);
    sheet1.addRow(["Tax", summary.tax]);
    sheet1.addRow(["Round Off", summary.roundOff]);
    sheet1.addRow(["Grand Total", summary.grandTotal]);
    sheet1.addRow(["Net Sales", summary.netSales]);
    sheet1.addRow(["Cash", summary.cash]);
    sheet1.addRow(["Card", summary.card]);
    sheet1.addRow(["UPI", summary.upi]);

    // ===== 2. Item Wise Report =====
    const itemData = await buildGroupedItemWiseData({
      startDate,
      endDate,
      foodType: "all",
    });
    const sheet2 = workbook.addWorksheet("ItemWise_Report");
    sheet2.columns = [
      { header: "Category", key: "categoryName", width: 20 },
      { header: "Item", key: "itemName", width: 25 },
      { header: "Qty", key: "totalQuantity", width: 10 },
      { header: "Price/Item", key: "pricePerItem", width: 15 },
      { header: "Total Amount", key: "totalAmount", width: 15 },
    ];
    itemData.forEach((row) => sheet2.addRow(row));

    // ===== 3. Invoice Summary Report =====
    const invoiceSummary = await buildInvoiceSummary(startDate, endDate);
    const sheet3 = workbook.addWorksheet("Invoice_Summary");
    Object.entries(invoiceSummary).forEach(([key, val]) => {
      sheet3.addRow([key, val]);
    });

    // ===== 4. Sub Order Wise Report =====
    const sectionMap = {};
    for (const bill of bills) {
      const table = await bill.getTable({ include: ["section"] });
      const sectionName = table?.section?.name || "Unknown";
      if (!sectionMap[sectionName])
        sectionMap[sectionName] = {
          Section: sectionName,
          BillCount: 0,
          Amount: 0,
          Discount: 0,
        };
      sectionMap[sectionName].BillCount += 1;
      sectionMap[sectionName].Amount += bill.total_amount || 0;
      sectionMap[sectionName].Discount += bill.discount_amount || 0;
    }
    const sheet4 = workbook.addWorksheet("SubOrder_Report");
    sheet4.columns = [
      { header: "Section", key: "Section", width: 20 },
      { header: "Bill Count", key: "BillCount", width: 15 },
      { header: "Amount", key: "Amount", width: 15 },
      { header: "Discount", key: "Discount", width: 15 },
    ];
    Object.values(sectionMap).forEach((row) => sheet4.addRow(row));

    // ===== 5. Employee Performance =====
    const employeeData = await OrderItem.findAll({
      attributes: [
        "userId",
        [fn("COUNT", col("OrderItem.id")), "totalOrders"],
        [fn("SUM", col("OrderItem.price")), "totalAmount"],
        [fn("AVG", col("OrderItem.price")), "avgOrderAmount"],
      ],
      where: {
        createdAt: { [Op.between]: [start, end] },
        userId: { [Op.ne]: null },
      },
      include: [{ model: User, as: "user", attributes: ["id", "name"] }],
      group: ["userId", "user.id"],
      raw: true,
      nest: true,
    });
    const sheet5 = workbook.addWorksheet("Employee_Performance");
    sheet5.columns = [
      { header: "Employee ID", key: "userId", width: 15 },
      { header: "Name", key: "user.name", width: 20 },
      { header: "Total Orders", key: "totalOrders", width: 15 },
      { header: "Total Amount", key: "totalAmount", width: 15 },
      { header: "Average Order", key: "avgOrderAmount", width: 15 },
    ];
    employeeData.forEach((row) => sheet5.addRow(row));

    // ===== 6. Inventory Report =====
    const inventoryItems = await Inventory.findAll();
    const sheet6 = workbook.addWorksheet("Inventory");
    sheet6.columns = [
      { header: "Item Name", key: "itemName", width: 25 },
      { header: "Quantity", key: "quantity", width: 15 },
      { header: "Min Qty", key: "minimum_quantity", width: 15 },
      { header: "Unit", key: "unit", width: 10 },
    ];
    inventoryItems.forEach((item) => sheet6.addRow(item.dataValues));

    // ===== 7. Drinks Inventory =====
    const drinksItems = await DrinksInventory.findAll();
    const sheet7 = workbook.addWorksheet("Drinks_Inventory");
    sheet7.columns = sheet6.columns;
    drinksItems.forEach((item) => sheet7.addRow(item.dataValues));

    // ===== Finalize Export =====
    const filename = `master_report_${startDate}_to_${endDate}.xlsx`;
    res.setHeader(
      "Content-Type",
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    );
    res.setHeader("Content-Disposition", `attachment; filename=${filename}`);
    await workbook.xlsx.write(res);
    res.end();
  } catch (error) {
    console.error("Error generating master report:", error);
    res.status(500).json({
      message: "Failed to generate master report",
      error: error.message,
    });
  }
};

const testDaySummary = async (req, res) => {
  try {
    // --- Fixed date: Yesterday in IST ---
    const nowUTC = new Date(); // current UTC
    const nowIST = new Date(nowUTC.getTime() + IST_OFFSET * 60000);

    // yesterday 00:00:00 IST
    const startIST = new Date(nowIST);
    startIST.setDate(startIST.getDate() - 1);
    startIST.setHours(0, 0, 0, 0);

    // end of yesterday 23:59:59 IST
    const endIST = new Date(startIST);
    endIST.setHours(23, 59, 59, 999);

    // convert to UTC for DB queries
    const startUTC = new Date(startIST.getTime() - IST_OFFSET * 60000);
    const endUTC = new Date(endIST.getTime() - IST_OFFSET * 60000);

    const summaryDate = startIST.toISOString().split("T")[0];

    // --- Fetch invoice summary ---
    const invoiceData = await Bill.findAll({
      where: { time_of_bill: { [Op.between]: [startUTC, endUTC] } },
      attributes: [
        [fn("COUNT", col("id")), "totalBills"],
        [fn("MIN", col("id")), "firstBillId"],
        [fn("MAX", col("id")), "lastBillId"],
      ],
      raw: true,
    });
    const { totalBills, firstBillId, lastBillId } = invoiceData[0] || {};

    // --- Fetch bills for detailed summary ---
    const bills = await Bill.findAll({
      where: { time_of_bill: { [Op.between]: [startUTC, endUTC] } },
    });
    // console.log("Test: ", JSON.stringify(bills));
    if (!bills.length) {
      console.log(`⚠️ No bills for ${summaryDate}.`);
      return res.status(200).json({
        message: `No bills found for ${summaryDate}`,
        date: summaryDate,
        orderCount: 0,
      });
    }

    // --- Aggregate bills ---
    const summary = bills.reduce(
      (acc, bill) => {
        acc.count++;
        acc.subTotal += bill.total_amount || 0;
        acc.discount += bill.discount_amount || 0;
        acc.serviceCharges += bill.service_charge_amount || 0;
        acc.tax += bill.tax_amount || 0;
        acc.roundOff += bill.round_off || 0;
        acc.grandTotal += bill.final_amount || 0;
        acc.netSales += bill.final_amount || 0;

        // ✅ Sum across payment_breakdown dynamically
        if (bill.payment_breakdown) {
          Object.entries(bill.payment_breakdown).forEach(([method, amount]) => {
            if (acc.paymentMethods[method] !== undefined) {
              acc.paymentMethods[method] += amount || 0;
            } else {
              // in case new method like 'wallet' comes in
              acc.paymentMethods[method] = amount || 0;
            }
          });
        }

        return acc;
      },
      {
        count: 0,
        subTotal: 0,
        discount: 0,
        serviceCharges: 0,
        tax: 0,
        roundOff: 0,
        grandTotal: 0,
        netSales: 0,
        paymentMethods: { cash: 0, card: 0, upi: 0 },
      }
    );

    console.log("Payment breakdown:", summary.paymentMethods);

    // --- Compare with previous day's summary ---
    const previousStartIST = new Date(startIST.getTime() - 24 * 60 * 60000);
    const previousSummaryDate = previousStartIST.toISOString().split("T")[0];

    const previousSummary = await DaySummary.findOne({
      where: { date: previousSummaryDate },
    });

    let grandTotalPercentType = null;
    let grandTotalPercent = null;

    if (previousSummary && previousSummary.grandTotal) {
      const prevGrandTotal = parseFloat(previousSummary.grandTotal);
      const currGrandTotal = summary.grandTotal;

      const diff = currGrandTotal - prevGrandTotal;

      grandTotalPercentType = diff < 0 ? "negative" : "positive";

      if (prevGrandTotal !== 0) {
        grandTotalPercent = ((Math.abs(diff) / prevGrandTotal) * 100).toFixed(
          2
        );
      }
    }

    // --- (Optional) Upsert into DB ---
    // await DaySummary.upsert({ ... })

    const result = {
      date: summaryDate,
      orderCount: summary.count,
      subTotal: summary.subTotal.toFixed(2),
      discount: summary.discount.toFixed(2),
      serviceCharges: summary.serviceCharges.toFixed(2),
      tax: summary.tax.toFixed(2),
      roundOff: summary.roundOff.toFixed(2),
      grandTotal: summary.grandTotal.toFixed(2),
      netSales: summary.netSales.toFixed(2),
      cash: summary.paymentMethods.cash.toFixed(2),
      card: summary.paymentMethods.card.toFixed(2),
      upi: summary.paymentMethods.upi.toFixed(2),
      invoices: `${firstBillId || ""}-${lastBillId || ""}`,
      grandTotalPercentType,
      grandTotalPercent,
    };

    res.status(200).json(result);
    console.log(`✅ Day-End Summary generated for ${summaryDate}`);
  } catch (err) {
    console.error("❌ Error generating day-end summary:", err);
    res.status(500).json({ error: err.message || "Internal server error" });
  }
};


const buildCancelledOrderRows = async ({
  startDate,
  endDate,
  foodType,
  isApprovedFilter, // 'true' | 'false' | undefined (= all rows)
}) => {
  const { startMoment, endMoment } = buildWindowFromQuery({ startDate, endDate });

  const baseWhere = {
    createdAt: { [Op.between]: [startMoment.toDate(), endMoment.toDate()] },
  };
  if (isApprovedFilter === "true")  baseWhere.isApproved = true;
  if (isApprovedFilter === "false") baseWhere.isApproved = false;

  // ---- Food cancelled orders ----
  const cancelledFood =
    foodType !== "drink"
      ? await CanceledFoodOrder.findAll({
          where: baseWhere,
          include: [
            {
              model: Menu,
              as: "menu",
              attributes: ["id", "name", "price"],
              required: false, // LEFT JOIN — custom items have no menuId
              include: [
                { model: Category, as: "category", attributes: ["id", "name"] },
              ],
            },
            { model: User, as: "user",          attributes: ["id", "name"] },
            { model: User, as: "deletedByUser", attributes: ["id", "name"] },
          ],
          order: [["createdAt", "DESC"]],
        })
      : [];

  // ---- Drink cancelled orders ----
  const cancelledDrinks =
    foodType !== "food"
      ? await CanceledDrinkOrder.findAll({
          where: baseWhere,
          include: [
            {
              model: DrinksMenu,
              as: "menu",
              attributes: ["id", "name", "price", "applyVAT"],
              required: false,
              include: [
                { model: DrinksCategory, as: "category", attributes: ["id", "name"] },
              ],
            },
            { model: User, as: "user",          attributes: ["id", "name"] },
            { model: User, as: "deletedByUser", attributes: ["id", "name"] },
          ],
          order: [["createdAt", "DESC"]],
        })
      : [];

  // ---- Map food rows ----
  const foodRows = cancelledFood.map((order) => {
    const isCustom = isTruthy(order.is_custom);

    // Item name resolution priority:
    // 1. Custom item  → customName field
    // 2. Regular item → Menu.name (from join)
    // 3. Fallback     → remarks (waiter typed name at cancel time)
    const itemName = isCustom
      ? (order.customName || order.remarks || "Open Food")
      : (order.menu?.name || order.remarks || "Unknown Item");

    const category = isCustom
      ? "Open Food"
      : (order.menu?.category?.name || "Food");

    const pricePerItem = toNumber(order.menu?.price ?? 0);
    const qty          = toNumber(order.count);
    const totalAmount  = pricePerItem * qty;

    // 5% GST split as CGST 2.5% + SGST 2.5%
    const cgst        = totalAmount * 0.025;
    const sgst        = totalAmount * 0.025;
    const tax         = cgst + sgst;
    const grossAmount = totalAmount + tax;

    return {
      type:          "food",
      category,
      itemName,
      // restaurent_table_number is the real table; section_number is the section
      tableNumber:   order.restaurent_table_number ?? "-",
      sectionNumber: order.section_number ?? "-",
      quantity:      qty,
      pricePerItem,
      totalAmount,
      cgst,
      sgst,
      vat:           0,
      tax,
      grossAmount,
      remarks:       order.remarks || "",
      orderedBy:     order.user?.name || "-",
      cancelledBy:   order.deletedByUser?.name || "-",
      cancelledAt:   order.createdAt,
      isApproved:    order.isApproved,
      isCustom,
    };
  });

  // ---- Map drink rows ----
  const drinkRows = cancelledDrinks.map((order) => {
    const isCustom = isTruthy(order.is_custom);

    const itemName = isCustom
      ? (order.customName || order.remarks || "Open Bar")
      : (order.menu?.name || order.remarks || "Unknown Item");

    const category = isCustom
      ? "Open Bar"
      : (order.menu?.category?.name || "Drinks");

    const pricePerItem = toNumber(order.menu?.price ?? 0);
    const qty          = toNumber(order.count);
    const totalAmount  = pricePerItem * qty;
    const catNorm      = normalizeString(category);
    const applyVAT     = isTruthy(order.menu?.applyVAT) || isCustom;

    let cgst = 0, sgst = 0, vat = 0, tax = 0;
    if (catNorm === "juices" || catNorm === "mocktails") {
      cgst = totalAmount * 0.025;
      sgst = totalAmount * 0.025;
      tax  = cgst + sgst;
    } else if (applyVAT) {
      vat = totalAmount * 0.1;
      tax = vat;
    } else {
      cgst = totalAmount * 0.025;
      sgst = totalAmount * 0.025;
      tax  = cgst + sgst;
    }
    const grossAmount = totalAmount + tax;

    return {
      type:          "drink",
      category,
      itemName,
      tableNumber:   order.restaurent_table_number ?? "-",
      sectionNumber: order.section_number ?? "-",
      quantity:      qty,
      pricePerItem,
      totalAmount,
      cgst,
      sgst,
      vat,
      tax,
      grossAmount,
      remarks:       order.remarks || "",
      orderedBy:     order.user?.name || "-",
      cancelledBy:   order.deletedByUser?.name || "-",
      cancelledAt:   order.createdAt,
      isApproved:    order.isApproved,
      isCustom,
    };
  });

  const rows = [...foodRows, ...drinkRows];
  return { startMoment, endMoment, rows };
};

// ---------- Summary helper ----------
const buildCancelledSummary = (rows) => {
  if (!rows.length) {
    return ["Total", "Min", "Max", "Avg"].map((label) => ({
      label, quantity: 0, totalAmount: 0, tax: 0, grossAmount: 0,
    }));
  }

  const pluck = (key) => rows.map((r) => toNumber(r[key]));
  const sum   = (arr) => arr.reduce((a, b) => a + b, 0);
  const qty   = pluck("quantity");
  const total = pluck("totalAmount");
  const tax   = pluck("tax");
  const gross = pluck("grossAmount");

  return [
    { label: "Total", quantity: sum(qty),                  totalAmount: sum(total),                  tax: sum(tax),                  grossAmount: sum(gross) },
    { label: "Min",   quantity: Math.min(...qty),           totalAmount: Math.min(...total),           tax: Math.min(...tax),           grossAmount: Math.min(...gross) },
    { label: "Max",   quantity: Math.max(...qty),           totalAmount: Math.max(...total),           tax: Math.max(...tax),           grossAmount: Math.max(...gross) },
    { label: "Avg",   quantity: sum(qty) / rows.length,     totalAmount: sum(total) / rows.length,     tax: sum(tax) / rows.length,     grossAmount: sum(gross) / rows.length },
  ];
};

// ---------- Endpoint: getCancelledOrdersReport ----------
const getCancelledOrdersReport = async (req, res) => {
  try {
    const { startDate, endDate, foodType, isApproved } = req.query;

    const { startMoment, endMoment, rows } = await buildCancelledOrderRows({
      startDate,
      endDate,
      foodType:         foodType || "all",
      isApprovedFilter: isApproved, // undefined = all rows (no filter)
    });

    const formatted = rows.map((r) => ({
      type:          r.type,
      category:      r.category,
      itemName:      r.itemName,
      tableNumber:   r.tableNumber,
      sectionNumber: r.sectionNumber,
      quantity:      r.quantity,
      pricePerItem:  Number(r.pricePerItem.toFixed(2)),
      totalAmount:   Number(r.totalAmount.toFixed(2)),
      cgst:          Number(r.cgst.toFixed(2)),
      sgst:          Number(r.sgst.toFixed(2)),
      vat:           Number(r.vat.toFixed(2)),
      tax:           Number(r.tax.toFixed(2)),
      grossAmount:   Number(r.grossAmount.toFixed(2)),
      remarks:       r.remarks,
      orderedBy:     r.orderedBy,
      cancelledBy:   r.cancelledBy,
      cancelledAt:   r.cancelledAt
        ? moment(r.cancelledAt).tz(TZ).format("YYYY-MM-DD HH:mm")
        : "-",
      isApproved:    r.isApproved,
      isCustom:      r.isCustom,
    }));

    const summary = buildCancelledSummary(rows).map((s) => ({
      label:       s.label,
      quantity:    Number(Number(s.quantity).toFixed(s.label === "Avg" ? 2 : 0)),
      totalAmount: Number(Number(s.totalAmount).toFixed(2)),
      tax:         Number(Number(s.tax).toFixed(2)),
      grossAmount: Number(Number(s.grossAmount).toFixed(2)),
    }));

    return res.status(200).json({
      message: "Cancelled Orders Report",
      window: {
        startIST: startMoment.tz(TZ).format("YYYY-MM-DD HH:mm"),
        endIST:   endMoment.tz(TZ).format("YYYY-MM-DD HH:mm"),
      },
      data:    formatted,
      summary,
    });
  } catch (error) {
    console.error("getCancelledOrdersReport error:", error);
    return res.status(500).json({
      message: "Failed to fetch cancelled orders report",
      error:   error.message,
    });
  }
};

// ---------- Endpoint: downloadCancelledOrdersReport ----------
const downloadCancelledOrdersReport = async (req, res) => {
  try {
    const { startDate, endDate, foodType, exportType, isApproved } = req.query;

    if (!exportType) {
      return res.status(400).json({ message: "exportType required: csv | excel | pdf" });
    }

    const { startMoment, endMoment, rows } = await buildCancelledOrderRows({
      startDate,
      endDate,
      foodType:         foodType || "all",
      isApprovedFilter: isApproved,
    });

    // Flat rows for export
    const exportRows = rows.map((r) => ({
      "Type":           r.type,
      "Category":       r.category,
      "Item Name":      r.itemName,
      "Remarks":        r.remarks,
      "Table No.":      r.tableNumber,
      "Section No.":    r.sectionNumber,
      "Qty":            r.quantity,
      "Price/Item":     r.pricePerItem.toFixed(2),
      "Total Amount":   r.totalAmount.toFixed(2),
      "CGST":           r.cgst.toFixed(2),
      "SGST":           r.sgst.toFixed(2),
      "VAT":            r.vat.toFixed(2),
      "Tax":            r.tax.toFixed(2),
      "Gross Amount":   r.grossAmount.toFixed(2),
      "Ordered By":     r.orderedBy,
      "Cancelled By":   r.cancelledBy,
      "Status":         r.isApproved ? "Approved" : "Pending",
      "Cancelled At":   r.cancelledAt
        ? moment(r.cancelledAt).tz(TZ).format("YYYY-MM-DD HH:mm")
        : "-",
    }));

    // Totals row
    const totalsRow = exportRows.reduce(
      (acc, r) => {
        acc["Qty"]          += Number(r["Qty"]);
        acc["Total Amount"]  = (Number(acc["Total Amount"])  + Number(r["Total Amount"])).toFixed(2);
        acc["CGST"]          = (Number(acc["CGST"])          + Number(r["CGST"])).toFixed(2);
        acc["SGST"]          = (Number(acc["SGST"])          + Number(r["SGST"])).toFixed(2);
        acc["VAT"]           = (Number(acc["VAT"])           + Number(r["VAT"])).toFixed(2);
        acc["Tax"]           = (Number(acc["Tax"])           + Number(r["Tax"])).toFixed(2);
        acc["Gross Amount"]  = (Number(acc["Gross Amount"])  + Number(r["Gross Amount"])).toFixed(2);
        return acc;
      },
      {
        "Type": "", "Category": "", "Item Name": "── TOTAL ──", "Remarks": "",
        "Table No.": "", "Section No.": "", "Qty": 0, "Price/Item": "",
        "Total Amount": "0.00", "CGST": "0.00", "SGST": "0.00",
        "VAT": "0.00", "Tax": "0.00", "Gross Amount": "0.00",
        "Ordered By": "", "Cancelled By": "", "Status": "", "Cancelled At": "",
      }
    );

    const startStr = startMoment.tz(TZ).format("YYYYMMDD_HHmm");
    const endStr   = endMoment.tz(TZ).format("YYYYMMDD_HHmm");
    const filename  = `cancelled_orders_${startStr}_${endStr}`;

    // ───────── CSV ──────────────────────────────────────────
    if (exportType === "csv") {
      const { Parser } = require("json2csv");
      const parser = new Parser();
      const csv = parser.parse([...exportRows, totalsRow]);
      res.setHeader("Content-Type", "text/csv; charset=utf-8");
      res.setHeader("Content-Disposition", `attachment; filename="${filename}.csv"`);
      return res.status(200).send(csv);
    }

    // ───────── EXCEL ─────────────────────────────────────────
    if (exportType === "excel" || exportType === "xlsx") {
      const ExcelJS = require("exceljs");
      const workbook = new ExcelJS.Workbook();
      const sheet = workbook.addWorksheet("Cancelled Orders");

      const cols = Object.keys(exportRows[0] || totalsRow);
      sheet.columns = cols.map((key) => ({
        header: key,
        key,
        width: Math.max(key.length + 2, 14),
      }));

      // Header styling
      const headerRow = sheet.getRow(1);
      headerRow.font      = { bold: true };
      headerRow.fill      = { type: "pattern", pattern: "solid", fgColor: { argb: "FFEDE7F6" } };
      headerRow.alignment = { vertical: "middle", horizontal: "center" };
      headerRow.height    = 22;

      // Data rows — type chip colour on the Type cell
      exportRows.forEach((row) => {
        const added = sheet.addRow(row);
        const isFood = row["Type"] === "food";
        added.getCell("Type").fill = {
          type: "pattern", pattern: "solid",
          fgColor: { argb: isFood ? "FFFFF3E0" : "FFE3F2FD" },
        };
        added.getCell("Type").font = {
          bold: true,
          color: { argb: isFood ? "FF8E5300" : "FF0D47A1" },
        };
        // Highlight Pending status in amber
        if (row["Status"] === "Pending") {
          added.getCell("Status").font  = { color: { argb: "FFE65100" } };
          added.getCell("Status").fill  = { type: "pattern", pattern: "solid", fgColor: { argb: "FFFFF8E1" } };
        }
      });

      // Totals row
      const totRow = sheet.addRow(totalsRow);
      totRow.font = { bold: true };
      totRow.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFDDD0F8" } };
      totRow.eachCell((cell) => { cell.alignment = { horizontal: "right" }; });
      totRow.getCell("Item Name").alignment = { horizontal: "left" };

      // Freeze header
      sheet.views = [{ state: "frozen", ySplit: 1 }];

      res.setHeader("Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
      res.setHeader("Content-Disposition", `attachment; filename="${filename}.xlsx"`);
      await workbook.xlsx.write(res);
      return res.end();
    }

    // ───────── PDF ───────────────────────────────────────────
    if (exportType === "pdf") {
      const PDFDocument = require("pdfkit");
      const doc = new PDFDocument({ margin: 28, size: "A4", layout: "landscape" });
      res.setHeader("Content-Type", "application/pdf");
      res.setHeader("Content-Disposition", `attachment; filename="${filename}.pdf"`);
      doc.pipe(res);

      doc.fontSize(14).font("Helvetica-Bold").text("Cancelled Orders Report", { align: "center" });
      doc.moveDown(0.25);
      doc.fontSize(8.5).font("Helvetica").fillColor("#555").text(
        `Period: ${startMoment.tz(TZ).format("DD MMM YYYY HH:mm")} — ${endMoment.tz(TZ).format("DD MMM YYYY HH:mm")} (IST)   |   Total rows: ${rows.length}`,
        { align: "center" }
      );
      doc.fillColor("black").moveDown(0.6);

      const PDF_COLS = [
        { label: "Type",         width: 36,  key: "Type" },
        { label: "Category",     width: 70,  key: "Category" },
        { label: "Item",         width: 95,  key: "Item Name" },
        { label: "Remarks",      width: 80,  key: "Remarks" },
        { label: "Table",        width: 32,  key: "Table No." },
        { label: "Qty",          width: 26,  key: "Qty" },
        { label: "Price",        width: 44,  key: "Price/Item" },
        { label: "Total",        width: 48,  key: "Total Amount" },
        { label: "Tax",          width: 44,  key: "Tax" },
        { label: "Gross",        width: 48,  key: "Gross Amount" },
        { label: "Cancelled By", width: 68,  key: "Cancelled By" },
        { label: "Status",       width: 44,  key: "Status" },
        { label: "Date",         width: 76,  key: "Cancelled At" },
      ];
      const ROW_H  = 15;
      const START_X = 28;
      const totalW  = PDF_COLS.reduce((s, c) => s + c.width, 0);

      const drawHLine = (y) => {
        doc.moveTo(START_X, y).lineTo(START_X + totalW, y)
          .strokeColor("#CCCCCC").lineWidth(0.4).stroke();
      };

      const drawRow = (values, y, { bgColor, bold, fontSize = 7.5 } = {}) => {
        if (bgColor) {
          doc.save().rect(START_X, y, totalW, ROW_H).fill(bgColor).restore();
        }
        doc.font(bold ? "Helvetica-Bold" : "Helvetica").fontSize(fontSize).fillColor("black");
        let x = START_X;
        PDF_COLS.forEach((col, i) => {
          doc.text(String(values[i] ?? "").slice(0, 28), x + 2, y + 3.5, {
            width: col.width - 4, lineBreak: false, ellipsis: true,
          });
          x += col.width;
        });
        drawHLine(y + ROW_H);
      };

      const printHeader = (y) => {
        drawRow(PDF_COLS.map((c) => c.label), y, { bgColor: "#D1C4E9", bold: true, fontSize: 8 });
        return y + ROW_H;
      };

      let curY = printHeader(doc.y);

      exportRows.forEach((row, idx) => {
        if (curY > 520) {
          doc.addPage({ layout: "landscape" });
          curY = printHeader(28);
        }
        const isFood = row["Type"] === "food";
        const bg = idx % 2 === 0 ? (isFood ? "#FFF8F0" : "#F0F7FF") : null;
        drawRow(PDF_COLS.map((c) => row[c.key]), curY, { bgColor: bg });
        curY += ROW_H;
      });

      // Totals
      if (curY > 520) { doc.addPage({ layout: "landscape" }); curY = 28; }
      drawRow(PDF_COLS.map((c) => totalsRow[c.key] ?? ""), curY, { bgColor: "#EDE7F6", bold: true });

      doc.end();
      return;
    }

    return res.status(400).json({ message: "Unsupported exportType. Use: csv | excel | pdf" });
  } catch (error) {
    console.error("downloadCancelledOrdersReport error:", error);
    return res.status(500).json({
      message: "Failed to export cancelled orders report",
      error:   error.message,
    });
  }
};

//-----------------------------------------------------------------------


//-----------------------------------------------------------------------



module.exports = {
  getSalesReport,
  downloadSalesReport,

  getItemWiseReport,
  downloadItemWiseReport,

  getInvoiceReport,
  downloadInvoiceReport,

  subOrderWiseReport,
  downloadSubOrderWiseReport,

  getEmployeePerformanceReport,
  downloadEmployeePerformanceReport,

  getInventoryItems,
  downloadInventoryItems,

  getDrinksInventoryItems,
  downloadDrinksInventoryItems,

  getDayWiseReport,
  downloadDayWiseReport,

  generateMasterReport,

  testDaySummary,

  getCancelledOrdersReport,
  downloadCancelledOrdersReport,
};
