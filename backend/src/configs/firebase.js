const admin = require("firebase-admin");
const serviceAccount = require("./serviceAccountKey.json"); // put it safely in your server

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

module.exports = admin;
