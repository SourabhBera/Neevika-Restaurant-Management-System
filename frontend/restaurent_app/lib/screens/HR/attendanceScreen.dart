import 'dart:io';
import 'package:Neevika/screens/HR/markAttendance_Screen.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_file/open_file.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  _AttendanceScreenState createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  List<AttendanceRecord> _attendanceRecords = [];
  DateTime selectedDate = DateTime.now();
  String? noDataMessage;
  final TextEditingController _searchController = TextEditingController();
  List<AttendanceRecord> _filteredRecords = [];
  bool _showDownloadOptions = false;
  // New: Start and End date for download
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _fetchAttendance();
  }

  Future<void> _fetchAttendance() async {
    final formattedDate =
        "${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}";

    final response = await http
        .get(Uri.parse('${dotenv.env['API_URL']}/hr/attendance/date/$formattedDate'));

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);

      if (decoded is List) {
        setState(() {
          _attendanceRecords =
              decoded.map((record) => AttendanceRecord.fromJson(record)).toList();
          _filteredRecords = _attendanceRecords;
          noDataMessage = null;
        });
      } else if (decoded is Map &&
          decoded['message'] == "No attendance records found for this date.") {
        setState(() {
          _attendanceRecords = [];
          _filteredRecords = [];
          noDataMessage = decoded['message'];
        });
      }
    } else {
      setState(() {
        _attendanceRecords = [];
        _filteredRecords = [];
        noDataMessage = "No attendance records found for this date.";
      });
      print('Failed to load attendance for $formattedDate');
    }
  }

  void _filterRecords(String query) {
    final filtered = _attendanceRecords.where((record) {
      return record.employeeName.toLowerCase().contains(query.toLowerCase());
    }).toList();

    setState(() {
      _filteredRecords = filtered;
    });
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );

    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
      await _fetchAttendance();
    }
  }

  // New: Pick start date
  Future<void> _pickStartDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: _endDate ?? DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        _startDate = picked;
        // If endDate is before startDate, reset endDate
        if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = null;
        }
      });
    }
  }

  // New: Pick end date
  Future<void> _pickEndDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? (_startDate ?? DateTime.now()),
      firstDate: _startDate ?? DateTime(2023),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        _endDate = picked;
      });
    }
  }

  Future<void> _downloadAttendance() async {
    if (_startDate == null || _endDate == null) return;

    final startDate =
        "${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}";
    final endDate =
        "${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}";

    final url = Uri.parse(
        '${dotenv.env['API_URL']}/hr/attendance/download?startDate=$startDate&endDate=$endDate');

    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      bool hasPermission = true;
      if (sdkInt <= 32) {
        final status = await Permission.storage.status;
        if (!status.isGranted) {
          final result = await Permission.storage.request();
          hasPermission = result.isGranted;
        }
      }

      if (!hasPermission) {
        throw Exception('Storage permission not granted');
      }

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;

        final dir = await getExternalStorageDirectory();
        final filePath = '${dir!.path}/attendance_${startDate}_to_${endDate}.xlsx';
        final file = File(filePath);
        await file.writeAsBytes(bytes);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Downloaded to: $filePath")),
        );

        await OpenFile.open(filePath);
      } else {
        throw Exception('Download failed: ${response.statusCode}');
      }
    } catch (e) {
      print("Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Download failed: $e")),
      );
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Select date';
    return "${date.day}/${date.month}/${date.year}";
  }

  bool get _isDownloadEnabled =>
      _startDate != null && _endDate != null && !_endDate!.isBefore(_startDate!);



