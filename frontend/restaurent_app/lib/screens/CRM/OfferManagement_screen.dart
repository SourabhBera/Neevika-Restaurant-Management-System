import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:open_file/open_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class OfferManagementPage extends StatefulWidget {
  const OfferManagementPage({super.key});

  @override
  State<OfferManagementPage> createState() => _OfferManagementPageState();
}

class _OfferManagementPageState extends State<OfferManagementPage> {
  List offers = [];
  final baseUrl = '${dotenv.env['API_URL']}/crm/QR-offer';

  @override
  void initState() {
    super.initState();
    fetchOffers();
  }

  Future<void> fetchOffers() async {
    final response = await http.get(Uri.parse(baseUrl));
    if (response.statusCode == 200) {
      setState(() => offers = jsonDecode(response.body));
    }
  }

  Future<void> deleteOffer(int id) async {
    final res = await http.delete(Uri.parse('$baseUrl/$id'));
    if (res.statusCode == 200) {
      fetchOffers();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Offer deleted', style: GoogleFonts.poppins())),
      );
    }
  }

  void showOfferDialog({Map? existingOffer}) {
    final formKey = GlobalKey<FormState>();
    final codeController = TextEditingController(text: existingOffer?['offer_code'] ?? '');
    final valueController = TextEditingController(text: existingOffer?['offer_value']?.toString() ?? '');
    String offerType = existingOffer?['offer_type'] ?? 'percent';
    final bool isEditing = existingOffer != null;

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isEditing ? 'Edit Offer' : 'Add New Offer',
                      style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: codeController,
                      decoration: InputDecoration(
                        labelText: 'Offer Code',
                        labelStyle: GoogleFonts.poppins(),
                        border: const OutlineInputBorder(),
                      ),
                      style: GoogleFonts.poppins(),
                      validator: (v) => v!.isEmpty ? 'Enter offer code' : null,
                    ),
                    const SizedBox(height: 15),
                    DropdownButtonFormField<String>(
                      value: offerType,
                      decoration: InputDecoration(
                        labelText: 'Offer Type',
                        labelStyle: GoogleFonts.poppins(),
                        border: const OutlineInputBorder(),
                      ),
                      items: ['percent', 'cash']
                          .map((t) => DropdownMenuItem(
                                value: t,
                                child: Text(t.toUpperCase(), style: GoogleFonts.poppins()),
                              ))
                          .toList(),
                      onChanged: (v) => offerType = v!,
                      style: GoogleFonts.poppins(),
                    ),
                    const SizedBox(height: 15),
                    TextFormField(
                      controller: valueController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Offer Value',
                        labelStyle: GoogleFonts.poppins(),
                        border: const OutlineInputBorder(),
                      ),
                      style: GoogleFonts.poppins(),
                      validator: (v) => v!.isEmpty ? 'Enter offer value' : null,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text('Cancel', style: GoogleFonts.poppins()),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: () async {
                            if (formKey.currentState!.validate()) {
                              final data = {
                                'offer_code': codeController.text.trim(),
                                'offer_type': offerType,
                                'offer_value': double.parse(valueController.text.trim()),
                              };
                              final url = isEditing
                                  ? Uri.parse('$baseUrl/${existingOffer!['id']}')
                                  : Uri.parse(baseUrl);
                              final resp = isEditing
                                  ? await http.put(url, body: jsonEncode(data), headers: {'Content-Type': 'application/json'})
                                  : await http.post(url, body: jsonEncode(data), headers: {'Content-Type': 'application/json'});
                              if (resp.statusCode == 200 || resp.statusCode == 201) {
                                fetchOffers();
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(isEditing ? 'Offer updated' : 'Offer added', style: GoogleFonts.poppins())),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error: ${resp.body}', style: GoogleFonts.poppins())),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Text(isEditing ? 'Update' : 'Add', style: GoogleFonts.poppins()),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void showQRDialog(String offerCode) async {
    final qrKey = GlobalKey();
    final qrUrl = 'http://13.60.15.89/customer-form?offerCode=${Uri.encodeComponent(offerCode)}';

    Future<void> _downloadQRCode() async {
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Storage permission is required to save the QR code.', style: GoogleFonts.poppins())),
          );
          return;
        }

        RenderRepaintBoundary boundary = qrKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
        ui.Image image = await boundary.toImage(pixelRatio: 3.0);
        ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);

        if (byteData == null) throw Exception("Failed to convert QR to bytes");

        final bytes = byteData.buffer.asUint8List();

        final dir = await getExternalStorageDirectory();
        final downloadsDir = Directory("${dir!.path}/downloads");

        if (!downloadsDir.existsSync()) {
          downloadsDir.createSync(recursive: true);
        }

        final filePath = '${downloadsDir.path}/qr_${offerCode}_${DateTime.now().millisecondsSinceEpoch}.png';
        final file = File(filePath);
        await file.writeAsBytes(bytes);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("QR code saved to: $filePath", style: GoogleFonts.poppins())),
        );

        await OpenFile.open(filePath);
      } catch (e) {
        print("Error saving QR code: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to save QR code: $e", style: GoogleFonts.poppins())),
        );
      }
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('QR for $offerCode', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 20),
              RepaintBoundary(
                key: qrKey,
                child: QrImageView(
                  data: qrUrl,
                  version: QrVersions.auto,
                  size: 200,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _downloadQRCode,
                icon: const Icon(Icons.download),
                label: Text('Download QR', style: GoogleFonts.poppins()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Close', style: GoogleFonts.poppins()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: Text('QR Offers', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16)),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: offers.isEmpty
                  ? Center(
                      child: Text(
                        'No offers available.',
                        style: GoogleFonts.poppins(fontSize: 15, color: Colors.grey),
                      ),
                    )
                  : ListView.separated(
                      itemCount: offers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, idx) {
                        final offer = offers[idx];
                        final offerCode = offer['offer_code'];
                        final type = offer['offer_type'];
                        final value = offer['offer_value'];
                        return GestureDetector(
                          onTap: () => showQRDialog(offerCode),
                          child: Card(
                            elevation: 4,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            color: Colors.white,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '$offerCode  (${type == 'percent' ? '$value%' : '₹$value'})',
                                          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13.5),
                                        ),
                                        const SizedBox(height: 4),
                                        Text('Value: $value', style: GoogleFonts.poppins(fontSize: 12)),
                                        const SizedBox(height: 2),
                                        Text('Type: $type', style: GoogleFonts.poppins(fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.amber),
                                    onPressed: () => showOfferDialog(existingOffer: offer),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                                    onPressed: () => deleteOffer(offer['id']),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 10),
            SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text('Add New Offer', style: GoogleFonts.poppins()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => showOfferDialog(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
