const express = require("express");
const router = express.Router();
const adminController = require("../../controllers/AdminController/adminController");
const dayEndSummaryController = require("../../jobs/daySummaryCron");
const authenticate = require("../../middlewares/authenticate");
const authorize = require("../../middlewares/authorize");

// Reusable PDF upload middleware
const createPDFUploadMiddleware = require("../../middlewares/pdfUploadMiddleware");

// Create specific middleware for each upload field/folder
const uploadAadharCardPDF = createPDFUploadMiddleware("aadharCard", "pdf_file"); // uploads/appointments/
const uploadPanCardPDF = createPDFUploadMiddleware("panCard", "pdf_file"); // uploads/leaves/

router.get("/day-end-summary", adminController.getDayEndSummary);
router.post("/create-day-end-summary", dayEndSummaryController.postGenerateDayEndSummary);



router.get("/topSelling-today", adminController.getTopSellingFoodItemToday);
router.get("/todays-Order-Stats", adminController.getTodaysOrderStats);
router.get("/todays-Customer-Stats", adminController.getTodaysCustomerStats);
router.get("/hourly-sales", adminController.getTodaysHourlySales);

router.get("/todayScore", adminController.getDailySalesScoreboard);
router.get("/sales-scoreboard", adminController.getSalesScoreboardByDate);
router.get("/monthlyScore", adminController.getMonthlySalesScoreboard);

router.get('/todaySales', adminController.getTodaysSales);
router.get('/last7daysSales', adminController.getSalesOverview);
router.get('/tables', adminController.getTables);
router.get('/orders', adminController.getOrders);
router.get('/lowStock', adminController.lowStock);


router.get(
  "/users", 
  adminController.getAllUsers
);
router.post("/users", adminController.createUser);
router.put("/users/:id", adminController.updateUser);
router.delete(
  "/users/:id",
  authenticate,
  authorize(["admin"]),
  adminController.deleteUser
);
router.get("/download-summary/:date", adminController.downloadDayEndSummary);
router.put("/aadharCard/:id", uploadAadharCardPDF, adminController.aadharCard);
router.put("/panCard/:id", uploadPanCardPDF, adminController.panCard);

router.get(
  "/inventory",
  authenticate,
  authorize(["admin", "manager"]),
  adminController.getInventory
);
router.post(
  "/inventory",
  authenticate,
  authorize(["admin", "manager"]),
  adminController.addInventory
);
router.put(
  "/inventory/:id",
  authenticate,
  authorize(["admin", "manager"]),
  adminController.updateInventory
);
router.delete(
  "/inventory/:id",
  authenticate,
  authorize(["admin", "manager"]),
  adminController.deleteInventory
);

router.get(
  "/orders",
  authenticate,
  authorize(["admin", "manager"]),
  adminController.getAllOrders
);
router.put(
  "/orders/:id/status",
  authenticate,
  authorize(["admin", "manager"]),
  adminController.updateOrderStatus
);
router.delete(
  "/orders/:id",
  authenticate,
  authorize(["admin", "manager"]),
  adminController.deleteOrder
);

module.exports = router;
