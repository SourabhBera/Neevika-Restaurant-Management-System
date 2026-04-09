const express = require('express');
const multer = require('multer');
const path = require('path');
const { enrollFace } = require('../../controllers/HrController/enrollFace'); // Adjust path as per your project 

const router = express.Router();

// Multer setup
const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, 'uploads/'),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname);
    cb(null, `${Date.now()}${ext}`);
  },
});
const upload = multer({ storage });

// POST /api/enroll-face
router.post('/enroll-face', upload.single('image'), enrollFace);

module.exports = router;
