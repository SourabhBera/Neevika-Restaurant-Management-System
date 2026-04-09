const express = require('express');
const authenticate = require('../../middlewares/authenticate');
const authorize = require('../../middlewares/authorize');

const router = express.Router();
const {
  getDrinksMenus,
  createDrinksMenu,
  getDrinksMenuById,
  updateDrinksMenu,
  deleteDrinksMenu,
} = require('../../controllers/DrinksController/drinksMenuController');




// ✅ Get all menu items
// router.get('/',authenticate, authorize(['Waiter']), getMenuItems);
router.get('/', getDrinksMenus);

// ✅ Create a new menu item
router.post('/addItem', createDrinksMenu);

// ✅ Get a single menu item by ID
router.get('/:id', getDrinksMenuById);

// ✅ Update a menu item
router.put('/:id', updateDrinksMenu);

// ✅ Delete a menu item
router.delete('/:id', deleteDrinksMenu);


// router.get(
//   '/admin-dashboard',
//   authenticate,
//   authorize(['admin']),
//   (req, res) => {
//     res.json({ message: 'Welcome to the admin dashboard!' });
//   }
// );

module.exports = router;
