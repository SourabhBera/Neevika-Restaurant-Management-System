const express = require('express');
const { createLog, getLogs } = require('../../controllers/LogsController/logsController');
const router = express.Router();

// Route for fetching logs with filters and pagination
router.get('/', getLogs);

// // Example of how you would use createLog directly in another controller (e.g., menu-item update)
// router.post('/create', async (req, res) => {
//   const { userId, userRole, action, affectedEntity, oldValue, newValue } = req.body;
  
//   try {
//     // Call the createLog function to log the action
//     await createLog(action, userId, userRole, affectedEntity, oldValue, newValue);
//     res.json({ message: 'Log created successfully' });
//   } catch (error) {
//     res.status(500).json({ error: 'Failed to create log' });
//   }
// });

module.exports = router;
