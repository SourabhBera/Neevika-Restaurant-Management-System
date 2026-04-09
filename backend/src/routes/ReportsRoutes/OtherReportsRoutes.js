const express = require("express");
const router = express.Router();
const {
  getItemWiseReport,
  downloadItemWiseReport,

  getSalesReport,
  downloadSalesReport,

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
} = require("../../controllers/ReportsController/OtherReportsController");

router.get("/item-wise-report/", getItemWiseReport);
router.get("/item-wise-report/download", downloadItemWiseReport);

router.get("/cancelled-orders-report/",   getCancelledOrdersReport,);
router.get("/cancelled-orders-report/download", downloadCancelledOrdersReport);

router.get("/sales-reports/summary", getSalesReport);
router.get("/sales-reports/summary/download", downloadSalesReport);

router.get("/invoice-report/", getInvoiceReport);
router.get("/invoice-report/download", downloadInvoiceReport);

router.get("/sub-order-wise-report/", subOrderWiseReport);
router.get("/sub-order-wise-report/download", downloadSubOrderWiseReport);

router.get("/employee-performance-report/", getEmployeePerformanceReport);
router.get("/employee-performance-report/download", downloadEmployeePerformanceReport);

router.get("/inventory-report/", getInventoryItems);
router.get("/inventory-report/download", downloadInventoryItems);

router.get("/drinks-inventory-report/", getDrinksInventoryItems);
router.get("/drinks-inventory-report/download", downloadDrinksInventoryItems);

router.get("/day-wise-report/", getDayWiseReport);
router.get("/day-wise-report/download", downloadDayWiseReport);

router.get("/master-report/download", generateMasterReport);

router.get("/day-summary-test", testDaySummary);

// router.get('/:id', getSectionById);
// router.post('/', createSection);
// router.put('/:id', updateSection);
// router.delete('/:id', deleteSection);

module.exports = router;
