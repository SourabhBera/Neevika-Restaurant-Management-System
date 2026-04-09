import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';

class SectionWiseReportScreen extends StatefulWidget {
  const SectionWiseReportScreen({super.key});

  @override
  _SectionWiseReportScreenState createState() => _SectionWiseReportScreenState();
}

class _SectionWiseReportScreenState extends State<SectionWiseReportScreen> {
  List<Map<String, dynamic>> reportData = [];
  DateTime startDate = DateTime.now();
  DateTime endDate = DateTime.now();
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    fetchReportData();
  }

  String formatDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  Future<void> selectDate(BuildContext context, bool isStartDate) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStartDate ? startDate : endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isStartDate) startDate = picked;
        else endDate = picked;
      });
      await fetchReportData();
    }
  }

  Future<void> fetchReportData() async {
    setState(() => isLoading = true);
    final url = Uri.parse(
      '${dotenv.env['API_URL']}/other-reports/sub-order-wise-report/'
      '?startDate=${formatDate(startDate)}&endDate=${formatDate(endDate)}',
    );

    final response = await http.get(url);
    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      setState(() {
        reportData = List<Map<String, dynamic>>.from(decoded['data']);
        isLoading = false;
      });
    } else {
      setState(() => isLoading = false);
      throw Exception('Failed to load section-wise data');
    }
  }

Future<void> downloadReport(String format) async {
  final url = Uri.parse(
    '${dotenv.env['API_URL']}/other-reports/sub-order-wise-report/download'
    '?startDate=${formatDate(startDate)}&endDate=${formatDate(endDate)}&exportType=$format',
  );

  try {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    final sdkInt = androidInfo.version.sdkInt;

    bool hasPermission = true;

    if (sdkInt >= 33) {
      // Android 13+: Request MANAGE_EXTERNAL_STORAGE
      final status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) {
        final result = await Permission.manageExternalStorage.request();
        hasPermission = result.isGranted;
      }
    } else if (sdkInt <= 32) {
      // Android 12 and below: Use standard storage permission
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

      // Get main Downloads folder (Android public Downloads)
      Directory? dir;
      try {
        if (Platform.isAndroid) {
          dir = Directory('/storage/emulated/0/Download');
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
        } else {
          dir = await getDownloadsDirectory();
        }
      } catch (_) {
        dir = null;
      }
      dir ??= await getApplicationDocumentsDirectory();

      if (dir == null) {
        throw Exception('Downloads directory not available');
      }

      final fileName =
          'SectionWiseReport_${formatDate(startDate)}_to_${formatDate(endDate)}.$format';
      final filePath = '${dir.path}${Platform.pathSeparator}$fileName';

      final file = File(filePath);
      await file.writeAsBytes(bytes);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Downloaded to: $filePath")),
      );

      OpenFile.open(filePath);
    } else {
      throw Exception('Download failed. Status: ${response.statusCode}');
    }
  } catch (e) {
    print("Download error: $e");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Download failed: $e")),
    );
  }
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F5F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F5F2),
        elevation: 0,
        title: Text('Section Wise Report', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () => selectDate(context, true),
                  icon: const Icon(Icons.calendar_today_outlined, size: 16, color: Colors.black54),
                  label: Text(DateFormat('d MMM yyyy').format(startDate), style: GoogleFonts.poppins(fontSize: 13)),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.grey.shade200,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    alignment: Alignment.centerLeft,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => selectDate(context, false),
                  icon: const Icon(Icons.calendar_today_outlined, size: 16, color: Colors.black54),
                  label: Text(DateFormat('d MMM yyyy').format(endDate), style: GoogleFonts.poppins(fontSize: 13)),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.grey.shade200,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    alignment: Alignment.centerLeft,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => downloadReport('pdf'),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('PDF'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => downloadReport('xlsx'),
                  icon: const Icon(Icons.table_chart),
                  label: const Text('Excel'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            isLoading
                ? const Center(child: CircularProgressIndicator())
                : Expanded(
                    child: reportData.isEmpty
                        ? const Center(child: Text('No section data found.'))
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingRowColor: MaterialStateProperty.all(Colors.deepPurple.shade100),
                              columns: [
                                DataColumn(label: Text('Section', style: GoogleFonts.poppins(fontSize: 11))),
                                DataColumn(label: Text('Bill Count', style: GoogleFonts.poppins(fontSize: 11))),
                                DataColumn(label: Text('Total Amount', style: GoogleFonts.poppins(fontSize: 11))),
                                DataColumn(label: Text('Total Discount', style: GoogleFonts.poppins(fontSize: 11))),
                              ],
                              rows: reportData.map((row) {
                                return DataRow(cells: [
                                  DataCell(Text(row['sectionName'], style: GoogleFonts.poppins(fontSize: 10)),),
                                  DataCell(Text(row['billCount'].toString(), style: GoogleFonts.poppins(fontSize: 10))),
                                  DataCell(Text('₹${row['totalAmount'].toStringAsFixed(2)}', style: GoogleFonts.poppins(fontSize: 10))),
                                  DataCell(Text('₹${row['totalDiscount'].toStringAsFixed(2)}', style: GoogleFonts.poppins(fontSize: 10))),
                                ]);
                              }).toList(),
                            ),
                          ),
                  ),
          ],
        ),
      ),
    );
  }
}
