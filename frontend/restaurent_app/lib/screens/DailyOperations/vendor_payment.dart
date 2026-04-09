import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class VendorPayment extends StatefulWidget {
  const VendorPayment({super.key});

  @override
  _VendorPaymentState createState() => _VendorPaymentState();
}

class _VendorPaymentState extends State<VendorPayment> {
  List<dynamic> purchaseHistory = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchPendingPurchases();
  }

  
Future<void> downloadImage(BuildContext context, String imageUrl) async {
  try {

    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = androidInfo.version.sdkInt;

    bool hasPermission = true;

    if (sdkInt <= 32) {
      final status = await Permission.storage.status;
      if (!status.isGranted) {
        final result = await Permission.storage.request();
        hasPermission = result.isGranted;
      } else {
        hasPermission = true;
      }
    }

    if (!hasPermission) {
      throw Exception('Storage permission not granted');
    }

    // Download the image using HTTP
    final response = await http.get(Uri.parse(imageUrl));

    if (response.statusCode == 200) {
      final bytes = response.bodyBytes;

      final dir = await getExternalStorageDirectory();
      final downloadsDir = Directory("${dir!.path}/downloads");

      if (!downloadsDir.existsSync()) {
        downloadsDir.createSync(recursive: true);
      }

      final filePath = '${downloadsDir.path}/downloaded_image_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      // Show a Snackbar with the success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Image downloaded to: $filePath")),
      );

      // Optionally, open the file using a default viewer (e.g., image viewer)
      OpenFile.open(filePath);
    } else {
      throw Exception('Failed to download image. Status: ${response.statusCode}');
    }
  } catch (e) {
    print("Error: $e");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Download failed: $e")),
    );
  }
}

  Future<void> fetchPendingPurchases() async {
    try {
      final response = await http.get(
        Uri.parse('${dotenv.env['API_URL']}/purchaseHistory/purchases/pending'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          purchaseHistory = data;
          isLoading = false;
        });
      } else {
        throw Exception('Failed to load pending purchases');
      }
    } catch (e) {
      print('Error fetching data: $e');
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F5F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F5F2),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              'Vendor Payment',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 3),
            Text(
              'Manage the pending vendor payment',
              style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey),
            ),
            SizedBox(height: 7),
          ],
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : purchaseHistory.isEmpty
              ? const Center(child: Text('No pending purchases found'))
              : buildPurchaseLayout(context),
    );
  }
