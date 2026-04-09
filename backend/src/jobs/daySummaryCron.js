const cron = require("node-cron");
const { Op, fn, col } = require("sequelize");
const { Bill, DaySummary } = require("../models");
// If your sequelize instance is exported, you can import it if needed:
// const sequelize = require("../models").sequelize;

const TZ = "Asia/Kolkata";
const IST_OFFSET = 5.5 * 60; // minutes

// --- Small helpers (same behaviour as getSalesReport) ---
const toNumber = (v) => {
  if (v === null || v === undefined || v === "") return 0;
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
};

const safeParseJsonMaybeString = (x) => {
  if (!x) return {};
  if (typeof x === "object") return x;
  try {
    return JSON.parse(x);
  } catch {
    return {};
  }
};

// Main job
const generatePreviousDaySummary = async () => {
  try {
    const now = new Date();

    // Convert current time to IST
    const nowUTC = new Date(now.getTime() + now.getTimezoneOffset() * 60000);
    const nowIST = new Date(nowUTC.getTime() + IST_OFFSET * 60000);

    // Define startIST as *today* 03:10 IST (the window: 03:10 → next 03:10)
    const startIST = new Date(nowIST);
    startIST.setHours(3, 10, 0, 0);

    // Robustness: if this function was run manually before 03:15 IST,
    // we want the window to refer to the previous day's 03:10.
    // Because cron runs at 03:15, this branch is only for manual runs.
    if (
      nowIST.getHours() < 3 ||
      (nowIST.getHours() === 3 && nowIST.getMinutes() < 15)
    ) {
      // If current IST is earlier than 03:15, the "current" 03:10 is in the future,
      // so step back one day to get the right 03:10 window.
      startIST.setDate(startIST.getDate() - 1);
    }

    // End = start + 24 hours (exclusive upper bound)
    const endIST = new Date(startIST.getTime() + 24 * 60 * 60000);

    // Convert to UTC for DB queries (assuming DB stores UTC)
    const startUTC = new Date(startIST.getTime() - IST_OFFSET * 60000);
    const endUTC = new Date(endIST.getTime() - IST_OFFSET * 60000);

    const summaryDate = startIST.toISOString().split("T")[0];

    // --- Fetch invoice meta (count, first/last IDs) ---
    const invoiceData = await Bill.findOne({
      where: { time_of_bill: { [Op.between]: [startUTC, endUTC] } },
      attributes: [
        [fn("COUNT", col("id")), "totalBills"],
        [fn("MIN", col("id")), "firstBillId"],
        [fn("MAX", col("id")), "lastBillId"],
      ],
      raw: true,
    });

    const { totalBills, firstBillId, lastBillId } = invoiceData || {};

    // --- Fetch all bills ---
const bills = await Bill.findAll({
  where: { time_of_bill: { [Op.between]: [startUTC, endUTC] } },
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
    "isComplimentary",
  ],
  raw: true,
});

if (!bills.length) {
  console.log(`⚠️ No bills for ${summaryDate}, saving empty summary.`);
  await DaySummary.upsert({
    date: summaryDate,
    orderCount: 0,
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
    paymentsOther: 0,
    roundingAdjustment: 0,
    totalTips: 0,
    totalBills: 0,
    invoices: `0-0`,
    complimentaryAmount: 0,
    totalComplimentaryBills: 0,
    complimentaryInvoice: "0-0",
  });
  return;
}

// --- Separate complimentary vs paid bills ---
const compBills = bills.filter(b => b.isComplimentary);
const paidBills = bills.filter(b => !b.isComplimentary);

// complimentary stats
let complimentaryAmount = 0;
let totalComplimentaryBills = 0;
let complimentaryInvoice = "0-0";

if (compBills.length > 0) {
  const compIds = compBills.map(b => Number(b.id)).sort((a, b) => a - b);
  totalComplimentaryBills = compIds.length;
  complimentaryAmount = compBills.reduce((sum, b) => sum + toNumber(b.final_amount), 0);
  complimentaryInvoice = `${compIds[0]}-${compIds[compIds.length - 1]}`;
}

// --- Aggregate only paid bills ---
let totalAmount = 0;
let totalDiscount = 0;
let totalSales = 0;
let gst = 0;
let vat = 0;
let serviceCharges = 0;
let totalTips = 0;

let cashTotal = 0;
let cardTotal = 0;
let upiTotal = 0;
let otherPaymentsTotal = 0;
let roundingAdjustment = 0;

for (const b of paidBills) {
  const finalAmt = Number((toNumber(b.final_amount || 0)).toFixed(2));
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

  cashTotal += toNumber(norm.cash);
  cardTotal += toNumber(norm.card);
  upiTotal += toNumber(norm.upi);

  let pbSum = 0;
  for (const k of Object.keys(norm)) pbSum += toNumber(norm[k]);

  const diff = Number((finalAmt - pbSum).toFixed(2));
  if (Math.abs(diff) >= 0.005) {
    otherPaymentsTotal += diff;
    roundingAdjustment += diff;
  }

  for (const k of Object.keys(norm)) {
    if (!["cash", "card", "upi"].includes(k)) {
      otherPaymentsTotal += toNumber(norm[k]);
    }
  }
}

// rounding adjustments
totalAmount = Number(totalAmount.toFixed(2));
totalDiscount = Number(totalDiscount.toFixed(2));
const netSales = Number(Math.max(0, totalAmount - totalDiscount).toFixed(2));
totalSales = Number(totalSales.toFixed(2));
gst = Number(gst.toFixed(2));
vat = Number(vat.toFixed(2));
const totalTax = Number((gst + vat).toFixed(2));
serviceCharges = Number(serviceCharges.toFixed(2));
totalTips = Number(totalTips.toFixed(2));

cashTotal = Number(cashTotal.toFixed(2));
cardTotal = Number(cardTotal.toFixed(2));
upiTotal = Number(upiTotal.toFixed(2));
otherPaymentsTotal = Number(otherPaymentsTotal.toFixed(2));
roundingAdjustment = Number(roundingAdjustment.toFixed(2));

// --- Save summary ---
await DaySummary.upsert({
  date: summaryDate,
  orderCount: paidBills.length, // ✅ only count paid bills
  subTotal: totalAmount.toFixed(2),
  discount: totalDiscount.toFixed(2),
  serviceCharges: serviceCharges.toFixed(2),
  tax: totalTax.toFixed(2),
  roundOff: 0,
  grandTotal: totalSales.toFixed(2), // ✅ excludes complimentary
  netSales: netSales.toFixed(2),     // ✅ excludes complimentary
  cash: cashTotal.toFixed(2),
  card: cardTotal.toFixed(2),
  upi: upiTotal.toFixed(2),
  paymentsOther: otherPaymentsTotal.toFixed(2),
  roundingAdjustment: roundingAdjustment.toFixed(2),
  totalTips: totalTips.toFixed(2),
  invoices: `${paidBills.length ? paidBills[0].id : ""}-${paidBills.length ? paidBills[paidBills.length - 1].id : ""}`,
  totalBills: paidBills.length,   // ✅ excludes complimentary
  complimentaryAmount: complimentaryAmount.toFixed(2), // 👈 shown separately
  totalComplimentaryBills,
  complimentaryInvoice,
});

    console.log(`✅ Day-End Summary upserted for ${summaryDate} (window ${startIST.toISOString()} → ${endIST.toISOString()})`);
  } catch (err) {
    console.error("❌ Error generating day-end summary:", err);
  }
};


