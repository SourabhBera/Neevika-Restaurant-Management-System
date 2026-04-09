import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_file/open_file.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform, Directory, File;

import 'download_helper_io.dart'
    if (dart.library.html) 'download_helper_web.dart' as download_helper;

class InvoiceReportScreen extends StatefulWidget {
  const InvoiceReportScreen({super.key});

  @override
  State<InvoiceReportScreen> createState() => _InvoiceReportScreenState();
}

class _InvoiceReportScreenState extends State<InvoiceReportScreen> {
  DateTime startDate = DateTime.now();
  DateTime endDate = DateTime.now();
  bool isLoading = false;
  Map<String, dynamic>? report;

  String formatDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  @override
  void initState() {
    super.initState();
    fetchInvoiceReport();
  }

  Future<void> selectDate(BuildContext context, bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? startDate : endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isStart) startDate = picked;
        else endDate = picked;
      });
      await fetchInvoiceReport();
    }
  }

  Future<void> fetchInvoiceReport() async {
    setState(() => isLoading = true);
    final url = Uri.parse('${dotenv.env['API_URL']}/other-reports/invoice-report?startDate=${formatDate(startDate)}&endDate=${formatDate(endDate)}');

    final response = await http.get(url);
    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      setState(() {
        report = decoded['data'];
        isLoading = false;
      });
    } else {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to fetch invoice report')));
    }
  }


Future<void> downloadReport(String format) async {
  final apiBase = dotenv.env['API_URL'] ?? '';
  final exportType = (format == 'xlsx' || format == 'excel') ? 'excel' : format;

  final url = Uri.parse(
    '$apiBase/other-reports/invoice-report/download'
    '?startDate=${formatDate(startDate)}'
    '&endDate=${formatDate(endDate)}'
    '&exportType=$exportType',
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

    // ---------- File Naming ----------
    final startStr = DateFormat('dd-MM-yy').format(startDate);
    final endStr = DateFormat('dd-MM-yy').format(endDate);
    final ext = exportType == 'excel' ? 'xlsx' : 'pdf';

    final filename = 'Invoice-Report_${startStr}_$endStr.$ext';

    final mime = (ext == 'pdf')
        ? 'application/pdf'
        : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

    // Android permission & storage handling
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

    // Determine Downloads Directory
    Directory? downloadsDir;
    try {
      if (!kIsWeb && Platform.isAndroid) {
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

    // Build target path and avoid conflicts
    String filePath =
        '${downloadsDir.path}${Platform.pathSeparator}$filename';

    File file = File(filePath);

    if (await file.exists()) {
      int counter = 1;
      final baseName = filename.replaceFirst(RegExp(r'\.[^.]+$'), '');
      final fileExtMatch =
          RegExp(r'(\.[^.]+)$').firstMatch(filename);
      final fileExt =
          fileExtMatch != null ? fileExtMatch.group(1) ?? '' : '';

      do {
        final newName = '${baseName}($counter)$fileExt';
        filePath =
            '${downloadsDir.path}${Platform.pathSeparator}$newName';
        file = File(filePath);
        counter++;
      } while (await file.exists());
    }

    // Save file directly
    await file.writeAsBytes(bytes);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Downloaded to: $filePath')),
    );

    try {
      await OpenFile.open(filePath);
    } catch (e) {
      debugPrint('OpenFile failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('File saved. Open it from your Downloads folder.')),
      );
    }
  } catch (e, st) {
    debugPrint('Download error: $e\n$st');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Download failed: $e')),
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
        title: Text('Invoice Report', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Date pickers
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

            // Download buttons
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => downloadReport('pdf'),
                  icon: const Icon(Icons.picture_as_pdf, size: 16),
                  label: const Text('PDF'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade400,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => downloadReport('xlsx'),
                  icon: const Icon(Icons.table_chart, size: 16),
                  label: const Text('Excel'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade500,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Report table
            isLoading
                ? const Center(child: CircularProgressIndicator())
                : report == null
                    ? const Text('No data found.', style: TextStyle(color: Colors.grey))
                    : Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: DataTable(
                              columnSpacing: 20,
                              headingRowColor: MaterialStateProperty.all(Colors.grey.shade200),
                              dataRowColor: MaterialStateProperty.all(Colors.white),
                              headingTextStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                              dataTextStyle: GoogleFonts.poppins(fontSize: 13),
                              columns: const [
                                DataColumn(label: Text('Bill Starting')),
                                DataColumn(label: Text('Bill Ending')),
                                DataColumn(label: Text('Total Bills')),
                                DataColumn(label: Text('Total Bill Amount')),
                                DataColumn(label: Text('Total Discount')),
                                DataColumn(label: Text('Total Service Charge')),
                              ],
                              rows: [
                                DataRow(cells: [
                                  DataCell(Text(report!['idStart'].toString())),
                                  DataCell(Text(report!['idEnd'].toString())),
                                  DataCell(Text(report!['totalBills'].toString())),
                                  DataCell(Text('₹${(report!['totalAmount'] ?? 0).toStringAsFixed(2)}')),
                                  DataCell(Text('₹${(report!['totalDiscountAmount'] ?? 0).toStringAsFixed(2)}')),
                                  DataCell(Text('₹${(report!['totalServiceChargeAmount'] ?? 0).toStringAsFixed(2)}')),
                                ])
                              ],
                            ),
                          ),
                        ),
                      )
          ],
        ),
      ),
    );
  }
}
