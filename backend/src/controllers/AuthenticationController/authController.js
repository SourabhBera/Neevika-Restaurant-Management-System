const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const logger = require("../../configs/logger");
const moment = require("moment");
const {
  User_role,
  OrderItem,
  DrinksOrder,
  User,
  DrinksMenu,
  Menu,
  Order,
  Section,
  Otp
} = require("../../models");
const { Op } = require("sequelize");



// Generate JWT token with user role
const generateToken = async (user) => {
  logger.info(`JWT Token generated for user: ${user.email}`);

  try {
    // Await the async call to fetch user with role
    const userWithRole = await User.findByPk(user.id, {
      attributes: { exclude: ["password"] },
      include: [{ model: User_role, as: "role", attributes: ["name"] }],
    });

    if (!userWithRole) {
      throw new Error("User not found");
    }

    const roleName = userWithRole.role?.name;
    console.log("User Data: ", userWithRole);
    const new_token = jwt.sign(
      {
        id: user.id,
        role: roleName,
        userName: userWithRole.name, // Include role in token
      },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_EXPIRES_IN || "1d" }
    );

    console.log(new_token);
    console.log(
      "Decoded Token-->",
      JSON.stringify(verifyAndDecodeToken(new_token), null, 2)
    );

    return new_token;
  } catch (err) {
    logger.error("Error generating token:", err);
    throw err; // Or return null or custom error response
  }
};



function verifyAndDecodeToken(token) {
  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    return decoded;
  } catch (err) {
    return { error: err.message };
  }
}



const getAllUserRoles = async (req, res) => {
  try {
    const roles = await User_role.findAll({ attributes: ["id", "name"] });

    const roleList = roles
      .filter((r) => r.name !== "Admin")
      .map((r) => ({
        id: r.id,
        role_name: r.name,
      }));
    console.log("Roles: ", roleList);
    res.status(200).json({ roles: roleList });
  } catch (error) {
    logger.error(`Error fetching user roles: ${error.message}`);
    res
      .status(500)
      .json({ message: "Error fetching user roles", error: error.message });
  }
};



const createRole = async (req, res) => {
  const { name } = req.body;
  try {
    const existingRole = await User_role.findOne({ where: { name } });
    if (existingRole) {
      return res.status(400).json({ message: "Role already exists" });
    }

    const newRole = await User_role.create({
      name,
    });

    logger.info(`Role created successfully: ${newRole.name}`);
    res.status(201).json({
      message: "Role created successfully!",
      role: newRole,
    });
  } catch (error) {
    logger.error(`Error creating role: ${error.message}`);
    res
      .status(500)
      .json({ message: "Error creating role", error: error.message });
  }
};



const getUsersByRoleId = async (req, res) => {
  try {
    const user_role = await User_role.findByPk(req.params.id);
    if (!user_role) {
      return res.status(404).json({ message: "User role not found" });
    }

    const users = await User.findAll({
      where: { roleId: req.params.id },
      attributes: ["id", "name", "email", "phone_number", "salary"], // Include salary in the attributes
    });

    res.status(200).json(users);
  } catch (error) {
    console.error("Error fetching users by role ID:", error);
    res.status(500).json({ message: "Error fetching users by role ID", error });
  }
};



// Update category
const updateRole = async (req, res) => {
  try {
    const role = await User_role.findByPk(req.params.id);
    if (!role) {
      return res.status(404).json({ message: "role not found" });
    }
    console.log(req.body);
    await role.update(req.body);
    res.status(200).json(role);
  } catch (error) {
    console.error("Error updating role:", error);
    res.status(500).json({ message: "Error updating role", error });
  }
};



// Delete category
const deleteRole = async (req, res) => {
  try {
    const role = await User_role.findByPk(req.params.id);
    if (!role) {
      return res.status(404).json({ message: "role not found" });
    }
    await role.destroy();
    res.status(204).json({ message: "role deleted successfully" });
  } catch (error) {
    console.error("Error deleting role:", error);
    res.status(500).json({ message: "Error deleting role", error });
  }
};



const register = async (req, res) => {
  console.log("Request Body:", req.body);
  const { name, email, phone_number, password, role } = req.body;
  const roleId = parseInt(role);
  console.log(`\n\nRole id to register: ${roleId}`);

  try {
    const userExists = await User.findOne({ where: { email } });
    if (userExists) {
      return res.status(400).json({ message: "User already exists" });
    }

    const salt = await bcrypt.genSalt(10);
    const hashedPassword = await bcrypt.hash(password, salt);

    const user = await User.create({
      name,
      email,
      phone_number,
      password: hashedPassword,
      roleId: roleId,
    });

    const token = await generateToken(user); // ✅ FIXED HERE

    logger.info(`User created successfully: ${user.email}`);
    res.status(201).json({
      message: "User registered successfully!",
      token, // ✅ this is now a string
    });
  } catch (error) {
    logger.error(`Error registering user: ${error.message}`);
    res
      .status(500)
      .json({ message: "Error registering user", error: error.message });
  }
};



