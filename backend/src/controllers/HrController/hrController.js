const { Attendance, User, User_role } = require('../../models');
const { Sequelize } = require('sequelize');
const ExcelJS = require('exceljs');

const downloadAttendanceInRange = async (req, res) => {
  const { startDate, endDate } = req.query;

  if (!startDate || !endDate) {
    return res.status(400).json({ error: 'Start date and end date are required.' });
  }

  try {
    const start = new Date(startDate);
    const end = new Date(endDate);
    end.setUTCDate(end.getUTCDate() + 1); // Include end date fully

    // Generate list of dates in range (YYYY-MM-DD)
    const dates = [];
    const tempDate = new Date(start);
    while (tempDate < end) {
      dates.push(new Date(tempDate).toISOString().split('T')[0]);
      tempDate.setUTCDate(tempDate.getUTCDate() + 1);
    }

    // Fetch all users with their roles
    let users = await User.findAll({
      include: [
        {
          model: User_role,
          as: 'role',
          attributes: ['name'],
        },
      ],
      attributes: ['id', 'name'],
    });

    // Sort users by role and name
    users = users.sort((a, b) => {
      const roleA = a.role?.name || '';
      const roleB = b.role?.name || '';
      const nameA = a.name.toLowerCase();
      const nameB = b.name.toLowerCase();

      if (roleA < roleB) return -1;
      if (roleA > roleB) return 1;
      return nameA.localeCompare(nameB);
    });

    // Fetch all attendance records in the range
    const attendanceRecords = await Attendance.findAll({
      where: {
        date: {
          [Sequelize.Op.gte]: start,
          [Sequelize.Op.lt]: end,
        },
      },
      include: [
        {
          model: User,
          as: 'employee',
          attributes: ['id'],
        },
      ],
    });

    // Map attendance by employeeId + date
    const attendanceMap = {};
    attendanceRecords.forEach(record => {
      const dateStr = new Date(record.date).toISOString().split('T')[0];
      const key = `${record.employee_id}_${dateStr}`;
      attendanceMap[key] = record.status.toLowerCase();
    });

    // Create Excel workbook
    const workbook = new ExcelJS.Workbook();
    const worksheet = workbook.addWorksheet('Attendance');

    // Header: Name | Role | Dates... | Total Days | Total Present | Total Absent
    const headerRow = ['Name', 'Role', ...dates, 'Total Days', 'Total Present', 'Total Absent'];
    worksheet.addRow(headerRow);

    // Populate each user row
    users.forEach(user => {
      let presentCount = 0;
      let absentCount = 0;

      const rowData = [user.name, user.role?.name || ''];

      // Fill attendance status for each date
      dates.forEach(date => {
        const key = `${user.id}_${date}`;
        const status = attendanceMap[key] || 'absent'; // default to absent
        rowData.push(status);

        if (status === 'present') presentCount++;
        else absentCount++;
      });

      // Add summary columns
      rowData.push(dates.length);   // Total Days
      rowData.push(presentCount);   // Total Present
      rowData.push(absentCount);    // Total Absent

      // Add row to worksheet
      const row = worksheet.addRow(rowData);

      // Highlight "absent" cells in red
      dates.forEach((_, index) => {
        const cell = row.getCell(3 + index); // offset: 1=Name, 2=Role, then dates
        if (cell.value === 'absent') {
          cell.fill = {
            type: 'pattern',
            pattern: 'solid',
            fgColor: { argb: 'FFFFC7CE' }, // Light red
            bgColor: { argb: 'FFFFC7CE' },
          };
          cell.font = { color: { argb: 'FF9C0006' }, bold: true };
        }
      });
    });

    // Optional: Auto-size columns
    worksheet.columns.forEach(column => {
        let maxLength = column.header ? column.header.toString().length : 10;
        column.eachCell({ includeEmpty: true }, cell => {
            const cellValue = cell.value ? cell.value.toString() : '';
            if (cellValue.length > maxLength) maxLength = cellValue.length;
        });
    column.width = maxLength + 2;
    });

    // Set download headers
    res.setHeader(
      'Content-Type',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    );
    res.setHeader(
      'Content-Disposition',
      `attachment; filename=attendance_${startDate}_to_${endDate}.xlsx`
    );

    await workbook.xlsx.write(res);
    res.status(200).end();
  } catch (error) {
    console.error('Error generating attendance Excel:', error);
    res.status(500).json({ error: 'Failed to download attendance report.' });
  }
};



