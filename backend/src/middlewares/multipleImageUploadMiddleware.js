const multer = require('multer');
const fs = require('fs');
const path = require('path');

/**
 * Returns a multer middleware configured to upload multiple files to a specific subfolder inside 'uploads'
 * 
 * @param {string} subfolder - The name of the folder inside 'uploads' where files should be saved
 * @param {string} fieldName - The name of the field to use for uploading the files (e.g., 'images')
 * @param {number} maxCount - Maximum number of files allowed
 */
function createUploadMiddleware(subfolder, fieldName, maxCount = 5) {
  const projectRoot = path.resolve(__dirname, '../..'); 
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

  return multer({ storage }).array(fieldName, maxCount);
}

module.exports = createUploadMiddleware;
