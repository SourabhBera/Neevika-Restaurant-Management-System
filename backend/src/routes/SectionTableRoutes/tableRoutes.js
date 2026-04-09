const express = require('express');
const router = express.Router();
const {
  getTables,
  getTableById,
  createTable,
  updateTable,
  deleteTable,
  getTableInfo,
  markTableAsFree,
  markTableAsOccupied,
  markTableAsReserved,
  getBills,
  getBillById,
  updateBillById,
  generateTableBill,
  settleAndCloseBill,
  transferTableOrders,
  mergeTableOrders,
  splitTable,
  closeSplitTable,
  demergeTableOrders,
  shiftOrders,
  getTableBillDetails,
  getTableWithAllOrderDetails, // ✅ New import
} = require('../../controllers/SectionTablesController/tableController');

// LIST / READ
router.get('/', getTables);
router.get('/bills', getBills); // note: keep this before /bills/:id
router.get('/bills/:id', getBillById);
router.get('/bill-details/:tableId', getTableBillDetails); // 🧾 Fresh table details for bill generation
router.get('/all-details/:tableId', getTableWithAllOrderDetails); // 🧾 Comprehensive table with all orders (similar to getSections)
router.get('/getTableInfo/:tableNumber', getTableInfo);

// ACTIONS (non-:id specific)
router.delete('/:id/close-split', closeSplitTable);
router.put('/transfer', transferTableOrders);
router.put('/merge', mergeTableOrders);
router.put('/demerge', demergeTableOrders); // <-- fixed: separate route + PUT
router.post('/orders/shift', shiftOrders);
router.post('/:tableNumber/bill', generateTableBill);
router.put('/bills/update/:billId', updateBillById);
router.post('/bills/:billId/settle', settleAndCloseBill);

// CRUD for tables (keep parameterized :id routes at the end)
router.post('/', createTable);
router.put('/:id', updateTable);
// router.delete('/:id', deleteTable);
router.get('/:id', getTableById);

// Table status / split routes
router.put('/:id/free', markTableAsFree);
router.put('/:id/occupied', markTableAsOccupied);
router.put('/:id/reserved', markTableAsReserved);
router.post('/:id/split', splitTable);



module.exports = router;