// Controller to mark attendance
const markAttendance = async (req, res) => {
    const { employee_id, status, date } = req.body;
    console.log(employee_id, status, date);

    if (!employee_id || !status || !date) {
        return res.status(400).json({ error: 'Missing required fields.' });
    }

    try {
        const employee = await User.findByPk(employee_id);
        if (!employee) {
            return res.status(404).json({ error: 'Employee not found.' });
        }

        // Parse the input date as UTC (from client as UTC or IST)
        let inputDate = new Date(date);

        // If the input date is in UTC (and not in local timezone), we should ensure it's treated correctly
        if (inputDate.toString().includes('UTC')) {
            // If the date is already in UTC, no need to adjust it
            console.log("Input date is in UTC:", inputDate);
        } else {
            // Otherwise, treat the date as IST (UTC+5:30) and convert it to UTC
            const istOffsetMs = 5.5 * 60 * 60 * 1000; // 5.5 hours in milliseconds
            inputDate = new Date(inputDate.getTime() - istOffsetMs); // Convert IST to UTC
            console.log("Converted to UTC from IST:", inputDate);
        }

        // Save the converted UTC date in the DB
        const attendance = await Attendance.create({
            employee_id,
            status,
            date: inputDate.toISOString(), // Save as UTC format
            marked_by: 3,
        });

        return res.status(201).json({
            message: 'Attendance marked successfully',
            attendance,
        });
    } catch (err) {
        console.error(err);
        return res.status(500).json({ error: 'Error marking attendance' });
    }
};


// Controller to fetch attendance records for a particular employee
const getEmployeeAttendance = async (req, res) => {
    const { employeeId } = req.params;

    try {
        // Fetch attendance records for the specified employee
        const attendanceRecords = await Attendance.findAll({
            where: {
                employee_id: employeeId,
            },
            include: [
                {
                    model: User,
                    as: 'employee', // Alias for employee data
                    attributes: ['id', 'name', 'email'], // Fetch only essential details
                },
                {
                    model: User,
                    as: 'hr', // Alias for HR user who marked the attendance
                    attributes: ['id', 'name', 'email'], // Fetch HR user details
                },
            ],
        });

        if (attendanceRecords.length === 0) {
            return res.status(404).json({
                message: 'No attendance records found for this employee.',
            });
        }

        return res.status(200).json(attendanceRecords);
    } catch (err) {
        console.error(err);
        return res.status(500).json({ error: 'Error fetching attendance records' });
    }
};

// Controller to fetch attendance records for a specific day
const getAttendanceByDate = async (req, res) => {
    const { date } = req.params;

    try {
        // Convert the provided date string to a Date object and reset the time to midnight UTC
        const providedDate = new Date(date);
        
        // Set the start of the day (midnight UTC)
        const startOfDay = new Date(Date.UTC(providedDate.getUTCFullYear(), providedDate.getUTCMonth(), providedDate.getUTCDate()));
        
        // Set the end of the day (23:59:59 UTC)
        const endOfDay = new Date(startOfDay);
        endOfDay.setUTCDate(endOfDay.getUTCDate() + 1); // Adding 1 day to get the end of the day
        
        // Log the start and end of the day for debugging
        console.log(`Start of day: ${startOfDay.toISOString()}`);
        console.log(`End of day: ${endOfDay.toISOString()}`);

        // Fetch attendance records for the specified date, ignoring time
        const attendanceRecords = await Attendance.findAll({
            where: {
                date: {
                    [Sequelize.Op.gte]: startOfDay,
                    [Sequelize.Op.lt]: endOfDay,
                },
            },
            include: [
                {
                    model: User,
                    as: 'employee',
                    attributes: ['id', 'name', 'email', 'roleId'],  // Include roleId
                    include: [
                        {
                            model: User_role, // Include role data from User_role model
                            as: 'role',       // Alias for the role
                            attributes: ['name'], // Get the role name
                        }
                    ]
                },
                {
                    model: User,
                    as: 'hr',
                    attributes: ['id', 'name', 'email'],
                },
            ],
        });

        if (attendanceRecords.length === 0) {
            return res.status(404).json({
                message: 'No attendance records found for this date.',
            });
        }

        return res.status(200).json(attendanceRecords);
    } catch (err) {
        console.error(err);
        return res.status(500).json({ error: 'Error fetching attendance records for the specified date' });
    }
};


