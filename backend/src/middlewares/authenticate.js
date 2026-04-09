// src/middlewares/authenticate.js
const jwt = require('jsonwebtoken');
const { User, User_role } = require('../models');

const authenticate = async (req, res, next) => {
  const token = req.headers.authorization?.split(' ')[1];
  

  if (!token) {
    return res.status(401).json({ message: 'Access denied. No token provided.' });
  }

  try {
    console.log(token);
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    console.log(`Decoded token: ${decode}`);

    const user = await User.findByPk(decoded.id, {
      include: {
        model: User_role,
        as: 'role',
        attributes: ['name'],
      },
      attributes: { exclude: ['password'] }, // Optional but recommended
    });


    if (!user) {
      return res.status(401).json({ message: 'User not found.' });
    }

    req.user = user;
    next();
  } catch (error) {
    return res.status(401).json({ message: 'Invalid or expired token.' });
  }
};

module.exports = authenticate;
