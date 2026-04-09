import 'dart:io' as io;
import 'package:Neevika/screens/Drinks/drinksKitchenInventory/DrinksKitchenInventoryScreen.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_file/open_file.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:core';
import 'package:Neevika/utils/web_downloader_stub.dart'
    if (dart.library.html) 'package:Neevika/utils/web_downloader_web.dart';

import 'package:barcode/barcode.dart';
import 'package:flutter/foundation.dart'; 

import 'package:Neevika/utils/barcode_printer_stub.dart'
    if (dart.library.html) 'package:Neevika/utils/barcode_printer_web.dart'
      as barcode_printer;

class ViewDrinksInventoryScreen extends StatefulWidget {
  const ViewDrinksInventoryScreen({super.key});

  @override
  State<ViewDrinksInventoryScreen> createState() => _ViewDrinksInventoryScreenState();
}

class _ViewDrinksInventoryScreenState extends State<ViewDrinksInventoryScreen> {
  List<dynamic> inventory = [];
  List<dynamic> purchaseHistory = [];
  List<dynamic> filteredInventory = [];
  List<dynamic> filteredPurchaseHistory = [];

  bool isInventoryLoading = true;
  bool isPurchaseHistoryLoading = true;
  bool hasInventoryError = false;
  bool hasPurchaseHistoryError = false;

  String searchQuery = '';
  String selectedCategory = 'Inventory Items';
  final List<String> categories = ['Inventory Items', 'Purchase History'];
  List<String> bottleSizes = ['90','180','330', '360','660', '750', '1000', '1500', '2000'];


  @override
  void initState() {
    super.initState();
    fetchInventory();
    fetchPurchaseHistory();
  }

  Future<void> fetchInventory() async {
    try {
      final response = await http
          .get(Uri.parse('${dotenv.env['API_URL']}/drinks-inventory/'))
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        setState(() {
          inventory = json.decode(response.body);
          filteredInventory = inventory;
          isInventoryLoading = false;
          hasInventoryError = false;
        });
      } else {
        setState(() {
          isInventoryLoading = false;
          hasInventoryError = true;
        });
      }
    } catch (e) {
      setState(() {
        isInventoryLoading = false;
        hasInventoryError = true;
      });
      print('Error fetching inventory: $e');
    }
  }



Future<void> _downloadExcel() async {
  final url = Uri.parse('${dotenv.env['API_URL']}/drinks-inventory/export-excel');
  print('Downloading from: $url');

  try {
    final response = await http.get(url);
    if (response.statusCode != 200) {
      throw Exception('Failed to download. Status: ${response.statusCode}');
    }

    final bytes = response.bodyBytes;
    const fileName = 'drinks-inventory.xlsx';

    if (kIsWeb) {
      triggerWebDownload(bytes, fileName);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Download started in browser")),
      );
      return;
    }

    // Mobile/Other platforms
    bool hasPermission = true;

    if (io.Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      if (sdkInt <= 32) {
        final status = await Permission.storage.status;
        if (!status.isGranted) {
          final result = await Permission.storage.request();
          hasPermission = result.isGranted;
        }
      }
    }

    if (!hasPermission) {
      throw Exception('Storage permission not granted');
    }

    // Store in app document directory or external storage
    final dir = io.Platform.isAndroid
        ? await getExternalStorageDirectory()
        : await getApplicationDocumentsDirectory();

    final downloadsDir = io.Directory('${dir!.path}/downloads');

    if (!downloadsDir.existsSync()) {
      downloadsDir.createSync(recursive: true);
    }

    final filePath = '${downloadsDir.path}/$fileName';
    final file = io.File(filePath);
    await file.writeAsBytes(bytes);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Downloaded to: $filePath")),
    );

    OpenFile.open(filePath);
  } catch (e) {
    print("Error: $e");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Download failed: $e")),
    );
  }
}


void printBarcodeDirectly({
    required String itemName,
    required String quantity,
    required String unit,
    required String barcodeData,
  }) {
    // Generate the SVG using the barcode package (works on all platforms)
    final barcode = Barcode.code128();
    final svg = barcode.toSvg(
      barcodeData,
      width: 110,
      height: 49,
      drawText: false,
    );

    // Delegate to the platform-specific impl:
    // - Web: opens print window and prints
    // - Mobile: no-op (safe for appbundle)
    barcode_printer.printBarcodeDirectly(
      itemName: itemName,
      quantity: quantity,
      unit: unit,
      barcodeData: barcodeData,
      svg: svg, // only used on web
    );
  }



