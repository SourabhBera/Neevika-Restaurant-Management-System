import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class DownloadMasterReportScreen extends StatefulWidget {
  const DownloadMasterReportScreen({super.key});

  @override
  State<DownloadMasterReportScreen> createState() => _DownloadMasterReportScreenState();
}

class _DownloadMasterReportScreenState extends State<DownloadMasterReportScreen> {
  DateTime startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime endDate = DateTime.now();
  bool isDownloading = false;

  String formatDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  Future<void> selectDate(BuildContext context, bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? startDate : endDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isStart) startDate = picked;
        else endDate = picked;
      });
    }
  }

Future<void> downloadMasterReport(String format) async {
  setState(() => isDownloading = true); // Start loading

  final url = Uri.parse(
    '${dotenv.env['API_URL']}/other-reports/master-report/download'
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
      // Get main Downloads folder (Android public Downloads)
      Directory? directory;
      try {
        if (Platform.isAndroid) {
          directory = Directory('/storage/emulated/0/Download');
          if (!await directory.exists()) {
            await directory.create(recursive: true);
          }
        } else {
          directory = await getDownloadsDirectory();
        }
      } catch (_) {
        directory = null;
      }
      directory ??= await getApplicationDocumentsDirectory();

      if (directory == null) {
        throw Exception('Downloads directory not available');
      }

      final fileName = 'Master_Report_${formatDate(startDate)}_to_${formatDate(endDate)}.$format';
      final filePath = '${directory.path}${Platform.pathSeparator}$fileName';

      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Downloaded to: $filePath")),
      );

      OpenFile.open(filePath);
    } else {
      throw Exception('Download failed. Status: ${response.statusCode}');
    }
  } catch (e) {
    print('Download error: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Download failed: $e')),
    );
  } finally {
    setState(() => isDownloading = false); // Stop loading
  }
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Master Report Export'),
        backgroundColor: const Color(0xFFF8F5F2),
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF8F5F2),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => selectDate(context, true),
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(DateFormat('d MMM yyyy').format(startDate),
                          style: GoogleFonts.poppins(fontSize: 13)),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.grey.shade200,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => selectDate(context, false),
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(DateFormat('d MMM yyyy').format(endDate),
                          style: GoogleFonts.poppins(fontSize: 13)),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.grey.shade200,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 30),
                ElevatedButton.icon(
                  icon: const Icon(Icons.download),
                  onPressed: isDownloading ? null : () => downloadMasterReport('xlsx'),
                  label: const Text('Download Master Report'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    textStyle: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
          if (isDownloading)
            Container(
              color: Colors.black.withOpacity(0.4),
              child: Center(
                child: LoadingAnimationWidget.staggeredDotsWave(
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
//xlsx