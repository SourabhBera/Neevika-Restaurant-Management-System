const multer = require('multer');

const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    if (file.fieldname === 'receipt_image') {
      cb(null, 'uploads/purchase_receipts/');
    } else if (file.fieldname === 'excel_file') {
      cb(null, 'uploads/excel-uploads/inventory-purchases/');
    } else {
      cb(new Error('Unexpected field'));
    }
  },
  filename: function (req, file, cb) {
    cb(null, Date.now() + '-' + file.originalname);
  }
});

const upload = multer({ storage });

const uploadFields = upload.fields([
  { name: 'receipt_image', maxCount: 1 },
  { name: 'excel_file', maxCount: 1 }
]);

module.exports = { uploadFields };