Widget buildPurchaseLayout(BuildContext context) {
  return Padding(
    padding: const EdgeInsets.all(16.0),
    child: SingleChildScrollView(
      child: Center(
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.9,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: purchaseHistory.map<Widget>((purchaseData) {
              DateTime purchaseDate =
                  DateTime.tryParse(purchaseData['date']) ?? DateTime.now();
              double totalCost = purchaseData['amount'] is double
                  ? purchaseData['amount']
                  : double.tryParse(purchaseData['amount'].toString()) ?? 0.0;
              String title = purchaseData['title']?.toString() ?? 'N/A';
              String supplierName = purchaseData['vendor']?['name'] ?? 'Unknown Vendor';
              String deliveryStatus = purchaseData['delivery_status'] ?? 'N/A';
              String paymentStatus = purchaseData['payment_status'] ?? 'N/A';
              String paymentMethod = purchaseData['payment_method'] ?? 'N/A';
              String imagePath = purchaseData['receipt_image']?? 'N/A';

              List<dynamic> items = purchaseData['items'] ?? [];

              return Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E5E5)),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Date + Cost Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            DateFormat('dd MMM yyyy').format(purchaseDate),
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: const Color(0xFF1C1917),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color.fromARGB(255, 248, 159, 63),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              "₹$totalCost",
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                                color: const Color(0xFF1C1917),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 6),

                      // Title
                      Text(
                        title,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: const Color.fromARGB(255, 73, 71, 68),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),

                      // Supplier
                      Text(
                        supplierName,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: const Color(0xFF78726D),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Items heading
                      Text(
                        "Items:",
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF1C1917),
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Display first 2 items
                      ...items.take(2).map<Widget>((item) {
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              item['name'] ?? 'Unknown Item',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: const Color(0xFF1C1917),
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            Text(
                              "${item['qty']} ${item['unit']}",
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: const Color(0xFF1C1917),
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        );
                      }),

                      const SizedBox(height: 4),

                      if (items.length > 2)
                        Text(
                          "+ ${items.length - 2} more items",
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: const Color(0xFF78726D),
                            fontWeight: FontWeight.w400,
                          ),
                        ),

                      const SizedBox(height: 16),

                      // View Details button
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () {
                            showPurchaseDetailsPopup(
                              context,
                              items,
                              title,
                              supplierName,
                              purchaseDate,
                              deliveryStatus,
                              paymentStatus,
                              paymentMethod,
                              totalCost,
                              imagePath,
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            backgroundColor: const Color(0xFFF8F5F2),
                            side: const BorderSide(color: Color(0xFFE5E5E5)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(
                            "View Details",
                            style: GoogleFonts.poppins(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF1C1917),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    ),
  );
}

  TableRow tableRow(String name, String qty, String price) {
    return TableRow(children: [
      Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(name,
            style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w400)),
      ),
      Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(qty,
            style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w400)),
      ),
      Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(price,
            style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w400)),
      ),
    ]);
  }

  void showPurchaseDetailsPopup(
    BuildContext context,
    List<dynamic> items,
    String title,
    String supplierName,
    DateTime purchaseDate,
    String deliveryStatus,
    String paymentStatus,
    String paymentMethod,
    double totalCost,
    String? imagePath,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Text(
                      'Purchase Details',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: const Color(0xFF1C1917),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Purchase from $supplierName on ${DateFormat('dd MMM yyyy').format(purchaseDate)}',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: const Color(0xFF78726D),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Title: $title",
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                      color: const Color(0xFF1C1917),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Items:",
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                      color: const Color(0xFF1C1917),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE5E5E5)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Table(
                      columnWidths: const {
                        0: FlexColumnWidth(2),
                        1: FlexColumnWidth(1),
                        2: FlexColumnWidth(1),
                      },
                      border: TableBorder(
                        horizontalInside: BorderSide(
                          color: Color(0xFFE5E5E5),
                          width: 1,
                        ),
                      ),
                      children: items.map<TableRow>((item) {
                        return tableRow(
                          item['name'] ?? 'Unknown Item',
                          "${item['qty']} ${item['unit']}",
                          "₹${item['price']}",
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  rowText("Total:", "₹$totalCost"),
                  rowText("Delivery Status:", deliveryStatus),
                  rowText("Payment Status:", paymentStatus),
                  rowText("Payment Method:", paymentMethod),
                  const SizedBox(height: 16),
                  Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFD9D9D9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Stack(
                  children: [
                    // Image Widget
                    imagePath != null
                        ? Center(
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                'http://13.60.15.89:3000$imagePath',
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) => Center(
                                  child: Text("Failed to load image", style: GoogleFonts.poppins(fontSize: 12)),
                                ),
                              ),
                            ),
                        )
                        : Center(
                            child: Text(
                              "No Receipt Uploaded",
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                color: const Color(0xFF78726D),
                              ),
                            ),
                          ),

                    // Download Icon
                    if (imagePath != null)
                      Positioned(
                        right: 05,
                        bottom: 05,
                        child: GestureDetector(
                          onTap: () {
                            downloadImage(context, 'http://13.60.15.89:3000$imagePath');
                          },
                          child: CircleAvatar(
                            backgroundColor: Colors.blue,
                            radius: 10,
                            child: Icon(
                              Icons.download,
                              color: Colors.white,
                              size: 15,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF89F3F),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        "Close",
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget rowText(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w500,
              fontSize: 12,
              color: const Color(0xFF1C1917),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: const Color(0xFF1C1917),
            ),
          ),
        ],
      ),
    );
  }
}