const getAllUsersAttendanceForToday = async (req, res) => {
    try {
        // Get today's date in YYYY-MM-DD format
        const today = new Date();
        const startOfDay = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate()));
        const endOfDay = new Date(startOfDay);
        endOfDay.setUTCDate(endOfDay.getUTCDate() + 1); // Adding 1 day to get the end of the day

        // Fetch all users and their attendance for today
        const users = await User.findAll({
            include: [
                {
                    model: Attendance,
                    as: 'attendances',  // Use the alias defined in the association
                    where: {
                        date: {
                            [Sequelize.Op.gte]: startOfDay,
                            [Sequelize.Op.lt]: endOfDay,
                        },
                    },
                    required: false, // Include all users, even those without attendance records
                    attributes: ['status'], // Only fetch the attendance status
                },
                {
                    model: User_role, // Fetch the role of the user
                    as: 'role',
                    attributes: ['name'],
                },
            ],
        });

        // Process the results to include 'Absent' if no attendance is found for a user
        const result = users.map(user => {
            const attendanceStatus = user.attendances.length > 0 ? user.attendances[0].status : 'absent'; // Default to 'absent' if no attendance record
            return {
                id: user.id,
                name: user.name,
                role: user.role.name,
                attendance: attendanceStatus,
            };
        });

        if (result.length === 0) {
            return res.status(404).json({
                message: 'No attendance records found for today.',
            });
        }

        return res.status(200).json(result);
    } catch (err) {
        console.error(err);
        return res.status(500).json({ error: 'Error fetching attendance records for all users' });
    }
};


// Controller to upload and save appointment letter path to the User model
const uploadAppointmentLetter = async (req, res) => {
    const userId = req.params.id;

    if (!userId) {
        return res.status(400).json({ error: 'User ID is required in the URL.' });
    }

    if (!req.file) {
        return res.status(400).json({ error: 'No PDF file uploaded.' });
    }

    try {
        const user = await User.findByPk(userId);

        if (!user) {
            return res.status(404).json({ error: 'User not found.' });
        }

        // Save the relative path to the appointment letter
        const relativePath = `/uploads/appointment_letters/${req.file.filename}`;
        user.appointment_letter_path = relativePath;
        await user.save();

        return res.status(200).json({
            message: 'Appointment letter uploaded successfully.',
            appointment_letter_path: relativePath,
        });
    } catch (err) {
        console.error(err);
        return res.status(500).json({ error: 'Failed to upload appointment letter.' });
    }
};


// Controller to upload and save Leave letter path to the User model
const uploadLeaveLetter = async (req, res) => {
    const userId = req.params.id;

    if (!userId) {
        return res.status(400).json({ error: 'User ID is required in the URL.' });
    }

    if (!req.file) {
        return res.status(400).json({ error: 'No PDF file uploaded.' });
    }

    try {
        const user = await User.findByPk(userId);

        if (!user) {
            return res.status(404).json({ error: 'User not found.' });
        }

        // Save the relative path to the appointment letter
        const relativePath = `/uploads/leave_letters/${req.file.filename}`;
        user.leave_letter_path = relativePath;
        await user.save();

        return res.status(200).json({
            message: 'Leave letter uploaded successfully.',
            leave_letter_path: relativePath,
        });
    } catch (err) {
        console.error(err);
        return res.status(500).json({ error: 'Failed to upload leave letter.' });
    }
};




module.exports = {
    markAttendance,
    getEmployeeAttendance,
    getAttendanceByDate, // Export the new function
    getAllUsersAttendanceForToday,
    uploadAppointmentLetter,
    uploadLeaveLetter,
    downloadAttendanceInRange
};