const IST_OFFSET_MIN = 5.5 * 60; // IST offset in minutes

const generateDayEndSummaryForDate = async (dateStr) => {
  if (!dateStr || typeof dateStr !== "string") {
    throw new Error("dateStr must be a YYYY-MM-DD string");
  }
  const m = dateStr.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!m) throw new Error("Invalid date format. Expected YYYY-MM-DD.");

  const year = Number(m[1]);
  const month = Number(m[2]);
  const day = Number(m[3]);

  const startUTCms =
    Date.UTC(year, month - 1, day, 3, 10, 0) - IST_OFFSET_MIN * 60000;
  const startUTC = new Date(startUTCms);
  const endUTC = new Date(startUTCms + 24 * 60 * 60000);
  const summaryDateStr = dateStr;

  // --- Fetch all bills for the day ---
  const bills = await Bill.findAll({
    where: { time_of_bill: { [Op.between]: [startUTC, endUTC] } },
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
      "isComplimentary", // make sure your Bill model has this
    ],
    raw: true,
  });

  // --- No bills case ---
  if (!bills.length) {
    const payload = {
      date: summaryDateStr,
      orderCount: 0,
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
      paymentsOther: 0,
      roundingAdjustment: 0,
      totalTips: 0,
      totalBills: 0,
      invoices: "0-0",
      grandTotalPercentType: null,
      grandTotalPercent: null,
      complimentaryAmount: 0,
      totalComplimentaryBills: 0,
      complimentaryInvoice: "0-0",
    };

    const existing = await DaySummary.findOne({
      where: { date: summaryDateStr },
    });
    if (existing) {
      await DaySummary.update(payload, { where: { date: summaryDateStr } });
      return {
        ok: true,
        action: "updated",
        summaryDate: summaryDateStr,
        message: "No bills; existing summary updated.",
      };
    } else {
      await DaySummary.create(payload);
      return {
        ok: true,
        action: "created",
        summaryDate: summaryDateStr,
        message: "No bills; summary created.",
      };
    }
  }

  // --- Split paid vs complimentary bills ---
  const paidBills = bills.filter((b) => !b.isComplimentary);
  const complimentaryBills = bills.filter((b) => b.isComplimentary);

  const billIds = paidBills.map((b) => Number(b.id)).sort((a, b) => a - b);
  const compIds = complimentaryBills.map((b) => Number(b.id)).sort((a, b) => a - b);

  const firstId = billIds.length ? billIds[0] : null;
  const lastId = billIds.length ? billIds[billIds.length - 1] : null;
  const totalBillsCount = billIds.length;

  const compFirstId = compIds.length ? compIds[0] : null;
  const compLastId = compIds.length ? compIds[compIds.length - 1] : null;

  let totalAmount = 0,
    totalDiscount = 0,
    totalSales = 0,
    gst = 0,
    vat = 0,
    serviceCharges = 0,
    roundOff = 0,
    totalTips = 0,
    cashTotal = 0,
    cardTotal = 0,
    upiTotal = 0,
    otherPaymentsTotal = 0,
    roundingAdjustment = 0,
    complimentaryAmount = 0;

  // --- Process paid bills ---
  for (const b of paidBills) {
    const finalAmt = Number(toNumber(b.final_amount || 0).toFixed(2));
    totalAmount += toNumber(b.total_amount || 0);
    totalDiscount += toNumber(b.discount_amount || 0);
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

    cashTotal += toNumber(norm.cash);
    cardTotal += toNumber(norm.card);
    upiTotal += toNumber(norm.upi);

    let pbSum = Object.values(norm).reduce(
      (acc, val) => acc + toNumber(val),
      0
    );
    const diff = Number((finalAmt - pbSum).toFixed(2));
    if (Math.abs(diff) >= 0.005) {
      otherPaymentsTotal += diff;
      roundingAdjustment += diff;
    }
    for (const k of Object.keys(norm)) {
      if (!["cash", "card", "upi"].includes(k)) {
        otherPaymentsTotal += toNumber(norm[k]);
      }
    }
  }

  // --- Process complimentary bills ---
  for (const b of complimentaryBills) {
    complimentaryAmount += toNumber(b.final_amount || 0);
  }

  // Reconcile totals (only for paid bills)
  const paymentsTotalBeforeAdjust = Number(
    (cashTotal + cardTotal + upiTotal + otherPaymentsTotal).toFixed(2)
  );
  const paymentDelta = Number((totalSales - paymentsTotalBeforeAdjust).toFixed(2));
  if (Math.abs(paymentDelta) >= 0.005) {
    otherPaymentsTotal += paymentDelta;
    roundingAdjustment += paymentDelta;
  }

  // Finalize numbers
  totalAmount = Number(totalAmount.toFixed(2));
  totalDiscount = Number(totalDiscount.toFixed(2));
  const netSales = Number(Math.max(0, totalAmount - totalDiscount).toFixed(2));
  totalSales = Number(totalSales.toFixed(2));
  gst = Number(gst.toFixed(2));
  vat = Number(vat.toFixed(2));
  const totalTax = Number((gst + vat).toFixed(2));
  serviceCharges = Number(serviceCharges.toFixed(2));
  roundOff = Number(roundOff).toFixed(2);
  totalTips = Number(totalTips.toFixed(2));
  cashTotal = Number(cashTotal.toFixed(2));
  cardTotal = Number(cardTotal.toFixed(2));
  upiTotal = Number(upiTotal.toFixed(2));
  otherPaymentsTotal = Number(otherPaymentsTotal.toFixed(2));
  roundingAdjustment = Number(roundingAdjustment.toFixed(2));
  complimentaryAmount = Number(complimentaryAmount.toFixed(2));

  // --- Compare with previous day ---
  const prevDay = new Date(startUTC.getTime() - 24 * 60 * 60000);
  const previousSummaryDate = prevDay.toISOString().slice(0, 10);
  const previousSummary = await DaySummary.findOne({
    where: { date: previousSummaryDate },
  });

  let grandTotalPercentType = null;
  let grandTotalPercent = null;
  if (previousSummary && previousSummary.grandTotal) {
    const prevGrandTotal = parseFloat(previousSummary.grandTotal);
    const currGrandTotal = totalSales;
    const diff = currGrandTotal - prevGrandTotal;
    grandTotalPercentType = diff < 0 ? "negative" : "positive";
    if (prevGrandTotal !== 0)
      grandTotalPercent = (
        (Math.abs(diff) / prevGrandTotal) *
        100
      ).toFixed(2);
  }

  // --- Build payload ---
  const payload = {
    date: summaryDateStr,
    orderCount: totalBillsCount,
    subTotal: totalAmount.toFixed(2), // excludes complimentary
    discount: totalDiscount.toFixed(2),
    serviceCharges: serviceCharges.toFixed(2),
    complimentaryAmount: complimentaryAmount,
    complimentaryInvoice: `${compFirstId || ""}-${compLastId || ""}`,
    totalComplimentaryBills: complimentaryBills.length,
    invoices: `${firstId || ""}-${lastId || ""}`,
    totalBills: totalBillsCount,
    tax: totalTax.toFixed(2),
    roundOff: roundOff,
    grandTotal: totalSales.toFixed(2), // excludes complimentary
    netSales: netSales.toFixed(2), // excludes complimentary
    cash: cashTotal.toFixed(2),
    card: cardTotal.toFixed(2),
    upi: upiTotal.toFixed(2),
    paymentsOther: otherPaymentsTotal.toFixed(2),
    roundingAdjustment: roundingAdjustment.toFixed(2),
    totalTips: totalTips.toFixed(2),
    firstBillId: firstId || null,
    lastBillId: lastId || null,
    grandTotalPercentType,
    grandTotalPercent,
  };

  // --- Update or create ---
  const existing = await DaySummary.findOne({
    where: { date: summaryDateStr },
  });
  if (existing) {
    await DaySummary.update(payload, { where: { date: summaryDateStr } });
    return { ok: true, action: "updated", summaryDate: summaryDateStr };
  } else {
    await DaySummary.create(payload);
    return { ok: true, action: "created", summaryDate: summaryDateStr };
  }
};

const postGenerateDayEndSummary = async (req, res) => {
  try {
    const { date } = req.body;
    if (!date) return res.status(400).json({ ok: false, error: "Missing date (YYYY-MM-DD)" });

    const result = await generateDayEndSummaryForDate(date);
    return res.status(200).json(result);
  } catch (err) {
    console.error("Error in postGenerateDayEndSummary:", err);
    return res.status(500).json({ ok: false, error: String(err) });
  }
};

// Schedule: every day at 03:15 IST
// using node-cron timezone option to ensure it runs at Asia/Kolkata local time
cron.schedule(
  "15 3 * * *",
  generatePreviousDaySummary,
  { timezone: TZ }
);

module.exports = {generatePreviousDaySummary, generateDayEndSummaryForDate, postGenerateDayEndSummary};
