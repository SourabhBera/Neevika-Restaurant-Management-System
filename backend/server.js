const express = require("express");
const logger = require("./src/configs/logger");
const requestLogger = require("./src/middlewares/requestLogger");
const routes = require("./src/routes/server");
const cors = require("cors");
const path = require("path");
const db = require("./src/configs/db");
const { User } = require("./src/models");
const bodyParser = require("body-parser");
const app = express();

const PORT = process.env.PORT || 3000;
const socketIO = require("socket.io");

//Cron Jobs
require("./src/jobs/daySummaryCron");
require("./src/jobs/generateMonthlyPayrollCron");

// Admin Routes
const adminRoutes = require("./src/routes/AdminRoutes/adminRoutes");

// Authentication Routes
const authRoutes = require("./src/routes/AuthenticationRoutes/authRoutes");

// Drinks Routes
const drinksInventoryRoutes = require("./src/routes/DrinksRoutes/drinksInventoryRoutes");
const drinksPurchaseHistoryRoutes = require("./src/routes/DrinksRoutes/drinksPurchaseHistoryRoutes");
const drinksOrderRoutes = require("./src/routes/DrinksRoutes/drinksOrderRoutes");
const drinksMenuRoutes = require("./src/routes/DrinksRoutes/drinksMenuRoutes");
const drinksCategoryRoutes = require("./src/routes/DrinksRoutes/drinksCategoryRoutes");
const drinksKitchenRoutes = require("./src/routes/DrinksRoutes/drinksKitchenRoutes");
const drinksIngredientRoutes = require("./src/routes/DrinksRoutes/drinksIngredientRoutes");
const drinksMenuIngredientRoutes = require("./src/routes/DrinksRoutes/drinksMenuIngredientRoutes");
const drinksCanceledDrinkRoutes = require("./src/routes/CanceledRoutes/canceledDrinksRoute");

// Food Routes
const categoryRoutes = require("./src/routes/FoodRoutes/categoryRoutes");
const menuRoutes = require("./src/routes/FoodRoutes/menuRoutes");
const orderRoutes = require("./src/routes/FoodRoutes/orderRoutes");
const inventoryRoutes = require("./src/routes/FoodRoutes/inventoryRoutes");
const kitchenRoutes = require("./src/routes/FoodRoutes/kitchenRoutes");
const purchaseHistoryRoutes = require("./src/routes/FoodRoutes/purchaseHistoryRoutes");
const ingredientRoutes = require("./src/routes/FoodRoutes/ingredientRoutes");
const menuIngredientRoutes = require("./src/routes/FoodRoutes/menuIngredientRoutes");
const foodsCanceledDrinkRoutes = require("./src/routes/CanceledRoutes/canceledFoodsRoute");

//Complimentary Profile Routes
const complimentaryProfileRoutes = require("./src/routes/ComplimentaryProfileRoutes/complimentaryProfileRoutes");

//Section Routes
const sectionRoutes = require("./src/routes/SectionTableRoutes/sectionRoutes");

//Table Routes
const tableRoutes = require("./src/routes/SectionTableRoutes/tableRoutes");

// Vendor Routes
const vendorRoutes = require("./src/routes/VendorRoutes/vendorRoutes");

// Crm Routes
const CrmRoutes = require("./src/routes/CrmRoutes/customerDetailsRoutes");

//CRM QR Routes
const CrmQRRoutes = require("./src/routes/CrmRoutes/customerDetailQRRoutes");

//CRM QR Offer Routes
const CrmQrOfferRoutes = require("./src/routes/CrmRoutes/qrOfferRoutes");

// HR Routes
const HrRoutes = require("./src/routes/HrRoutes/hrRoutes");

// Face Enroll Routes
// const EnrollRoutes = require('./src/routes/HrRoutes/enrollRoutes');

// Accounting Routes
const expenseRoutes = require("./src/routes/AccountingRoutes/expenseRoutes");

// Payroll Routes
const payrollRoutes = require("./src/routes/AccountingRoutes/payrollRoutes");

// Profit & Loss Routes
const profitLossRoutes = require("./src/routes/AccountingRoutes/profitLossRoutes");

