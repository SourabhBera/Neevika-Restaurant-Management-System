// src/middlewares/authorize.js
const authorize = (roles) => {
  return (req, res, next) => {
    const roleName = req.user?.role?.name;
    
    console.log(`Authorize middleware triggered. Allowed roles: ${roles}. User role: ${roleName}`);

    if (!roleName || !roles.includes(roleName)) {
      return res.status(403).json({
        message: 'Access denied. You do not have permission to perform this action.',
      });
    }

    next();
  };
};

module.exports = authorize;
