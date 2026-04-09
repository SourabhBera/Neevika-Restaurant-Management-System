const { Log, User } = require('../../models');
const { Sequelize } = require('sequelize');

// Create a new log entry
async function createLog(action, userId, userRole, affectedEntity, oldValue, newValue) {
  try {
    // Log the action performed by the user
    await Log.create({
      action: action,                      // Description of the action (e.g., "Updated menu item")
      user_id: userId,                     // The user who performed the action
      user_role: userRole,                 // The user's role (e.g., "manager", "chef")
      affected_entity: affectedEntity,     // The entity affected (e.g., "menu_item", "order")
      old_value: oldValue,                 // Old value (before the action)
      new_value: newValue                  // New value (after the action)
    });
  } catch (error) {
    console.error('Error creating log:', error);
    throw new Error('Error creating log entry');
  }
}

// Get logs with pagination and filtering
async function getLogs(req, res) {
  const { limit = 50, page = 1, user_id, action, start_date, end_date } = req.query;

  // Pagination logic
  const offset = (page - 1) * limit;

  try {
    // Build query options for filtering and pagination
    const where = {};
    if (user_id) where.user_id = user_id;
    if (action) where.action = { [Sequelize.Op.iLike]: `%${action}%` };  // Case-insensitive match
    if (start_date && end_date) {
      where.timestamp = {
        [Sequelize.Op.between]: [new Date(start_date), new Date(end_date)]
      };
    }

    // Fetch logs from the database with filters and pagination
    const logs = await Log.findAll({
      where,
      limit: Number(limit),
      offset: offset,
      order: [['timestamp', 'DESC']],  // Sort by most recent
    });

    // Return logs in the response
    res.json({
      logs,
      pagination: {
        currentPage: page,
        totalLogs: await Log.count({ where }),  // Count total logs with the applied filters
        totalPages: Math.ceil(await Log.count({ where }) / limit),
      }
    });
  } catch (error) {
    console.error('Error fetching logs:', error);
    res.status(500).json({ error: 'Failed to fetch logs' });
  }
}

module.exports = {
  createLog,
  getLogs
};
