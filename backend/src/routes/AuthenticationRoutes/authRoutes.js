const express = require('express');
const { register, login, logout, deleteUser,
        getAllUserRoles, createRole,
        getAllUsers, updateRole, 
        deleteRole, getUsersByRoleId, getUserById, 
        getOrdersByUserId, getScoreForToday, sendOtp, verifyOtp,
        resetPasswordViaOtp, sendPasswordResetOtp,
        getUnverifiedUsers, verifyUser   // ✅ NEW FUNCTIONS
      } = require('../../controllers/AuthenticationController/authController');

const authenticate = require('../../middlewares/authenticate');
const authorize = require('../../middlewares/authorize');

const router = express.Router();

// Public routes
router.get('/users', getAllUsers); // Get user Role

router.get('/unverified-users', getUnverifiedUsers); // Get all unverified users

router.get('/user_role', getAllUserRoles); // Get user Role
router.post('/user_role', createRole); // Get user Role
router.get('/scoreboard', getScoreForToday); // Get user Role

router.put('/verify-user/:userId', verifyUser);// Verify a user
router.post('/register', register); // Register user
router.post('/login', login); // Login user
router.post("/send-otp", sendOtp);
router.post("/send-password-reset-otp", sendPasswordResetOtp);
router.post("/verify-otp", verifyOtp);
router.post('/reset-password-otp', resetPasswordViaOtp);
// router.put('/change-password', changePassword); // Login user
router.post('/logout/:userId', logout); //logout
router.delete('/delete-account/:userId', deleteUser); // Delete user account

router.get('/user_orders/:userId', getOrdersByUserId); //Get orders by user id
router.get('/user_details/:id', getUserById); // Update user Role
router.get('/user_role/:id', getUsersByRoleId); // Update user Role
router.put('/user_role/:id', updateRole); // Update user Role
router.delete('/user_role/:id', deleteRole);// Delete user Role


// Protected route examples
router.get(
  '/admin-dashboard',
  authenticate,
  authorize(['admin']),
  (req, res) => {
    res.json({ message: 'Welcome to the admin dashboard!' });
  }
);

router.get(
  '/chef-dashboard',
  authenticate,
  authorize(['chef', 'admin']),
  (req, res) => {
    res.json({ message: 'Welcome to the chef dashboard!' });
  }
);

router.get(
  '/customer-dashboard',
  authenticate,
  authorize(['customer', 'admin']),
  (req, res) => {
    res.json({ message: 'Welcome to the customer dashboard!' });
  }
);

module.exports = router;