const resetPasswordViaOtp = async (req, res) => {
  try {
    const { phone, otp, newPassword } = req.body;

    // Step 1: Verify OTP
    const foundOtp = await Otp.findOne({
      where: { phone, otp: otp.toString(), verified: false }
    });

    if (!foundOtp) {
      return res.status(400).json({ message: "Invalid OTP" });
    }

    if (new Date() > foundOtp.expiresAt) {
      await Otp.destroy({ where: { phone } });
      return res.status(400).json({ message: "OTP expired" });
    }

    // Step 2: Find user by phone number
    const user = await User.findOne({
      where: { phone_number: phone }
    });

    if (!user) {
      return res.status(404).json({ message: "User not found" });
    }

    // Step 3: Hash new password
    const salt = await bcrypt.genSalt(10);
    const hashedPassword = await bcrypt.hash(newPassword, salt);

    // Step 4: Update password
    user.password = hashedPassword;
    await user.save();

    // Step 5: Delete OTP after successful password reset
    await Otp.destroy({ where: { phone } });

    logger.info(`Password reset successfully for: ${user.email}`);

    return res.json({
      message: "Password reset successfully!",
      email: user.email
    });

  } catch (error) {
    logger.error(`Error resetting password: ${error.message}`);
    return res.status(500).json({
      message: "Password reset failed",
      error: error.message
    });
  }
};




const getAllUsers = async (req, res) => {
  try {
    const users = await User.findAll({
      attributes: { exclude: ["password"] }, // Exclude sensitive data
      include: [{ model: User_role, as: "role", attributes: ["name"] }],
      order: [["id", "ASC"]], // ✅ Order by id ascending
    });
    res.status(200).json(users);
  } catch (error) {
    console.error("Error fetching users:", error);
    logger.error("Error fetching users:", error);
    res
      .status(500)
      .json({ message: "Error fetching users", error: error.message });
  }
};



const getUserById = async (req, res) => {
  try {
    const user = await User.findByPk(req.params.id, {
      attributes: { exclude: ["password"] }, // Exclude sensitive data
      include: [{ model: User_role, as: "role", attributes: ["name"] }],
    });

    if (!user) {
      return res.status(404).json({ message: "User not found" });
    }

    res.status(200).json(user);
  } catch (error) {
    console.error("Error fetching user:", error);
    logger.error("Error fetching user:", error);
    res
      .status(500)
      .json({ message: "Error fetching user", error: error.message });
  }
};




const login = async (req, res) => {
  const { emailOrPhone, password } = req.body;

  try {
    const user = await User.findOne({
      where: {
        [Op.or]: [
          { email: emailOrPhone },
          { phone_number: emailOrPhone }
        ],
      },
    });

    if (!user) {
      return res.status(400).json({ message: "Invalid credentials" });
    }

    // ❌ Block if user is not verified
    if (!user.isVerified) {
      return res.status(403).json({
        message: "Account not verified. Please contact admin."
      });
    }



    const isMatch = await bcrypt.compare(password, user.password);

    if (!isMatch) {
      return res.status(400).json({ message: "Invalid credentials" });
    }

    // ✅ Mark user active on login
    user.isActive = true;
    await user.save();

    const token = await generateToken(user);

    const safeUser = await User.findByPk(user.id, {
      attributes: { exclude: ["password"] }
    });

    return res.json({
      message: "Login successful!",
      token,
      user: safeUser
    });

  } catch (error) {
    return res.status(500).json({
      message: "Login failed",
      error: error.message
    });
  }
};


const getUnverifiedUsers = async (req, res) => {
  try {
    const users = await User.findAll({
      where: { isVerified: false },
      attributes: { exclude: ["password"] },
      include: [{ model: User_role, as: "role", attributes: ["name"] }],
      order: [["id", "ASC"]],
    });

    return res.status(200).json({
      users
    });

  } catch (error) {
    return res.status(500).json({
      message: "Error fetching unverified users",
      error: error.message
    });
  }
};


const verifyUser = async (req, res) => {
  try {

    const user = await User.findByPk(req.params.userId);

    if (!user) {
      return res.status(404).json({
        message: "User not found"
      });
    }

    user.isVerified = true;
    await user.save();

    return res.json({
      message: "User verified successfully"
    });

  } catch (error) {
    return res.status(500).json({
      message: "Verification failed",
      error: error.message
    });
  }
};



