


const multer = require('multer');
const fs = require('fs');
const path = require('path');

/**
 * Returns a multer middleware configured to upload files to a specific subfolder inside 'uploads'
 * 
 * @param {string} subfolder - The name of the folder inside 'uploads' where files should be saved
 * @param {string} fieldName - The name of the field to use for uploading the file (e.g., 'receipt_image')
 */
function createUploadMiddleware(subfolder, fieldName) {
  const projectRoot = path.resolve(__dirname, '../..'); // Adjust as needed
  const uploadPath = path.join(projectRoot, 'uploads', subfolder);

  // Ensure the folder exists
  if (!fs.existsSync(uploadPath)) {
    fs.mkdirSync(uploadPath, { recursive: true });
  }

  const storage = multer.diskStorage({
    destination: function (req, file, cb) {
      cb(null, uploadPath);
    },
    filename: function (req, file, cb) {
      cb(null, Date.now() + '-' + file.originalname);
    }
  });

  return multer({ storage }).single(fieldName);
}

module.exports = createUploadMiddleware;
