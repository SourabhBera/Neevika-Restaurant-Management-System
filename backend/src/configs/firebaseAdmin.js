const admin = require('firebase-admin');
const serviceAccount = require('./k-restaurant-eef0f-firebase-adminsdk-fbsvc-8348c5d5bc.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

module.exports = admin;
