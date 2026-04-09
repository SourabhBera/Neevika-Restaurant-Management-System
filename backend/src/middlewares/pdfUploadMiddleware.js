// const multer = require('multer');
// const fs = require('fs');
// const path = require('path');

// // Define the path to the 'uploads/pdfs' folder
// const projectRoot = path.resolve(__dirname, '../..');
// const pdfFolder = path.join(projectRoot, 'uploads', 'leaves');

// // Ensure the 'pdfs' folder exists
// if (!fs.existsSync(pdfFolder)) {
//   fs.mkdirSync(pdfFolder, { recursive: true });
// }

// // Configure multer storage
// const storage = multer.diskStorage({
//   destination: function (req, file, cb) {
//     cb(null, pdfFolder);
//   },
//   filename: function (req, file, cb) {
//     const timestamp = Date.now();
//     const uniqueName = `${timestamp}-${file.originalname}`;
//     cb(null, uniqueName);
//   }
// });

// // File filter to allow only PDFs
// function pdfFileFilter(req, file, cb) {
//   console.log('Uploaded file:', {
//     name: file.originalname,
//     mimetype: file.mimetype,
//     ext: path.extname(file.originalname).toLowerCase(),
//   });

//   const ext = path.extname(file.originalname).toLowerCase();
//   const isPdfExtension = ext === '.pdf';

//   if (file.mimetype === 'application/pdf' || isPdfExtension) {
//     cb(null, true);
//   } else {
//     cb(new Error('Only PDF files are allowed!'), false);
//   }
// }


// // Set up multer for PDF upload only
// const uploadPDF = multer({
//   storage: storage,
//   fileFilter: pdfFileFilter,
//   limits: { fileSize: 10 * 1024 * 1024 } // 10MB limit
// }).single('pdf_file'); // 'pdf_file' should match the form field name

// module.exports = uploadPDF;







const multer = require('multer');
const fs = require('fs');
const path = require('path');

/**
 * Create a multer middleware that uploads a single PDF file to a given subfolder.
 *
 * @param {string} subfolder - Subfolder inside 'uploads/' (e.g., 'leaves')
 * @param {string} fieldName - Name of the form field (e.g., 'pdf_file')
 * @returns {function} Multer middleware
 */
function createPDFUploadMiddleware(subfolder, fieldName) {
  const projectRoot = path.resolve(__dirname, '../..');
  const targetFolder = path.join(projectRoot, 'uploads', subfolder);

  // Ensure the folder exists
  if (!fs.existsSync(targetFolder)) {
    fs.mkdirSync(targetFolder, { recursive: true });
  }

  const storage = multer.diskStorage({
    destination: function (req, file, cb) {
      cb(null, targetFolder);
    },
    filename: function (req, file, cb) {
      cb(null, `${Date.now()}-${file.originalname}`);
    }
  });

  const pdfFileFilter = (req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase();
    const isPDF = file.mimetype === 'application/pdf' || ext === '.pdf';
    if (isPDF) {
      cb(null, true);
    } else {
      cb(new Error('Only PDF files are allowed!'), false);
    }
  };

  return multer({
    storage,
    fileFilter: pdfFileFilter,
    limits: { fileSize: 10 * 1024 * 1024 } // 10MB max
  }).single(fieldName);
}

module.exports = createPDFUploadMiddleware;
