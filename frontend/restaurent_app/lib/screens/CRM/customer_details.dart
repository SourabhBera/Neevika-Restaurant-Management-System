import 'dart:io';
import 'package:Neevika/utils/web_downloader_stub.dart'
    if (dart.library.html) 'package:Neevika/utils/web_downloader_web.dart';
import 'dart:io' as io;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class CustomerDetailsPage extends StatefulWidget {
  const CustomerDetailsPage({super.key});

  @override
  State<CustomerDetailsPage> createState() => _CustomerDetailsPageState();
}

class _CustomerDetailsPageState extends State<CustomerDetailsPage> {
  List<dynamic> customers = [];
  bool isLoading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    fetchCustomerDetails();
  }

  Future<void> fetchCustomerDetails() async {
    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      final response = await http.get(Uri.parse('${dotenv.env['API_URL']}/crm/customers-details'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          customers = data;
          isLoading = false;
        });
      } else {
        setState(() {
          error = 'Failed to load customers. Status: ${response.statusCode}';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        error = 'Error fetching customers: $e';
        isLoading = false;
      });
    }
  }

  Future<void> downloadCustomerDetailsFile(BuildContext context) async {
  final url = Uri.parse('${dotenv.env['API_URL']}/crm/download');

  try {
    final response = await http.get(url);

    if (response.statusCode != 200) {
      throw Exception('Failed to download. Status: ${response.statusCode}');
    }

    final bytes = response.bodyBytes;

    if (kIsWeb) {
      triggerWebDownload(bytes, 'customer_details.xlsx');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Download started (web browser)")),
      );
      return;
    }else {
      // 📱 Mobile (Android/iOS) logic
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
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

      final dir = await getExternalStorageDirectory();
      final downloadsDir = io.Directory("${dir!.path}/downloads");

      if (!downloadsDir.existsSync()) {
        downloadsDir.createSync(recursive: true);
      }

      final filePath = '${downloadsDir.path}/customer_details.xlsx';
      final file = io.File(filePath);
      await file.writeAsBytes(bytes);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Downloaded to: $filePath")),
      );

      OpenFile.open(filePath);
    }
  } catch (e) {
    print("Error: $e");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Download failed: $e")),
    );
  }
}

// Build the button below the table with a title above it
Widget buildCustomerDetailsDownloadButton() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 4.0, bottom: 16),
        child: Text(
          'Download detailed customer report',
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
      ),
      SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.width * 0.14,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ElevatedButton(
            onPressed: () {
              downloadCustomerDetailsFile(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF8F5F2),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(
                  color: Color.fromARGB(255, 204, 203, 203),
                  width: 1.3,
                ),
              ),
              minimumSize: const Size.fromHeight(50),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.download, color: Colors.black, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Download',
                  style: GoogleFonts.poppins(color: Colors.black, fontSize: 13.5),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F5F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F5F2),
        elevation: 0,
        title: Text(
          'Customer Details',
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(
                  child: Text(
                    error!,
                    style: GoogleFonts.poppins(color: Colors.red, fontSize: 14),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.center,
                      child: buildCustomerDetailsDownloadButton(), // Corrected function name
                    ),
                  ],
                ),
    );
  }
}