Future<void> _uploadExcel() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
    withData: true, // safer on Android 13+
  );
  if (result == null) return;

  final fileBytes = result.files.single.bytes!;
  final fileName = result.files.single.name;
  final uri = Uri.parse('${dotenv.env['API_URL']}/drinks-inventory/bulk-upload');

  final request = http.MultipartRequest('POST', uri);
  request.files.add(http.MultipartFile.fromBytes('file', fileBytes, filename: fileName));

  try {
    final streamed = await request.send();
    final respStr = await streamed.stream.bytesToString();
    if (streamed.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload success!')),
      );
      fetchInventory();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $respStr')),
      );
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Upload error: $e')),
    );
  } 
}

  Future<void> fetchPurchaseHistory() async {
    try {
      final response = await http
          .get(Uri.parse('${dotenv.env['API_URL']}/drinks-purchaseHistory'))
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        setState(() {
          purchaseHistory = json.decode(response.body);
          filteredPurchaseHistory = purchaseHistory;
          print(purchaseHistory);
          isPurchaseHistoryLoading = false;
          hasPurchaseHistoryError = false;
        });
      } else {
        setState(() {
          isPurchaseHistoryLoading = false;
          hasPurchaseHistoryError = true;
        });
      }
    } catch (e) {
      setState(() {
        isPurchaseHistoryLoading = false;
        hasPurchaseHistoryError = true;
      });
      print('Error fetching purchase history: $e');
    }
  }

  // Filter inventory based on search query
  void filterInventory(String query) {
    List<dynamic> filteredItems =
        inventory
            .where(
              (item) =>
                  item['itemName'].toLowerCase().contains(query.toLowerCase()),
            )
            .toList();

    setState(() {
      filteredInventory = filteredItems;
    });
  }

  // Update item quantity or details
  void updateItem(int itemId) {
    print('Update item: $itemId');
  }

  void deleteItem(int itemId) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: const Text('Are you sure you want to delete this item?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text('Delete'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) {
      return; // User cancelled the deletion
    }

    final url = Uri.parse('${dotenv.env['API_URL']}/drinks-inventory/$itemId');

    try {
      final response = await http.delete(url);

      if (response.statusCode == 200) {
        fetchInventory();
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Item Deleted successfully!'),
            backgroundColor: Color(0xFFD95326),
          ),
        );
        print('Item $itemId deleted successfully.');
      } else {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Failed to delete item: ${response.statusCode}'),
            backgroundColor: Color(0xFFD95326),
          ),
        );
        print(
          'Failed to delete item $itemId. Status code: ${response.statusCode}',
        );
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Color(0xFFD95326),
        ),
      );
      print('Error deleting item $itemId: $e');
    }
  }

  // Get notification message for low and out-of-stock items
  String getNotificationMessage() {
    int outOfStockCount = 0;
    int lowStockCount = 0;

    for (var item in filteredInventory) {
      double quantity = item['quantity'].toDouble();
      if (quantity == 0) {
        outOfStockCount++;
      } else if (quantity <= 10) {
        lowStockCount++;
      }
    }

    if (outOfStockCount == 0 && lowStockCount == 0) {
      return ''; // No message if all items are okay
    }

    return '$outOfStockCount items out of stock and $lowStockCount items low in stock.';
  }

  // Build notification banner
  Widget buildNotificationBanner() {
    String message = getNotificationMessage();

    if (message.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: MediaQuery.of(context).size.width *1,

      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(253, 230, 138, 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.yellow.shade300),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Color.fromARGB(255, 198, 135, 48),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.poppins(
                color: Color.fromRGBO(146, 64, 14, 0.7),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Build status indicator
  Widget buildStatusIndicator(double quantity, double minQuantity) {
    String status = getStatus(quantity, minQuantity);
    Color statusColor =
        status == 'OK'
            ? Colors.green
            : (status == 'LOW' ? Colors.orange : Colors.red);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      height: 30  ,
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          status.toUpperCase(),
          style: GoogleFonts.poppins(
            color: statusColor,
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

Widget _buildSwitchButton() {
  return Center(
    child: Container(
      width: MediaQuery.of(context).size.width * 0.9,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEDEBE9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.9,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly, // Even spacing
            children: categories.map((category) {
              bool isSelected = selectedCategory == category;

              IconData? icon;
              if (category.toLowerCase() == 'inventory items') {
                icon = LucideIcons.packageOpen;
              } else if (category.toLowerCase() == 'purchase history') {
                icon = LucideIcons.clock;
              }

              return GestureDetector(
                onTap: () {
                  setState(() {
                    selectedCategory = category;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFFCFAF8) : const Color(0xFFEDEBE9),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : [],
                  ),
                  child: AnimatedScale(
                    scale: isSelected ? 1.05 : 1.0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: Row(
                      children: [
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 350),
                          opacity: isSelected ? 1.0 : 0.6,
                          child: Icon(
                            icon,
                            size: 16,
                            color: isSelected ? const Color(0xFF1C1917) : const Color(0xFF78726D),
                          ),
                        ),
                        const SizedBox(width: 6),
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 350),
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            color: isSelected ? const Color(0xFF1C1917) : const Color(0xFF78726D),
                          ),
                          child: Text(
                            category,
                            style: GoogleFonts.poppins(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
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


  Widget _buildContent() {
    if (selectedCategory == 'Inventory Items') {
      return buildInventoryList();
    } else {
      return buildPurchaseSection();
    }
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
    String image_path,
    double totalCost,
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Purchase Details',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: const Color(0xFF1C1917),
                      ),
                    ),
                  ],
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

                // Items Title
                Text(
                  "Items:",
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    color: const Color(0xFF1C1917),
                  ),
                ),
                const SizedBox(height: 8),

                // Table displaying items dynamically
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFE5E5E5)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(2),
                      1: FlexColumnWidth(1),
                     
                    },
                    border: TableBorder(
                      horizontalInside: BorderSide(
                        color: Color(0xFFE5E5E5),
                        width: 1,
                      ),
                    ),
                    children:
                        items.map<TableRow>((item) {
                          return tableRow(
                            item['name'] ?? 'Unknown Item',
                            "${item['qty']} ${item['unit']} ",
                            
                          );
                        }).toList(),
                  ),
                ),

                const SizedBox(height: 16),

                // Total (just a placeholder here, you can adjust based on actual data)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Total:",
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        color: const Color(0xFF1C1917),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Text(
                        totalCost
                            .toString(), // This should be dynamically calculated
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: const Color(0xFF1C1917),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Delivery Status:",
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        color: const Color(0xFF1C1917),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Text(
                        deliveryStatus, // This should be dynamically calculated
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: const Color(0xFF1C1917),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Payment Status:",
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        color: const Color(0xFF1C1917),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Text(
                        paymentStatus, // This should be dynamically calculated
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: const Color(0xFF1C1917),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Payment Method:",
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        color: const Color(0xFF1C1917),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Text(
                        paymentMethod, // This should be dynamically calculated
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: const Color(0xFF1C1917),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Receipt placeholder
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          '${dotenv.env['API_URL_1']}$image_path',
                          height: 120,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              height: 120,
                              color: const Color(0xFFD9D9D9),
                              alignment: Alignment.center,
                              child: Text(
                                "No Receipt Available",
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: const Color(0xFF78726D),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () async {
                        final imageUrl = '${dotenv.env['API_URL_1']}$image_path';
                        final filename = imageUrl.split('/').last;

                        await downloadImage(imageUrl, filename, context);
                      },
                      icon: const Icon(Icons.download_rounded, color: Colors.blue),
                      tooltip: 'Download Receipt',
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Close button
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
        );
      },
    );
  }


Future<void> downloadImage(String url, String filename, BuildContext context) async {
  if (kIsWeb) {
    final response = await http.get(Uri.parse(url));
    final bytes = response.bodyBytes;

    triggerWebDownload(bytes, filename);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Download started (web browser)")),
    );
    return;
  }

  // For mobile and desktop
  final status = await Permission.storage.request();
  if (!status.isGranted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Storage permission not granted')),
    );
    return;
  }

  final dir = await getDownloadsDirectory();
  final filePath = "${dir!.path}/$filename";

  final dio = Dio();
  await dio.download(url, filePath);

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Downloaded to $filePath')),
  );
}



  // Table row helper
  TableRow tableRow(String item, String quantity) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(item, style: GoogleFonts.poppins(fontSize: 14)),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(quantity, style: GoogleFonts.poppins(fontSize: 14)),
        ),
        
      ],
    );
  }

  Future<void> downloadPurchaseHistoryFile(BuildContext context) async {
  final url = Uri.parse(
    '${dotenv.env['API_URL']}/purchaseHistory/download',
  );

  try {
    final response = await http.get(url);

    if (response.statusCode != 200) {
      throw Exception('Failed to download. Status: ${response.statusCode}');
    }

    final bytes = response.bodyBytes;

    if (kIsWeb) {
      // Web: Trigger browser download
      triggerWebDownload(bytes, 'purchase_history.xlsx');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Download started (web browser)")),
      );
      return;
    }

    // Mobile/Desktop
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

    final filePath = '${downloadsDir.path}/purchase_history.xlsx';
    final file = io.File(filePath);
    await file.writeAsBytes(bytes);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Downloaded to: $filePath")),
    );

    OpenFile.open(filePath);
  } catch (e) {
    print("Error: $e");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Download failed: $e")),
    );
  }
}

  // Build the button below the search bar
  Widget buildPurchaseHistoryDownloadButton() {
    return SizedBox(
      width: MediaQuery.of(context).size.width *0.9, // Same width as the search bar
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12,), // Remove top margin, keep bottom padding
        child: ElevatedButton(
          onPressed: () {
            downloadPurchaseHistoryFile(context);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF8F5F2), // Background color
            elevation: 0, // No elevation (flat button)
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
              Icon(LucideIcons.download, color: Colors.black, size:18),
              SizedBox(width: 8),
              Text(
                'Download',
                style: GoogleFonts.poppins(color: Colors.black, fontSize: 13.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildPurchaseLayout() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Center(
        child: SizedBox(
          width:MediaQuery.of(context).size.width * 0.88, 
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Iterate through all purchase history entries
              ...purchaseHistory.map<Widget>((purchaseData) {
                DateTime purchaseDate =
                    DateTime.tryParse(purchaseData['date']) ?? DateTime.now();
                double totalCost =
                    purchaseData['amount'] is double
                        ? purchaseData['amount']
                        : double.tryParse(purchaseData['amount'].toString()) ??
                            0.0;
                String title = purchaseData['title'].toString() ?? 'N/A';
                String supplierName = purchaseData['vendor']['name'];
                String deliveryStatus = purchaseData['delivery_status'];
                String paymentStatus = purchaseData['payment_status'];
                String paymentMethod = purchaseData['payment_type'];
                String image_path = purchaseData['receipt_image']?? 'N/A';
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
                        // Display purchase date
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
                                  color: Color(0xFF1C1917),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          title.toString(),
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Color.fromARGB(255, 73, 71, 68),
                            fontWeight: FontWeight.w500
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          supplierName,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Color(0xFF78726D),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "Items:",
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF1C1917),
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Iterate through the items in this purchase
                        ...items.take(2).map<Widget>((item) {
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                item['name'] ?? 'Unknown Item',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: Color(0xFF1C1917),
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                              Text(
                                "${item['qty']} ${item['unit']}",
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: Color(0xFF1C1917),
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
                              color: Color(0xFF78726D),
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        const SizedBox(height: 16),
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
                                image_path,
                                totalCost,
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
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildPurchaseSection() {
    return Padding(
      padding: const EdgeInsets.all(0.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buildPurchaseLayout(),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.center,
            child: buildPurchaseHistoryDownloadButton(),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget buildInventoryTile(dynamic item) {
    double quantity = item['quantity'].toDouble();
    double minQuantity = item['minimumQuantity'].toDouble();
    String status = getStatus(quantity, minQuantity);
    bool isMobile = MediaQuery.of(context).size.width < 600;

    if (isMobile) {
      return Center(
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.91, 
          child: Card(
            color: Colors.white,
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: Color(0xFFE5E5E5),
                width: 1,
              ), // 🔴 Red border added here
            ),
            elevation: 0.2,
            child: Padding(
              padding: const EdgeInsets.only(left: 20,right: 20, top: 0, bottom: 0 ), // Reduced overall padding
              child: Theme(
                data: ThemeData(
                  dividerColor: Colors.transparent, // Removes divider line
                  splashColor: Colors.transparent, // Removes splash effect
                  highlightColor: Colors.transparent, // Removes highlight effect
                ),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero, // Removes padding around the tile
                  childrenPadding: EdgeInsets.only(left: 5, right: 12),
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "${item['itemName']}",
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5, // Reduced font size for the collapsed tile
                        ),
                      ),
                      buildStatusIndicator(quantity, minQuantity),
                    ],
                  ),
                  children: [
                    const SizedBox(height: 2),
                    buildInfoRow(
                      'Bottle Size:',
                      '${item['bottleSize']} ml',
                    ),

                    buildInfoRow(
                      'Quantity:',
                      '${item['quantity']} ${item['unit']}',
                    ),
                    buildInfoRow(
                      'Minimum Level:',
                      '${item['minimumQuantity']} ${item['minimumQuantity_unit']}',
                    ),
                    buildInfoRow('Last Updated:', formatDate(item['updatedAt'])),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 320,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  showUpdateItemDialog(
                                    context: context,
                                    itemId: item['id'].toString(),
                                    initialName: item['itemName'].toString(),
                                    initialQuantity: item['quantity'].toString(),
                                    initialUnit: item['unit'].toString(),
                                    initialMinQuantity:
                                        item['minimumQuantity'].toString(),
                                    initialMinUnit:
                                        item['minimumQuantity_unit'].toString(),
                                    
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Color(0xFFEDEBE9),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    side: BorderSide(
                                      color: Color.fromARGB(255, 204, 203, 203),
                                      width: 1,
                                    ),
                                  ),
                                ),
                                icon: const Icon(
                                  size: 15,
                                  LucideIcons.edit,
                                  color: Color(0xFF1C1917),
                                ),
                                label: Text(
                                  'Update',
                                  style: GoogleFonts.poppins(color: Colors.black, fontSize: 11.2),
                                ),
                              ),
                            ),
                                
                            const SizedBox(width: 70),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => deleteItem(item['id']),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Color(0xFFD95326),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: Text(
                                  'Delete',
                                  style: GoogleFonts.poppins(color: Colors.white,  fontSize: 11.2),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  // Helper method to build info rows for right alignment
  Widget buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              color: Color.fromARGB(255, 100, 100, 100),
              fontSize: 12,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // Build inventory item for web (Table Layout)
  TableRow buildInventoryRow(dynamic item) {
    double quantity = item['quantity'] != null ? item['quantity'].toDouble() : 0.0;
    double minQuantity = item['minimumQuantity'] != null ? item['minimumQuantity'].toDouble() : 0.0;
    String status = getStatus(quantity, minQuantity);

    String categoryName = item['category'] != null ? item['category']['categoryName'] : 'Unknown Category';

    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Text(
            '${item['itemName']}',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Text('${item['bottleSize']} ml'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Text('${item['quantity']} ${item['unit']}'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Text('${item['minimumQuantity']} ${item['unit']}'),
        ),
        Padding(
          padding: const EdgeInsets.only(right:40 , top: 12, bottom:12),
          child: buildStatusIndicator(
            item['quantity'].toDouble(),
            item['minimumQuantity'].toDouble(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              ElevatedButton.icon(
        onPressed: () {
          final itemName = item['itemName'];
          final quantity = item['barcode'].toString();
          final barcodeData = '${item['id']}#1#${item['unit']}';

          printBarcodeDirectly(
            itemName: itemName,
            quantity: '1',
            unit: item['unit'] ?? 'Kg',
            barcodeData: barcodeData,
          );
        },
        icon: Icon(Icons.print, color: Colors.white),
        label: Text(
          'Print',
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Color.fromARGB(255, 33, 215, 157),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),

      // Spacing
      const SizedBox(width: 10),


              ElevatedButton(
                onPressed: () => updateItem(item['id']),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade200,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'Update',
                  style: GoogleFonts.poppins(color: Colors.black),
                ),
              ),
              const SizedBox(width: 10),

              ElevatedButton(
                onPressed: () => deleteItem(item['id']),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFFD95326),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'Delete',
                  style: GoogleFonts.poppins(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Determine item status of the Inventory.
  String getStatus(double quantity, double minQuantity) {
    if (quantity == 0) {
      return 'OUT';
    } else if (quantity <= minQuantity) {
      return 'LOW';
    } else {
      return 'OK';
    }
  }

  // Format Date to YYYY-MM-DD
  String formatDate(String date) {
    DateTime parsedDate = DateTime.parse(date);
    return '${parsedDate.year}-${parsedDate.month.toString().padLeft(2, '0')}-${parsedDate.day.toString().padLeft(2, '0')}';
  }

  // Build search bar
  Widget buildSearchBar() {
    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.9,
      height:MediaQuery.of(context).size.height * 0.1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: TextField(
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: Colors.black, // Updated text color for visibility
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF8F5F2), // Background a
            hintText: 'Search Drinks Inventory...',
            hintStyle: GoogleFonts.poppins(
              fontSize: 12,
              color: const Color(0xFF1C1917), // Hint text color
            ),
            prefixIcon: const Icon(
              Icons.search,
              color: Color(0xFF1C1917), // Icon color
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: Color.fromARGB(255, 204, 203, 203),
                width: 1.3,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: Color(0xFFE5E5E5),
                width: 1.5,
              ),
            ),
          ),
          onChanged: (value) {
            setState(() {
              searchQuery = value;
              filterInventory(value);
            });
          },
        ),
      ),
    );
  }

  void showUpdateItemDialog({
    required BuildContext context,
    required String itemId,
    required String initialName,
    required String initialQuantity,
    required String initialUnit,
    required String initialMinQuantity,
    required String initialMinUnit,
    
  }) {
    List<String> sections = ['Bottle'];

    TextEditingController nameController = TextEditingController(
      text: initialName,
    );
    TextEditingController quantityController = TextEditingController(
      text: initialQuantity.toString(),
    );
    TextEditingController minQuantityController = TextEditingController(
      text: initialMinQuantity.toString(),
    );
    

    String? selectedUnit =
        sections.contains(initialUnit) ? initialUnit : sections[0];
    String? selectedMinUnit =
        sections.contains(initialMinUnit) ? initialMinUnit : sections[0];

    ScaffoldMessengerState scaffoldMessenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: const Color(0xFFEDEBE9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Update Item',
                        style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 20),

                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Item Name",
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          _buildInputField(
                            controller: nameController,
                            hintText: 'Enter Item Name',
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),

                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Quantity",
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                _buildInputField(
                                  controller: quantityController,
                                  hintText: 'Quantity',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Unit",
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                _buildDropdown(selectedUnit, sections, (value) {
                                  setState(() => selectedUnit = value);
                                }),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),

                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Min Quantity",
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                _buildInputField(
                                  controller: minQuantityController,
                                  hintText: 'Min Quantity',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Min Unit",
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                _buildDropdown(selectedMinUnit, sections, (
                                  value,
                                ) {
                                  setState(() => selectedMinUnit = value);
                                }),
                              ],
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 20),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              'Cancel',
                              style: GoogleFonts.poppins(
                                color: Color(0xFFD95326),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () async {
                              if (nameController.text.isNotEmpty &&
                                  quantityController.text.isNotEmpty &&
                                  selectedUnit != null &&
                                  minQuantityController.text.isNotEmpty &&
                                  selectedMinUnit != null 
                                  ){
                                final url = Uri.parse(
                                  '${dotenv.env['API_URL']}/drinks-inventory/$itemId/',
                                );

                                final body = jsonEncode({
                                  "itemName": nameController.text,
                                  "quantity":
                                      double.tryParse(
                                        quantityController.text,
                                      ) ??
                                      0,
                                  "unit": selectedUnit,
                                  "minimumQuantity":
                                      double.tryParse(
                                        minQuantityController.text,
                                      ) ??
                                      0,
                                  "minimumQuantity_unit": selectedMinUnit,
                                  
                                });

                                final headers = {
                                  'Content-Type': 'application/json',
                                  // Include auth token if required
                                  // 'Authorization': 'Bearer YOUR_TOKEN',
                                };

                                try {
                                  final response = await http.put(
                                    url,
                                    body: body,
                                    headers: headers,
                                  );

                                  if (response.statusCode == 200 ||
                                      response.statusCode == 204) {
                                    fetchInventory();
                                    scaffoldMessenger.showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Item updated successfully!',
                                        ),
                                      ),
                                    );

                                    Navigator.pop(context);
                                  } else {
                                    scaffoldMessenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Failed to update item: ${response.statusCode}',
                                        ),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  scaffoldMessenger.showSnackBar(
                                    SnackBar(content: Text('Error: $e')),
                                  );
                                }
                              } else {
                                scaffoldMessenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Please fill in all fields.'),
                                  ),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFFD95326),
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 40,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              'Update',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hintText,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: GoogleFonts.poppins(color: Colors.black38),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          vertical: 12,
          horizontal: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Color.fromARGB(
              255,
              204,
              203,
              203,
            ), // Set the border color here
            width: 1.2, // Set the border width
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Color.fromARGB(
              255,
              204,
              203,
              203,
            ), // Border color when the field is enabled
            width: 1.2, // Border width when the field is enabled
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: const Color.fromARGB(
              255,
              233,
              99,
              66,
            ), // Color when the field is focused
            width: 1.1, // Border width when the field is focused
          ),
        ),
      ),
    );
  }

  Widget _buildDropdown(
    String? selectedSection,
    List<String> sections,
    ValueChanged<String?> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      value: selectedSection,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Select Unit',
        hintStyle: GoogleFonts.poppins(color: Colors.black38),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          vertical: 12,
          horizontal: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Color.fromARGB(
              255,
              204,
              203,
              203,
            ), // Border color when the field is enabled
            width: 1.2,
          ),
        ),

        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Color.fromARGB(
              255,
              204,
              203,
              203,
            ), // Border color when the field is enabled
            width: 1.2, // Border width when the field is enabled
          ),
        ),

        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: const Color.fromARGB(
              255,
              233,
              99,
              66,
            ), // Set the border color when focused
            width: 1.1, // Border width when focused
          ),
        ),
      ),
      items:
          sections.map((section) {
            return DropdownMenuItem<String>(
              value: section,
              child: Text(section),
            );
          }).toList(),
    );
  }

  // Build the button below the search bar
  Widget buildAddButton(BuildContext context) {
    final buttonHeight = 45.0;

    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.9,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            // Kitchen Button
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => DrinksKitchenInventoryPage()),
            );
          },
                icon: const Icon(
                  LucideIcons.utensils,
                  color: Color(0xFF1C1917),
                  size: 15,
                ),
                label: Text(
                  "Kitchen",
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF1C1917),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  backgroundColor: const Color(0xFFF8F5F2),
                  side: const BorderSide(
                    color: Color.fromARGB(255, 204, 203, 203),
                    width: 1.3,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  minimumSize: Size.fromHeight(buttonHeight),
                ),
              ),
            ),
            const SizedBox(width: 16),

            // Add Purchase Button
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () async {
                  // Navigate to the add-drinks-purchase page
                  await Navigator.pushNamed(context, '/add_drinks_purchase');

                  // After returning from the page, fetch inventory
                  fetchInventory();
                },
                icon: const Icon(Icons.shopping_cart, color: Colors.white),
                label: Text(
                  'Add Purchase',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD95326),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  minimumSize: Size.fromHeight(buttonHeight),
                ),
              ),
            ),

          ],
        ),
      ),
    );
  }

  Future<void> downloadInventoryFile(BuildContext context) async {
  final url = Uri.parse('${dotenv.env['API_URL']}/drinks-inventory/download');
try {
    final response = await http.get(url);
    if (response.statusCode != 200) {
      throw Exception('Failed to download. Status: ${response.statusCode}');
    }

    final bytes = response.bodyBytes;

    if (kIsWeb) {
      // Web: trigger browser download
      triggerWebDownload(bytes, 'inventory.xlsx');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Download started (web browser)")),
      );
      return;
    }

    // Mobile/Desktop
    bool hasPermission = true;

    if (io.Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      if (sdkInt <= 32) {
        final status = await Permission.storage.status;
        if (!status.isGranted) {
          final result = await Permission.storage.request();
          hasPermission = result.isGranted;
        }
      }
    }

    if (!hasPermission) {
      throw Exception('Storage permission not granted');
    }

    final dir = await getApplicationDocumentsDirectory();
    final filePath = '${dir.path}/inventory.xlsx';
    final file = io.File(filePath);
    await file.writeAsBytes(bytes);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Downloaded to: $filePath")),
    );

    OpenFile.open(filePath);
  } catch (e) {
    print("Error: $e");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Download failed: $e")),
    );
  }
}


  // Build the button below the search bar
  Widget buildDownloadButton() {
    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.9, // Same width as the search bar
      // height:MediaQuery.of(context).size.width * 0.14, 

      child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _downloadExcel,
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
                      const Icon(Icons.download_rounded, color: Colors.black),
                      const SizedBox(width: 8),
                      Text(
                        'Download Excel Format',
                        style: GoogleFonts.poppins(
                          color: Colors.black,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // const SizedBox(width: 8),
              // Expanded(
              //   child: ElevatedButton(
              //     onPressed: _uploadExcel,
              //     style: ElevatedButton.styleFrom(
              //       backgroundColor: const Color(0xFFF8F5F2),
              //       elevation: 0,
              //       shape: RoundedRectangleBorder(
              //         borderRadius: BorderRadius.circular(10),
              //         side: const BorderSide(
              //           color: Color.fromARGB(255, 204, 203, 203),
              //           width: 1.0,
              //         ),
              //       ),
              //       minimumSize: const Size.fromHeight(50),
              //     ),
              //     child: Row(
              //       mainAxisAlignment: MainAxisAlignment.center,
              //       children: [
              //         const Icon(Icons.upload_rounded, color: Colors.black),
              //         const SizedBox(width: 8),
              //         Text(
              //           'Upload Excel',
              //           style: GoogleFonts.poppins(
              //             color: Colors.black,
              //             fontSize: 11,
              //           ),
              //         ),
              //       ],
              //     ),
              //   ),
              // ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: ElevatedButton(
            onPressed: () {
              downloadInventoryFile(context);
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
                Icon(LucideIcons.download, color: Colors.black),
                const SizedBox(width: 8),
                Text(
                  'Download Current Inventory',
                  style: GoogleFonts.poppins(
                    color: Colors.black,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
    );
  }

  Widget buildInventoryList() {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isMobile = constraints.maxWidth < 600;

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!isMobile)
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 65.0),
                  child: buildNotificationBanner(),
                ),
              if (isMobile)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18.0),
                  child: buildNotificationBanner(),
                ),
              const SizedBox(height: 12),
              if (isMobile)
                ...filteredInventory
                    .map((item) => buildInventoryTile(item))
                    
              else
                Container(
                  width: constraints.maxWidth * 0.9,
                  margin: const EdgeInsets.symmetric(vertical: 16, horizontal: 40),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                  child: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(2), // Item
                      1: FlexColumnWidth(1), // Bottle Size
                      2: FlexColumnWidth(0.7), // Quantity
                      3: FlexColumnWidth(1), // Min Quantity
                      4: FlexColumnWidth(0.7), // Status
                      5: FlexColumnWidth(2), // Actions
                    },
                    border: TableBorder(
                      horizontalInside: BorderSide(color: Colors.grey.shade300),
                      bottom: BorderSide(color: Colors.grey.shade300),
                    ),
                    children: [
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: _buildTableHeader('Item'),
                          ),
                          _buildTableHeader('Bottle Size'), 
                          _buildTableHeader('Quantity'),
                          Padding(
                            padding: const EdgeInsets.only(right: 16.0),
                            child: _buildTableHeader('Min Quantity'),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 5),
                            child:_buildTableHeader('Status'),
                          ),
                         Padding(
                            padding: const EdgeInsets.only(left: 75),
                            child: _buildTableHeader('Actions'),
                         ),
                        ],
                      ),
                      ...filteredInventory.map(
                        (item) => buildInventoryRow(item),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 40),
              Align(alignment: Alignment.center, child: buildDownloadButton()),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTableHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Text(
        title,
        style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
      ),
    );
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
            const SizedBox(height: 4),
            Text(
              'Drinks Inventory',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Manage restaurant drinks inventory and supplies',
              style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey),
            ),
            SizedBox(height: 7),
          ],
        ),
      ),
      body:
          isInventoryLoading || isPurchaseHistoryLoading
              ? Center(
                child: LoadingAnimationWidget.staggeredDotsWave(
                  color: Colors.black,
                  size: 40,
                ),
              )
              : hasPurchaseHistoryError || hasInventoryError 
              ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.alertTriangle,
                      size: 60,
                      color: Color(0xFFEF4444), // Tailwind red-500
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "Something went wrong",
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1F2937), // Tailwind gray-800
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Please check your connection or try again.",
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          isPurchaseHistoryLoading = true;
                          isInventoryLoading = true;
                          
                          hasPurchaseHistoryError = false;
                          hasInventoryError = false;
                        });
                        fetchInventory(); // Try again
                      },
                      icon: const Icon(
                        LucideIcons.refreshCw,
                        size: 20,
                        color: Colors.white,
                      ),
                      label: Text(
                        "Retry",
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(
                          0xFF2563EB,
                        ), // Tailwind blue-600
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              )
              : Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1600),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 18),
                        _buildSwitchButton(),
                        buildSearchBar(),
                        buildAddButton(context),
                        _buildContent(),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ),
    );
  }
}