const logout = async (req, res) => {
  const { userId } = req.params;

  try {
    const user = await User.findByPk(userId);

    if (!user) {
      return res.status(404).json({ message: "User not found" });
    }

    // 🔴 Send FCM force-logout notification BEFORE clearing the token
    if (user.fcm_token && user.fcm_token.length > 0) {
      try {
        const admin = require("../../configs/firebaseAdmin");
        await admin.messaging().send({
          token: user.fcm_token,
          data: {
            type: "force_logout",
            title: "Session Ended",
            body: "Admin has logged you out. Please login again.",
          },
          // Also show as a visible notification
          notification: {
            title: "Session Ended",
            body: "Admin has logged you out. Please login again.",
          },
        });
        console.log(`📤 Force-logout FCM sent to user ${userId}`);
      } catch (fcmErr) {
        console.error("FCM send error (non-fatal):", fcmErr.message);
      }
    }

    // Now clear the token, mark inactive, and revoke verification
    user.fcm_token = "";
    user.isActive = false;
    user.isVerified = false;
    await user.save();

    // Also emit socket event as secondary mechanism
    const io = req.app.get("io");
    io.to(`user_${userId}`).emit("force_logout");

    res.status(200).json({
      message: "Logout successful. User forced to logout."
    });

  } catch (error) {
    console.error("Error during logout:", error);
    res.status(500).json({
      message: "Error during logout",
      error: error.message
    });
  }
};



const deleteUser = async (req, res) => {
  const { userId } = req.params;

  try {
    const user = await User.findByPk(userId);

    if (!user) {
      return res.status(404).json({ message: "User not found" });
    }

    // Optionally, you can add a check here to ensure only the user themselves
    // or an admin can delete the account (based on JWT token payload)

    await user.destroy();

    logger.info(`User deleted successfully: ${user.email}`);
    res.status(200).json({ message: "User account deleted successfully" });
  } catch (error) {
    logger.error(`Error deleting user: ${error.message}`);
    res
      .status(500)
      .json({ message: "Error deleting user", error: error.message });
  }
};



const getOrdersByUserId = async (req, res) => {
  try {
    // Fetch drink orders for the user by userId and sort by id in descending order
    const drink_orders = await DrinksOrder.findAll({
      where: { userId: req.params.userId },
      include: [
        { model: DrinksMenu, as: "drink", attributes: ["name", "price"] },
        { model: Section, as: "section", attributes: ["name"] },
      ],
      order: [["id", "DESC"]], // Sorting by id DESC
    });

    // Fetch food orders for the user by userId and sort by id in descending order
    const food_orders = await Order.findAll({
      where: { userId: req.params.userId },
      include: [
        { model: Menu, as: "menu", attributes: ["name", "price"] },
        { model: Section, as: "section", attributes: ["name"] },
      ],
      order: [["id", "DESC"]], // Sorting by id DESC
    });

    // If no drink or food orders found, return a 404
    if (!drink_orders.length && !food_orders.length) {
      return res.status(404).json({ message: "No orders found for this user" });
    }

    // Combine drink_orders and food_orders into a single array
    const all_orders = [...drink_orders, ...food_orders];

    // Function to map status to a priority value
    const getStatusPriority = (status) => {
      switch (status) {
        case "pending":
          return 1; // 'pending' has the highest priority
        case "accepted":
          return 2; // 'accepted' comes next
        case "completed":
          return 3; // 'completed' has the lowest priority
        default:
          return 4; // Any other status is treated as lowest priority
      }
    };

    // Function to sort orders based on status priority
    const sortByStatus = (orders) => {
      return orders.sort((a, b) => {
        const statusA = getStatusPriority(a.status);
        const statusB = getStatusPriority(b.status);

        return statusA - statusB; // Sort in ascending order of priority
      });
    };

    // Sort all orders by status priority
    const sortedOrders = sortByStatus(all_orders);

    // Return all sorted orders
    res.json({
      orders: sortedOrders,
    });
  } catch (error) {
    console.error("Error fetching orders for user:", error);
    res
      .status(500)
      .json({ message: "Error fetching orders", error: error.message });
  }
};



const getScoreForToday = async (req, res) => {
  try {
    // Fetch the order items, including food and drink items with the appropriate conditions
    const score = await OrderItem.findAll({
      include: [
        {
          model: Menu,
          as: "menu",
          attributes: ["name"],
          required: true, // Only include the menu if it exists (food items)
          where: { food: true }, // Ensure only food items are included
        },
        {
          model: DrinksMenu,
          as: "drink",
          attributes: ["name"],
          required: false, // Allow for order items without drinks (food-only items)
          where: { food: false }, // Ensure only drink items are included
        },
        {
          model: User,
          as: "user",
          attributes: ["name"],
        },
      ],
    });

    // Return the score in the response
    res.status(200).json(score);
  } catch (error) {
    console.error("Error fetching score:", error);
    logger.error("Error fetching score:", error);
    res
      .status(500)
      .json({ message: "Error fetching score", error: error.message });
  }
};




