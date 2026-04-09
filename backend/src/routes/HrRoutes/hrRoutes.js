const express = require('express');
const router = express.Router();

const {
  markAttendance,
  getEmployeeAttendance,
  getAttendanceByDate,
  getAllUsersAttendanceForToday,
  uploadAppointmentLetter,
  uploadLeaveLetter,
  downloadAttendanceInRange
} = require('../../controllers/HrController/hrController');

// Reusable PDF upload middleware
const createPDFUploadMiddleware = require('../../middlewares/pdfUploadMiddleware');

// Create specific middleware for each upload field/folder
const uploadAppointmentPDF = createPDFUploadMiddleware('appointments', 'pdf_file'); // uploads/appointments/
const uploadLeavePDF = createPDFUploadMiddleware('leaves', 'pdf_file');             // uploads/leaves/

// Routes
router.post('/attendance', markAttendance);
router.get('/attendance-today', getAllUsersAttendanceForToday);
router.get('/attendance/download', downloadAttendanceInRange);


router.put('/appointment/:id', uploadAppointmentPDF, uploadAppointmentLetter);
router.put('/leave/:id', uploadLeavePDF, uploadLeaveLetter);  

router.get('/attendance/:employeeId', getEmployeeAttendance);
router.get('/attendance/date/:date', getAttendanceByDate);

module.exports = router;
