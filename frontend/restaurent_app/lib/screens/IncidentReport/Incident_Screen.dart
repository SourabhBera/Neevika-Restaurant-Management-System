import 'dart:convert';
import 'dart:io';
import 'package:Neevika/widgets/sidebar.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class IncidentScreen extends StatefulWidget {
  const IncidentScreen({super.key});

  @override
  State<IncidentScreen> createState() => _IncidentScreenState();
}

class _IncidentScreenState extends State<IncidentScreen> {
  List incidents = [];
  final String baseUrl = "${dotenv.env['API_URL']}/incident-report/";

  Future<void> fetchIncidents() async {
    try {
      final res = await http.get(Uri.parse(baseUrl));
      if (res.statusCode == 200) {
        setState(() => incidents = jsonDecode(res.body));
      }
    } catch (e) {
      print("Error fetching incidents: $e");
    }
  }

  Future<void> downloadImage(BuildContext context, String imageUrl) async {
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

      final response = await http.get(Uri.parse(imageUrl));

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final dir = await getExternalStorageDirectory();
        final downloadsDir = Directory("${dir!.path}/downloads");

        if (!downloadsDir.existsSync()) {
          downloadsDir.createSync(recursive: true);
        }

        final filePath =
            '${downloadsDir.path}/incident_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final file = File(filePath);
        await file.writeAsBytes(bytes);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Image saved: $filePath")),
        );

        OpenFile.open(filePath);
      } else {
        throw Exception('Failed to download image');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Download failed: $e")),
      );
    }
  }

  Future<void> showIncidentDetails(Map<String, dynamic> incident) async {
    print('${dotenv.env['API_URL_1']}${incident['images']}');
    await showDialog(
      context: context,
      builder: (_) {
        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Incident Details",
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _detailRow("Title", incident['title']),
                  _detailRow("Description", incident['description'] ?? "-"),
                  _detailRow(
                    "Date",
                    DateFormat('dd MMM yyyy HH:mm').format(
                      DateTime.parse(incident['incidentDate']),
                    ),
                  ),
                  _detailRow("Reported by", incident['userId'] ?? "-"),
                  const SizedBox(height: 16),
                  Text(
                    "Images:",
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 10),
                  if (incident['images'] != null &&
                      (incident['images'] as List).isNotEmpty)
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: (incident['images'] as List).map((imgPath) {
                        final rawPath = imgPath.toString();
                        final normalizedPath = rawPath
                            .replaceAll(r'\', '/')   // convert backslashes to forward slashes
                            .replaceAll('..', '');   // remove the double dots

                        final url = "${dotenv.env['API_URL_1']}$normalizedPath";
                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                url,
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              right: 4,
                              bottom: 4,
                              child: GestureDetector(
                                onTap: () => downloadImage(context, url),
                                child: const CircleAvatar(
                                  backgroundColor: Color(0xFFF89F3F),
                                  radius: 14,
                                  child: Icon(Icons.download,
                                      color: Colors.white, size: 16),
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    )
                  else
                    Text(
                      "No images uploaded",
                      style: GoogleFonts.poppins(fontSize: 14),
                    ),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        "Close",
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF78726D),
                        ),
                      ),
                    ),
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, dynamic value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "$label: ",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: const Color(0xFF3E3E3E),
          ),
        ),
        Expanded(
          child: Text(
            value?.toString() ?? "-",
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w400,
              fontSize: 13,
              color: const Color(0xFF6E6E6E),
            ),
          ),
        ),
      ],
    ),
  );
}

  @override
  void initState() {
    super.initState();
    fetchIncidents();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F5F2),
        drawer: const Sidebar(),
        appBar: AppBar(
          title: Text(
            "Incident Reports",
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 20,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFFF89F3F),
          elevation: 0,
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () =>
              Navigator.pushNamed(context, '/add-incident-report').then((_) {
            fetchIncidents();
          }),
          backgroundColor: const Color(0xFFF89F3F),
          child: const Icon(Icons.add, size: 28),
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 3,
            child: ListView.separated(
              itemCount: incidents.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final incident = incidents[index];
                return ListTile(
                  onTap: () => showIncidentDetails(incident),
                  leading: const Icon(Icons.report, color: Color(0xFFF89F3F)),
                  title: Text(
                    incident['title'] ?? "Untitled",
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    DateFormat('dd MMM yyyy – HH:mm').format(
                      DateTime.parse(incident['incidentDate']),
                    ),
                    style: GoogleFonts.poppins(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