// ---------------- FAST2SMS OTP SENDER ----------------
const axios = require("axios");

async function sendFast2SmsOtp(phone, otp) {
  const apiKey = process.env.FAST2SMS_API_KEY;

  const payload = {
    route: "dlt",
    sender_id: "NKIDFS",
    message: "208958",
    variables_values: otp,
    flash: 0,
    numbers: phone
  };

  try {
    const response = await axios.post(
      "https://www.fast2sms.com/dev/bulkV2",
      payload,
      {
        headers: {
          authorization: apiKey,
          "Content-Type": "application/json"
        }
      }
    );

    if (!response.data.return) {
      console.error("SMS Failed:", response.data);
      return false;
    }

    return true;

  } catch (error) {
    console.error("Fast2SMS Error:", error.response?.data || error.message);
    return false;
  }
}



const sendOtp = async (req, res) => {
  try {
    const { phone } = req.body;

    const user = await User.findOne({ where: { phone_number: phone } });
    if (!user) {
      return res.status(404).json({ message: "Mobile number not registered" });
    }

    await Otp.destroy({ where: { phone } });

    const otp = Math.floor(100000 + Math.random() * 900000).toString();

    await Otp.create({
      phone,
      otp,
      expiresAt: new Date(Date.now() + 2 * 60 * 1000),
      verified: false
    });

    const smsSent = await sendFast2SmsOtp(phone, otp);

    if (!smsSent) {
      return res.status(500).json({ message: "Failed to send OTP" });
    }

    return res.json({ message: "OTP sent successfully!" });

  } catch (error) {
    return res.status(500).json({ message: "Failed to send OTP", error: error.message });
  }
};


const sendPasswordResetOtp = async (req, res) => {
  try {
    const { phone } = req.body;

    const user = await User.findOne({ where: { phone_number: phone } });
    if (!user) {
      return res.status(404).json({ message: "Mobile number not registered" });
    }

    await Otp.destroy({ where: { phone } });

    const otp = Math.floor(100000 + Math.random() * 900000).toString();

    await Otp.create({
      phone,
      otp,
      expiresAt: new Date(Date.now() + 2 * 60 * 1000),
      verified: false
    });

    const payload = {
      route: "dlt",
      sender_id: "NKIDFS",
      message: "209035",       // ← password reset template ID
      variables_values: otp,
      flash: 0,
      numbers: phone
    };

    try {
      const response = await axios.post(
        "https://www.fast2sms.com/dev/bulkV2",
        payload,
        {
          headers: {
            authorization: process.env.FAST2SMS_API_KEY,
            "Content-Type": "application/json"
          }
        }
      );

      if (!response.data.return) {
        console.error("SMS Failed:", response.data);
        return res.status(500).json({ message: "Failed to send OTP" });
      }
    } catch (smsError) {
      console.error("Fast2SMS Error:", smsError.response?.data || smsError.message);
      return res.status(500).json({ message: "Failed to send OTP" });
    }

    return res.json({ message: "Password reset OTP sent successfully!" });

  } catch (error) {
    return res.status(500).json({ message: "Failed to send OTP", error: error.message });
  }
};


const verifyOtp = async (req, res) => {
  try {
    const { phone, otp } = req.body;

    const foundOtp = await Otp.findOne({
      where: { phone, otp: otp.toString(), verified: false }
    });

    if (!foundOtp) {
      return res.status(400).json({ message: "Invalid OTP" });
    }

    if (new Date() > foundOtp.expiresAt) {
      await Otp.destroy({ where: { phone } });
      return res.status(400).json({ message: "OTP expired" });
    }

    // Delete OTP after success
    await Otp.destroy({ where: { phone } });

    const user = await User.findOne({
      where: { phone_number: phone }
    });

    const token = await generateToken(user);

    const safeUser = await User.findByPk(user.id, {
      attributes: { exclude: ["password"] }
    });

    return res.json({
      message: "OTP Verified!",
      token,
      user: safeUser
    });

  } catch (error) {
    return res.status(500).json({
      message: "OTP verification failed",
      error: error.message
    });
  }
};



module.exports = {
  register,
  login,
  getUnverifiedUsers,
  verifyUser,
  logout,
  deleteUser,
  getAllUserRoles,
  createRole,
  getAllUsers,
  updateRole,
  deleteRole,
  getUsersByRoleId,
  getUserById,
  getOrdersByUserId,
  getScoreForToday,
  sendOtp,
  verifyOtp,
  resetPasswordViaOtp,
  sendPasswordResetOtp,
};