// Other Reports Routes
const OtherReportsRoutes = require("./src/routes/ReportsRoutes/OtherReportsRoutes");

// Logs Routes
const LogsRoutes = require("./src/routes/LogsRoutes/logsRoutes");

// Incident Routes
const IncidentRoutes = require("./src/routes/IncidentRoutes/incidentRoutes");

// Notification Routes
const sendNotification = require("./src/utils/sendNotification");

// Disable Etag for error 304
app.disable('etag');

// Middleware to log requests
app.use(requestLogger);

app.use(cors());

// Parse incoming requests
app.use(express.json());
app.use(express.urlencoded({ extended: false }));
app.use(bodyParser.json());

// Serve static files from the 'uploads' directory
app.use("/uploads", express.static(path.join(__dirname, "uploads")));

// FCM Token saving route
app.post("/api/save-token", async (req, res) => {
  const { userId, token } = req.body;
  console.log(userId);

  if (!userId || !token) {
    return res.status(400).json({ message: "Missing userId or token" });
  }

  try {
    const [updated] = await User.update(
      { fcm_token: token },
      { where: { id: userId } }
    );

    if (updated) {
      res.status(200).json({ message: "FCM Token saved successfully" });
    } else {
      res.status(404).json({ message: "User not found" });
    }
  } catch (err) {
    console.error("Error saving FCM token:", err);
    res.status(500).json({ message: "Internal server error" });
  }
});

// Notify user route
app.post("/api/notify-user/", async (req, res) => {
  const { userId, title, message } = req.body;
  console.log(`ServerID: ${userId}`);
  if (!userId || !title || !message) {
    return res
      .status(400)
      .json({ message: "Missing userId, title, or message" });
  }

  try {
    const user = await User.findByPk(userId);
    if (!user || !user.fcm_token) {
      return res.status(404).json({ message: "User or FCM token not found" });
    }

    const result = await sendNotification(user.fcm_token, title, message);
    res.status(200).json({ message: "Notification sent", result });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: "Error sending notification" });
  }
});

// Load routes
app.use("/api", routes);

// Routes
app.use("/api/auth", authRoutes);
app.use("/api/inventory", inventoryRoutes);
app.use("/api/purchaseHistory", purchaseHistoryRoutes);
app.use("/api/orders", orderRoutes);
app.use("/api/canceledFoodOrders", foodsCanceledDrinkRoutes);
app.use("/api/canceledDrinkOrders", drinksCanceledDrinkRoutes);
app.use("/api/menu", menuRoutes);
app.use("/api/categories", categoryRoutes);
app.use("/api/sections", sectionRoutes);
app.use("/api/tables", tableRoutes);
app.use("/api/kitchen-inventory", kitchenRoutes);
app.use("/api/ingredients", ingredientRoutes);
app.use("/api/menu-ingredients", menuIngredientRoutes);

//

app.use("/api/complimentaryProfiles", complimentaryProfileRoutes);
app.use("/api/admin", adminRoutes);
app.use("/api/vendor", vendorRoutes);
app.use("/api/crm", CrmRoutes);
app.use("/api/crm/QR", CrmQRRoutes);
app.use("/api/crm/QR-offer", CrmQrOfferRoutes);
app.use("/api/hr", HrRoutes);
// app.use('/api/enroll-face', EnrollRoutes);
app.use("/api/accounting", expenseRoutes);
app.use("/api/payroll", payrollRoutes);
app.use("/api/profit-loss", profitLossRoutes);
app.use("/api/other-reports", OtherReportsRoutes);
app.use("/api/logs", LogsRoutes);
app.use("/api/incident-report", IncidentRoutes);

//Drinks
app.use("/api/drinks-orders", drinksOrderRoutes);
app.use("/api/drinks-menu", drinksMenuRoutes);
app.use("/api/drinks-inventory", drinksInventoryRoutes);
app.use("/api/drinks-purchaseHistory", drinksPurchaseHistoryRoutes);
app.use("/api/drinks-categories", drinksCategoryRoutes);
app.use("/api/drinks-kitchen-inventory", drinksKitchenRoutes);
app.use("/api/drinks-ingredients", drinksIngredientRoutes);
app.use("/api/drinks-menu-ingredients", drinksMenuIngredientRoutes);

