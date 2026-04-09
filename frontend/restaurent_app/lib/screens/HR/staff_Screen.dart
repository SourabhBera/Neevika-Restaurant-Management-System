import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

class AttendanceTableScreen extends StatefulWidget {
  const AttendanceTableScreen({super.key});

  @override
  State<AttendanceTableScreen> createState() => _AttendanceTableScreenState();
}

class _AttendanceTableScreenState extends State<AttendanceTableScreen> {
  List<AttendanceTodayRecord> _records = [];
  List<AttendanceTodayRecord> _filtered = [];
  List<String> _roles = ['All'];
  String _selectedRole = 'All';
  String? _noDataMessage;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchAttendanceToday();
  }

  Future<void> _fetchAttendanceToday() async {
    final url = Uri.parse('${dotenv.env['API_URL']}/hr/attendance-today');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> decoded = json.decode(response.body);
        final data = decoded.map((e) => AttendanceTodayRecord.fromJson(e)).toList();

        final roles = data.map((e) => e.role).toSet().toList()..sort();

        setState(() {
          _records = data;
          _filtered = data;
          _roles = ['All', ...roles];
          _noDataMessage = null;
        });
      } else {
        setState(() {
          _records = [];
          _filtered = [];
          _noDataMessage = 'Failed to load data.';
        });
      }
    } catch (e) {
      setState(() {
        _records = [];
        _filtered = [];
        _noDataMessage = 'Error fetching attendance data.';
      });
    }
  }

  void _filter(String query) {
    final filtered = _records.where((record) {
      final matchesName = record.name.toLowerCase().contains(query.toLowerCase());
      final matchesRole = _selectedRole == 'All' || record.role == _selectedRole;
      return matchesName && matchesRole;
    }).toList();

    setState(() {
      _filtered = filtered;
    });
  }

  void _setRole(String? newRole) {
    if (newRole == null) return;
    setState(() {
      _selectedRole = newRole;
    });
    _filter(_searchController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        title: Text("Today's Attendance",
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.black)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchAttendanceToday,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Role Dropdown
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _selectedRole,
                  underline: const SizedBox(),
                  icon: const Icon(Icons.arrow_drop_down),
                  onChanged: _setRole,
                  items: _roles.map((role) {
                    return DropdownMenuItem(
                      value: role,
                      child: Text(role, style: GoogleFonts.poppins(fontSize: 14)),
                    );
                  }).toList(),
                ),
              ),

              // Search Bar
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
                  onChanged: _filter,
                  decoration: const InputDecoration(
                    hintText: "Search by employee name...",
                    border: InputBorder.none,
                    icon: Icon(Icons.search),
                  ),
                ),
              ),

              // Table
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
                child: _filtered.isNotEmpty
                    ? DataTable(
                        columnSpacing: 20,
                        headingRowColor:
                            WidgetStateProperty.all(Colors.grey.shade200),
                        columns: const [
                          DataColumn(label: Text('Employee')),
                          DataColumn(label: Text('Role')),
                          DataColumn(label: Text('Status')),
                        ],
                        rows: _filtered.map(
                          (record) => DataRow(
                            cells: [
                              DataCell(Text(record.name)),
                              DataCell(Text(record.role)),
                              DataCell(
                                Text(
                                  record.attendance.capitalize(),
                                  style: TextStyle(
                                    color: record.attendance.toLowerCase() == 'present'
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ).toList(),
                      )
                    : Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Center(
                          child: Text(
                            _noDataMessage ?? 'No data available.',
                            style: GoogleFonts.poppins(
                                fontStyle: FontStyle.italic,
                                color: Colors.grey[600]),
                          ),
                        ),
                      ),
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}

class AttendanceTodayRecord {
  final String name;
  final String role;
  final String attendance;

  AttendanceTodayRecord({
    required this.name,
    required this.role,
    required this.attendance,
  });

  factory AttendanceTodayRecord.fromJson(Map<String, dynamic> json) {
    return AttendanceTodayRecord(
      name: json['name'] ?? 'Unknown',
      role: json['role'] ?? 'Unknown',
      attendance: json['attendance'] ?? 'absent',
    );
  }
}

extension StringCasing on String {
  String capitalize() =>
      isNotEmpty ? '${this[0].toUpperCase()}${substring(1)}' : '';
}
