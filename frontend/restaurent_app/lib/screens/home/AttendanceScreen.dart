import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

class UserAttendanceScreen extends StatefulWidget {
  final String employeeId;

  const UserAttendanceScreen({super.key, required this.employeeId});

  @override
  State<UserAttendanceScreen> createState() => _UserAttendanceScreenState();
}

class _UserAttendanceScreenState extends State<UserAttendanceScreen> {
  late Future<List<AttendanceRecord>> _attendanceRecords;
  List<AttendanceRecord> _allRecords = [];
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  String _selectedMonth = DateFormat('MMMM yyyy').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    _attendanceRecords = fetchAttendance(widget.employeeId);
  }

  Future<List<AttendanceRecord>> fetchAttendance(String employeeId) async {
    final response = await http.get(
      Uri.parse('http://13.60.15.89:3000/api/hr/attendance/$employeeId'),
    );

    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(response.body);
      print(data);
      final records = data.map((e) => AttendanceRecord.fromJson(e)).toList();
      setState(() => _allRecords = records);
      return records;
    } else {
      throw Exception('No attendance data');
    }
  }

  List<AttendanceRecord> get filteredRecords {
  final selectedMonthDate = DateFormat('MMMM yyyy').parse(_selectedMonth);
  final today = DateTime.now();

  final start = DateTime(selectedMonthDate.year, selectedMonthDate.month, 1);
  final end = DateTime(
    selectedMonthDate.year,
    selectedMonthDate.month,
    selectedMonthDate.month == today.month && selectedMonthDate.year == today.year
        ? today.day
        : DateTime(selectedMonthDate.year, selectedMonthDate.month + 1, 0).day,
  );

  final presentDates = _allRecords.map((r) => DateTime.parse(r.date).toLocal()).toList();

  List<AttendanceRecord> filled = [];

  for (int i = 0; i < end.day; i++) {
    final currentDate = start.add(Duration(days: i));

    if (currentDate.isAfter(today)) break;

    final match = presentDates.firstWhere(
      (d) =>
          d.year == currentDate.year &&
          d.month == currentDate.month &&
          d.day == currentDate.day,
      orElse: () => DateTime(1900),
    );

    filled.add(
      AttendanceRecord(
        date: currentDate.toIso8601String(),
        status: match.year != 1900 ? 'present' : 'absent',
      ),
    );
  }

  return filled;
}


  AttendanceRecord? getRecordForDay(DateTime day) {
    for (var record in filteredRecords) {
      final recordDate = DateTime.parse(record.date).toLocal();
      if (recordDate.year == day.year &&
          recordDate.month == day.month &&
          recordDate.day == day.day) {
        return record;
      }
    }
    return null;
  }

  int get presentCount =>
    filteredRecords.where((r) => r.status == 'present').length;

  int get absentCount =>
      filteredRecords.where((r) => r.status == 'absent').length;

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: GoogleFonts.inter(fontSize: 12)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final monthList = List.generate(12, (index) {
      final date = DateTime(DateTime.now().year, index + 1);
      return DateFormat('MMMM yyyy').format(date);
    });
  
    final selectedRecord = getRecordForDay(_selectedDay);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        title: Text(
          'Your Attendance',
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: FutureBuilder<List<AttendanceRecord>>(
        future: _attendanceRecords,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No attendance records found.'));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButton<String>(
                  value: _selectedMonth,
                  icon: const Icon(Icons.keyboard_arrow_down),
                  isExpanded: true,
                  items: monthList.map((String month) {
                    return DropdownMenuItem<String>(
                      value: month,
                      child: Text(month),
                    );
                  }).toList(),
                  onChanged: (String? newMonth) {
                    if (newMonth != null) {
                      setState(() {
                        _selectedMonth = newMonth;
                        _focusedDay =
                            DateFormat('MMMM yyyy').parse(newMonth);
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                TableCalendar(
                  firstDay: DateTime.utc(2023, 1, 1),
                  lastDay: DateTime.utc(2030, 12, 31),
                  focusedDay: _focusedDay,
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  headerStyle: const HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                  ),
                  calendarStyle: CalendarStyle(
                    todayDecoration: BoxDecoration(
                      color: Colors.blueAccent,
                      shape: BoxShape.circle,
                    ),
                    selectedDecoration: BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                    ),
                  ),
                  calendarBuilders: CalendarBuilders(
                    defaultBuilder: (context, day, _) {
                      final record = getRecordForDay(day);
                      if (record == null) return null;

                      final isPresent = record.status == "present";
                      return Center(
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color:
                                isPresent ? Colors.green : Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${day.day}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _selectedDay = selectedDay;
                      _focusedDay = focusedDay;
                    });
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildLegendDot(Colors.green, 'Present'),
                    _buildLegendDot(Colors.red, 'Absent'),
                    _buildLegendDot(Colors.blueAccent, 'Today'),
                  ],
                ),
                const SizedBox(height: 20),
                Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  color: Colors.white,
                  elevation: 2,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Present: $presentCount",
                          style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.green),
                        ),
                        Text(
                          "Absent: $absentCount",
                          style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.red),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (selectedRecord != null)
                  Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    color: Colors.white,
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Selected Day Record",
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Date: ${DateFormat('dd MMM yyyy').format(_selectedDay)}",
                            style: GoogleFonts.inter(fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Status: ${selectedRecord.status}",
                            style: GoogleFonts.inter(
                                fontSize: 14,
                                color: selectedRecord.status == "present"
                                    ? Colors.green
                                    : Colors.red),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class AttendanceRecord {
  final String date;
  final String status;

  AttendanceRecord({required this.date, required this.status});

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    return AttendanceRecord(
      date: json['date'],
      status: json['status'],
    );
  }
}
