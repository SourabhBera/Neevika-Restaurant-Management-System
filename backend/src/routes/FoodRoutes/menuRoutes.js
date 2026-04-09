const express = require('express');
const authenticate = require('../../middlewares/authenticate');
const authorize = require('../../middlewares/authorize');

const router = express.Router();
const {
  createMenuItem,
  getMenuItems,
  getMenuItemById,
  updateMenuItem,
  deleteMenuItem,
} = require('../../controllers/FoodController/menuController');


// ✅ Create a new menu item
router.post('/addItem',  createMenuItem);

// ✅ Get all menu items
// router.get('/',authenticate, authorize(['Waiter']), getMenuItems);
router.get('/', getMenuItems);

// ✅ Get a single menu item by ID
router.get('/:id', getMenuItemById);

// ✅ Update a menu item
router.put('/:id',  updateMenuItem);

// ✅ Delete a menu item
router.delete('/:id', deleteMenuItem);


router.get(
  '/admin-dashboard',
  authenticate,
  authorize(['admin']),
  (req, res) => {
    res.json({ message: 'Welcome to the admin dashboard!' });
  }
);

module.exports = router;