// Error handling
app.use((err, req, res, next) => {
  logger.error(err.stack);

  if (res.headersSent) {
    return next(err);
  }

  res.status(500).json({
    message: "Internal Server Error",
  });
});



const http = require("http");
const server = http.createServer(app);

// Initialize Socket.IO
const io = socketIO(server, {
  cors: {
    origin: "*", // adjust as needed for security
    methods: ["GET", "POST"],
  },
  maxHttpBufferSize: 1e6, // 1MB
  pingInterval: 25000,
  pingTimeout: 60000,
});

// Attach io instance to app so it can be accessed in routes
app.set("io", io);

// Handle socket connections
io.on("connection", (socket) => {
  console.log(`🔌 Client connected: ${socket.id}`);

  // Allow clients to join their user-specific room for force-logout
  socket.on("join_user_room", (userId) => {
    if (userId) {
      socket.join(`user_${userId}`);
      console.log(`👤 Socket ${socket.id} joined room user_${userId}`);
    }
  });



socket.on("error", (error) => {
  if (
    error.code === "ECONNRESET" ||
    error.message?.includes("ECONNRESET")
  ) {
    return;
  }
  console.error(`❌ Socket error for ${socket.id}:`, error);
});



  socket.on("disconnect", () => {
    console.log(`❌ Client disconnected: ${socket.id}`);
  });
});


server.on("clientError", (err, socket) => {
  if (err.code === "ECONNRESET" || !socket.writable) {
    return; // ignore silently
  }
  socket.end("HTTP/1.1 400 Bad Request\r\n\r\n");
});



// Handle server errors
server.on("error", (error) => {
  console.error("❌ Server error:", error);
  if (error.code === "EADDRINUSE") {
    console.error(`Port ${PORT} is already in use. Exiting...`);
    process.exit(1);
  }
});

// Handle uncaught exceptions
process.on("uncaughtException", (error) => {
  const isConnReset =
    error.code === "ECONNRESET" ||
    error.message?.includes("ECONNRESET");

  if (isConnReset) {
    console.warn("⚠️ Ignored ECONNRESET");
    return;
  }

  console.error("❌ Uncaught Exception:", error);
  console.error("Error Stack:", error.stack);
  logger.error("Uncaught Exception: " + error.stack);
  logger.error("Error Details: " + JSON.stringify({
    code: error.code,
    message: error.message,
    name: error.name
  }));

  // ❗ DO NOT exit for now (important for debugging)
  // process.exit(1);
});



// Handle unhandled promise rejections
process.on("unhandledRejection", (reason, promise) => {
  const isConnReset =
    reason?.code === "ECONNRESET" ||
    reason?.message?.includes("ECONNRESET");

  if (isConnReset) {
    console.warn("⚠️ Ignored ECONNRESET (promise)");
    return;
  }

  console.error("❌ Unhandled Rejection at:", promise, "reason:", reason);
  console.error("Rejection Stack:", reason?.stack);
  logger.error("Unhandled Rejection: " + reason);
  if (reason?.stack) {
    logger.error("Rejection Stack: " + reason.stack);
  }
});



// Graceful shutdown
process.on("SIGTERM", () => {
  console.log("SIGTERM signal received: closing HTTP server");
  server.close(() => {
    console.log("HTTP server closed");
    process.exit(0);
  });
});

process.on("SIGINT", () => {
  console.log("SIGINT signal received: closing HTTP server");
  server.close(() => {
    console.log("HTTP server closed");
    process.exit(0);
  });
});

// Start the server
const serverInstance = server.listen(PORT, "0.0.0.0", () => {
  console.log(`🚀 Server running with Socket.IO on http://localhost:${PORT}`);
}).on("error", (err) => {
  console.error("❌ Server startup error:", err);
  console.error("Error Code:", err.code);
  console.error("Error Stack:", err.stack);
  logger.error("Server startup error: " + err.stack);
  
  if (err.code === "EADDRINUSE") {
    console.error(`Port ${PORT} is already in use.`);
  }
});



module.exports = app;