@override
Widget build(BuildContext context) {
  final bool _isDownloadEnabled = _startDate != null && _endDate != null;
  return Scaffold(
    backgroundColor: const Color(0xFFF9F9F9),
    appBar: AppBar(
      title: Text(
        "Attendance Records",
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.w600,
          color: Colors.black,
          fontSize: 16
        ),
      ),
      centerTitle: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      iconTheme: const IconThemeData(color: Colors.black),
    ),
    body: RefreshIndicator(
      onRefresh: _fetchAttendance,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12.withOpacity(0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Date: ${selectedDate.day}/${selectedDate.month}/${selectedDate.year}",
                      style: GoogleFonts.poppins(
                          fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    const Icon(Icons.calendar_today_outlined, size: 16),
                  ],
                ),
              ),
            ),

            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12.withOpacity(0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _filterRecords,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.black,
                ),
                decoration: InputDecoration(
                  hintText: "Search by Employee Name...",
                  hintStyle: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                  border: InputBorder.none,
                  icon: const Icon(Icons.search),
                ),
              ),
            ),

            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12.withOpacity(0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: DataTable(
                columnSpacing: 20,
                headingRowColor:
                    MaterialStateProperty.all(Colors.grey.shade200),
                columns: [
                  DataColumn(label: Text('Employee', style: GoogleFonts.poppins(fontSize: 12))),
                  DataColumn(label: Text('Role', style: GoogleFonts.poppins(fontSize: 12))),
                  DataColumn(label: Text('Status', style: GoogleFonts.poppins(fontSize: 12))),
                  DataColumn(label: Text('Time', style: GoogleFonts.poppins(fontSize: 12))),
                ],
                rows: _filteredRecords.map(
                  (record) => DataRow(cells: [
                    DataCell(Text(record.employeeName, style: GoogleFonts.poppins(fontSize: 10.7))),
                    DataCell(Text(record.roleName, style: GoogleFonts.poppins(fontSize: 10.7))),
                    DataCell(
                      Text(
                        record.status.capitalize(),
                        style: GoogleFonts.poppins(
                          color: record.status.toLowerCase() == 'present' ? Colors.green : Colors.red,
                          fontSize: 10.7
                        ),
                      ),
                    ),
                    DataCell(Text(record.timeFormatted, style: GoogleFonts.poppins(fontSize: 10.7))),
                  ]),
                ).toList(),
              ),
            ),

            if (_attendanceRecords.isEmpty && noDataMessage != null) ...[
              const SizedBox(height: 12),
              Center(
                child: Text(
                  noDataMessage!,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const MarkAttendanceScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF8F5F2),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(
                      color: Color.fromARGB(255, 204, 203, 203),
                      width: 1.6,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.how_to_reg_rounded, color: Colors.black),
                    const SizedBox(width: 8),
                    Text(
                      'Mark Attendance',
                      style: GoogleFonts.poppins(
                        color: Colors.black,
                        fontSize: 11,
                      ),
                    ),
                      const SizedBox(width: 15),
                      const Icon(Icons.arrow_right_alt_rounded, color: Colors.black),
                  ],
                ),
              ),
            ),


            const SizedBox(height: 20),

            // Download Attendance Excel toggle button styled as requested
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    _showDownloadOptions = !_showDownloadOptions;
                    if (!_showDownloadOptions) {
                      _startDate = null;
                      _endDate = null;
                    }
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF8F5F2),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(
                      color: Color.fromARGB(255, 204, 203, 203),
                      width: 1.6,
                    ),
                  ),
                  minimumSize: const Size.fromHeight(50),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _showDownloadOptions ? Icons.close_rounded : Icons.download_rounded,
                      color: Colors.black,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _showDownloadOptions ? 'Cancel Download' : 'Download Attendance Excel',
                      style: GoogleFonts.poppins(
                        color: Colors.black,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (_showDownloadOptions) ...[
              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _startDate ?? DateTime.now(),
                          firstDate: DateTime(2023),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setState(() {
                            _startDate = picked;
                            if (_endDate != null && _endDate!.isBefore(_startDate!)) {
                              _endDate = null;
                            }
                          });
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF8F5F2),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: const BorderSide(
                            color: Color.fromARGB(255, 204, 203, 203),
                            width: 1.6,
                          ),
                        ),
                        minimumSize: const Size.fromHeight(50),
                      ),
                      child: Text(
                        _startDate == null
                            ? "Select Start Date"
                            : "Start: ${_startDate!.day}/${_startDate!.month}/${_startDate!.year}",
                        style: GoogleFonts.poppins(
                          color: Colors.black,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _startDate == null
                          ? null
                          : () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _endDate ?? _startDate!,
                                firstDate: _startDate!,
                                lastDate: DateTime.now(),
                              );
                              if (picked != null) {
                                setState(() {
                                  _endDate = picked;
                                });
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _startDate == null
                            ? Colors.grey.shade300
                            : const Color(0xFFF8F5F2),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: _startDate == null
                                ? Colors.grey.shade400
                                : const Color.fromARGB(255, 204, 203, 203),
                            width: 1.6,
                          ),
                        ),
                        minimumSize: const Size.fromHeight(50),
                      ),
                      child: Text(
                        _endDate == null
                            ? "Select End Date"
                            : "End: ${_endDate!.day}/${_endDate!.month}/${_endDate!.year}",
                        style: GoogleFonts.poppins(
                          color: Colors.black,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isDownloadEnabled ? _downloadAttendance : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isDownloadEnabled
                        ? const Color(0xFFF8F5F2)
                        : Colors.grey.shade300,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: _isDownloadEnabled
                            ? const Color.fromARGB(255, 204, 203, 203)
                            : Colors.grey.shade400,
                        width: 1.6,
                      ),
                    ),
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.download_rounded, color: Colors.black),
                      const SizedBox(width: 8),
                      Text(
                        'Download',
                        style: GoogleFonts.poppins(
                          color: Colors.black,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
}

class AttendanceRecord {
  final String employeeName;
  final String roleName;
  final String status;
  final String time;

  AttendanceRecord({
    required this.employeeName,
    required this.roleName,
    required this.status,
    required this.time,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    return AttendanceRecord(
      employeeName: json['employee']['name'] ?? 'Unknown',
      roleName: json['employee']['role']['name'] ?? 'Unknown',
      status: json['status'] ?? 'Absent',
      time: json['createdAt'] ?? '',
    );
  }

  String get timeFormatted {
    try {
      final parsed = DateTime.parse(time);
      return "${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}";
    } catch (_) {
      return "--:--";
    }
  }
}

extension StringCasingExtension on String {
  String capitalize() =>
      isNotEmpty ? '${this[0].toUpperCase()}${substring(1)}' : '';
}
