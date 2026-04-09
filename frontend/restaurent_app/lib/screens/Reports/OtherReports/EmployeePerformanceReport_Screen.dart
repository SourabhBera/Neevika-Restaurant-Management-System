import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform, File, Directory;
import 'download_helper_io.dart'
    if (dart.library.html) 'download_helper_web.dart' as download_helper;

class EmployeePerformanceReportScreen extends StatefulWidget {
  const EmployeePerformanceReportScreen({super.key});

  @override
  _EmployeePerformanceReportScreenState createState() =>
      _EmployeePerformanceReportScreenState();
}

class _EmployeePerformanceReportScreenState
    extends State<EmployeePerformanceReportScreen> {
  List<Map<String, dynamic>> reportData = [];
  DateTime startDate = DateTime.now();
  DateTime endDate = DateTime.now();
  bool isLoading = false;

  // Filters
  String selectedFilter = "All";
  final TextEditingController categoryController = TextEditingController();
  final TextEditingController itemController = TextEditingController();

  @override
  void initState() {
    super.initState();
    fetchReportData();
  }

  @override
  void dispose() {
    categoryController.dispose();
    itemController.dispose();
    super.dispose();
  }

  String formatDate(DateTime date, {bool endOfDay = false}) {
    if (endOfDay) {
      date = DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
    } else {
      date = DateTime(date.year, date.month, date.day, 0, 0, 0, 0);
    }
    return date.toIso8601String();
  }

  Future<void> selectDate(BuildContext context, bool isStartDate) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStartDate ? startDate : endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isStartDate) {
          startDate = picked;
        } else {
          endDate = picked;
        }
      });
      await fetchReportData();
    }
  }

  Future<void> fetchReportData() async {
    setState(() => isLoading = true);

    final url = Uri.parse(
      '${dotenv.env['API_URL']}/other-reports/employee-performance-report'
      '?startDate=${formatDate(startDate)}'
      '&endDate=${formatDate(endDate, endOfDay: true)}'
      '&filter=$selectedFilter'
      '&category=${Uri.encodeComponent(categoryController.text)}'
      '&item=${Uri.encodeComponent(itemController.text)}',
    );

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);

        if (decoded['data'] != null && decoded['data'] is List) {
          setState(() {
            reportData = List<Map<String, dynamic>>.from(decoded['data']);
            isLoading = false;
          });
        } else {
          setState(() {
            reportData = [];
            isLoading = false;
          });
        }
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      print('Fetch error: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> downloadReport(String format) async {
  final apiBase = dotenv.env['API_URL'] ?? '';

  final url = Uri.parse(
    '$apiBase/other-reports/employee-performance-report/download'
    '?startDate=${formatDate(startDate)}'
    '&endDate=${formatDate(endDate, endOfDay: true)}'
    '&exportType=$format'
    '&filter=$selectedFilter'
    '&category=${Uri.encodeComponent(categoryController.text)}'
    '&item=${Uri.encodeComponent(itemController.text)}',
  );

  try {
    final response = await http.get(url);
    if (response.statusCode != 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: ${response.statusCode}')),
      );
      return;
    }

    final bytes = response.bodyBytes;

    // -------- Filename (same pattern as Sales report) --------
    final startStr = DateFormat('dd-MM-yy').format(startDate);
    final endStr = DateFormat('dd-MM-yy').format(endDate);
    final ext = format == 'xlsx' ? 'xlsx' : (format == 'csv' ? 'csv' : 'pdf');
    final filename = 'Employee-Performance_${startStr}_$endStr.$ext';

    final mime = (ext == 'pdf')
        ? 'application/pdf'
        : (ext == 'xlsx')
            ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
            : 'text/csv';

    // Mobile / Desktop path
    bool canWrite = true;

    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final sdkInt = androidInfo.version.sdkInt ?? 0;

      if (sdkInt >= 33) {
        // Android 13+: Request MANAGE_EXTERNAL_STORAGE
        final status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          final result = await Permission.manageExternalStorage.request();
          canWrite = result.isGranted;
        }
      } else {
        // Android 12 and below: Use storage permission
        final status = await Permission.storage.status;
        if (!status.isGranted) {
          final result = await Permission.storage.request();
          canWrite = result.isGranted;
        }
      }
    }

    if (!canWrite) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Storage permission not granted')),
      );
      return;
    }

    // -------- Downloads directory logic --------
    Directory? downloadsDir;
    try {
      if (Platform.isAndroid) {
        // Public Downloads folder visible in file manager
        downloadsDir = Directory('/storage/emulated/0/Download');
        if (!await downloadsDir.exists()) {
          await downloadsDir.create(recursive: true);
        }
      } else {
        downloadsDir = await getDownloadsDirectory();
      }
    } catch (_) {
      downloadsDir = null;
    }
    downloadsDir ??= await getApplicationDocumentsDirectory();

    if (downloadsDir == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to access storage directory')),
      );
      return;
    }

    final filePath =
        '${downloadsDir.path}${Platform.pathSeparator}$filename';

    final file = File(filePath);
    await file.writeAsBytes(bytes);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Downloaded: $filename'),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => OpenFile.open(filePath),
          ),
        ),
      );
    }
  } catch (e) {
    debugPrint("Download error: $e");
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}


  // Group report data by employee for summary cards
  Map<String, Map<String, dynamic>> _getEmployeeSummary() {
    final Map<String, Map<String, dynamic>> summary = {};
    for (final row in reportData) {
      final name = row['employeeName'] ?? 'Unknown';
      if (!summary.containsKey(name)) {
        summary[name] = {
          'employeeName': name,
          'totalOrders': 0,
          'totalQuantity': 0,
          'totalAmount': 0.0,
          'commissionTotal': 0.0,
        };
      }
      summary[name]!['totalOrders'] =
          (summary[name]!['totalOrders'] as int) +
              (int.tryParse(row['totalOrders'].toString()) ?? 0);
      summary[name]!['totalQuantity'] =
          (summary[name]!['totalQuantity'] as int) +
              (int.tryParse(row['totalQuantity'].toString()) ?? 0);
      summary[name]!['totalAmount'] =
          (summary[name]!['totalAmount'] as double) +
              (double.tryParse(row['totalAmount'].toString()) ?? 0.0);
      summary[name]!['commissionTotal'] =
          (summary[name]!['commissionTotal'] as double) +
              (double.tryParse(row['commissionTotal'].toString()) ?? 0.0);
    }
    return summary;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F5F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F5F2),
        elevation: 0,
        title: Text(
          'Employee Performance Report',
          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Date pickers ──────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => selectDate(context, true),
                      icon: const Icon(Icons.calendar_today_outlined,
                          size: 16, color: Colors.black54),
                      label: Text(
                        DateFormat('d MMM yyyy').format(startDate),
                        style: GoogleFonts.poppins(fontSize: 13),
                      ),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.grey.shade200,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        alignment: Alignment.centerLeft,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => selectDate(context, false),
                      icon: const Icon(Icons.calendar_today_outlined,
                          size: 16, color: Colors.black54),
                      label: Text(
                        DateFormat('d MMM yyyy').format(endDate),
                        style: GoogleFonts.poppins(fontSize: 13),
                      ),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.grey.shade200,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        alignment: Alignment.centerLeft,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── Filter dropdown ───────────────────────────────────
              DropdownButtonFormField<String>(
                value: selectedFilter,
                items: ["All", "Success", "Cancelled", "Complimentary", "Sales Return"]
                    .map((option) => DropdownMenuItem(
                          value: option,
                          child: Text(option,
                              style: GoogleFonts.poppins(fontSize: 13)),
                        ))
                    .toList(),
                onChanged: (value) {
                  setState(() => selectedFilter = value!);
                  fetchReportData();
                },
                decoration: InputDecoration(
                  labelText: "Filter",
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              const SizedBox(height: 12),

              // ── Category + Item inputs ────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: categoryController,
                      decoration: InputDecoration(
                        labelText: "Category",
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                      onSubmitted: (_) => fetchReportData(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: itemController,
                      decoration: InputDecoration(
                        labelText: "Item",
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                      onSubmitted: (_) => fetchReportData(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── Search button ─────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: fetchReportData,
                  icon: const Icon(Icons.search, size: 18),
                  label: Text('Search', style: GoogleFonts.poppins()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5E35B1),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Export buttons ────────────────────────────────────
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () => downloadReport('pdf'),
                    icon: const Icon(Icons.picture_as_pdf, size: 16),
                    label: Text('PDF', style: GoogleFonts.poppins(fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => downloadReport('xlsx'),
                    icon: const Icon(Icons.table_chart, size: 16),
                    label: Text('Excel', style: GoogleFonts.poppins(fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Summary cards ─────────────────────────────────────
              if (!isLoading && reportData.isNotEmpty) ...[
                Text('Employee Summary',
                    style: GoogleFonts.poppins(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ..._getEmployeeSummary().values.map((emp) => _buildEmployeeCard(emp)),
                const SizedBox(height: 16),
                Text('Item Breakdown',
                    style: GoogleFonts.poppins(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
              ],

              // ── Data table ────────────────────────────────────────
              isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : reportData.isEmpty
                      ? Center(
                          child: Column(
                            children: [
                              const SizedBox(height: 32),
                              Icon(Icons.bar_chart_outlined,
                                  size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 8),
                              Text('No data found.',
                                  style: GoogleFonts.poppins(
                                      color: Colors.grey.shade500)),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingRowColor: MaterialStateProperty.all(
                                Colors.deepPurple.shade100),
                            dataRowMinHeight: 36,
                            dataRowMaxHeight: 48,
                            columnSpacing: 14,
                            columns: [
                              _col('Employee'),
                              _col('Type'),
                              _col('Category'),
                              _col('Item'),
                              _col('Orders'),
                              _col('Qty'),
                              _col('Total (₹)'),
                              _col('Avg (₹)'),
                              _col('Incentive (₹)'),
                            ],
                            rows: reportData.map((row) {
                              final isFood =
                                  (row['type'] ?? '').toString().toLowerCase() ==
                                      'food';
                              return DataRow(
                                color: MaterialStateProperty.resolveWith((states) {
                                  return isFood
                                      ? Colors.orange.shade50
                                      : Colors.blue.shade50;
                                }),
                                cells: [
                                  _cell(row['employeeName'] ?? ''),
                                  DataCell(
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isFood
                                            ? Colors.orange.shade100
                                            : Colors.blue.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        isFood ? 'Food' : 'Drink',
                                        style: GoogleFonts.poppins(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w600,
                                          color: isFood
                                              ? Colors.orange.shade800
                                              : Colors.blue.shade800,
                                        ),
                                      ),
                                    ),
                                  ),
                                  _cell(row['categoryName'] ?? ''),
                                  _cell(row['itemName'] ?? ''),
                                  _cell(row['totalOrders']?.toString() ?? '0'),
                                  _cell(row['totalQuantity']?.toString() ?? '0'),
                                  _cell(
                                      '₹${double.tryParse(row['totalAmount'].toString())?.toStringAsFixed(2) ?? '0.00'}'),
                                  _cell(
                                      '₹${double.tryParse(row['avgOrderAmount'].toString())?.toStringAsFixed(2) ?? '0.00'}'),
                                  DataCell(
                                    Text(
                                      '₹${double.tryParse(row['commissionTotal'].toString())?.toStringAsFixed(2) ?? '0.00'}',
                                      style: GoogleFonts.poppins(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.green.shade700,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  DataColumn _col(String label) => DataColumn(
        label: Text(label,
            style: GoogleFonts.poppins(
                fontSize: 11, fontWeight: FontWeight.w600)),
      );

  DataCell _cell(String text) => DataCell(
        Text(text, style: GoogleFonts.poppins(fontSize: 10)),
      );

  Widget _buildEmployeeCard(Map<String, dynamic> emp) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.deepPurple.shade100,
            radius: 20,
            child: Text(
              (emp['employeeName'] as String).isNotEmpty
                  ? (emp['employeeName'] as String)[0].toUpperCase()
                  : '?',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  color: Colors.deepPurple.shade700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(emp['employeeName'],
                    style: GoogleFonts.poppins(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                Text(
                    '${emp['totalOrders']} orders • ${emp['totalQuantity']} items',
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹${(emp['totalAmount'] as double).toStringAsFixed(2)}',
                style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87),
              ),
              Row(
                children: [
                  const Icon(Icons.star, size: 12, color: Colors.amber),
                  const SizedBox(width: 2),
                  Text(
                    '₹${(emp['commissionTotal'] as double).toStringAsFixed(2)}',
                    style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.green.shade700),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}