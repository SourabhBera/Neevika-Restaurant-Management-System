import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_file/open_file.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<Map<String, dynamic>> inventoryData = [];
  bool isLoading = false;

  String filter = 'All'; // Current filter

  @override
  void initState() {
    super.initState();
    fetchInventoryData();
  }

  Future<void> fetchInventoryData() async {
  setState(() => isLoading = true);

  try {
    List<Map<String, dynamic>> combinedData = [];

    if (filter == 'Drinks Inventory') {
      final url = Uri.parse('${dotenv.env['API_URL']}/other-reports/drinks-inventory-report');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        combinedData = List<Map<String, dynamic>>.from(decoded['data']);
      }
    } else if (filter == 'Food Inventory') {
      final url = Uri.parse('${dotenv.env['API_URL']}/other-reports/inventory-report');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        combinedData = List<Map<String, dynamic>>.from(decoded['data']);
      }
    } else if (filter == 'All') {
      final foodUrl = Uri.parse('${dotenv.env['API_URL']}/other-reports/inventory-report');
      final drinksUrl = Uri.parse('${dotenv.env['API_URL']}/other-reports/drinks-inventory-report');

      final foodResponse = await http.get(foodUrl);
      final drinksResponse = await http.get(drinksUrl);

      if (foodResponse.statusCode == 200 && drinksResponse.statusCode == 200) {
        final foodData = json.decode(foodResponse.body);
        final drinksData = json.decode(drinksResponse.body);

        combinedData = [
          ...List<Map<String, dynamic>>.from(foodData['data']),
          ...List<Map<String, dynamic>>.from(drinksData['data']),
        ];
      }
    }

    // Sort: 0 qty → low qty → rest
    combinedData.sort((a, b) {
      final qtyA = a['quantity'] ?? 0;
      final qtyB = b['quantity'] ?? 0;
      final minA = a['minimum_quantity'] ?? 0;
      final minB = b['minimum_quantity'] ?? 0;

      int rank(dynamic qty, dynamic min) {
        if (qty == 0) return 0;
        if (qty < min) return 1;
        return 2;
      }

      return rank(qtyA, minA).compareTo(rank(qtyB, minB));
    });

    setState(() {
      inventoryData = combinedData;
      isLoading = false;
    });
  } catch (e) {
    print('Error fetching inventory: $e');
    setState(() => isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to fetch inventory: $e")));
  }
}

  Future<void> downloadReport(String format) async {
  final typeParam = filter == 'Drinks Inventory'
      ? 'drinks'
      : filter == 'Food Inventory'
          ? 'food'
          : 'all';

  final url = Uri.parse(
    '${dotenv.env['API_URL']}/inventory/download?exportType=$format&type=$typeParam',
  );

  try {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    final sdkInt = androidInfo.version.sdkInt;

    bool hasPermission = true;

    // Request appropriate permissions based on Android version
    if (sdkInt >= 33) {
      // Android 13+: Request MANAGE_EXTERNAL_STORAGE for Downloads folder access
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

      // Get main Downloads folder
      final downloadDir = await getDownloadsDirectory();
      if (downloadDir == null) {
        throw Exception('Downloads directory not available');
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'Inventory_${typeParam}_$timestamp.$format';
      final filePath = '${downloadDir.path}/$fileName';

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


  Color? getRowColor(Map<String, dynamic> item) {
  switch (getItemStatus(item)) {
    case 'critical':
      return Colors.red.shade100;
    case 'warning':
      return Colors.yellow.shade100;
    default:
      return null;
  }
}


  String getItemStatus(Map<String, dynamic> item) {
  final qty = item['quantity'] ?? 0;
  final min = item['minimum_quantity'] ?? 0;

  if (qty == 0) return 'critical';
  if (qty < min) return 'warning';
  return 'ok';
}

  Widget buildFilterChips() {
    const filters = ['All', 'Food Inventory', 'Drinks Inventory'];
    return Row(
      children: filters.map((label) {
        final isSelected = filter == label;
        return Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: ChoiceChip(
            label: Text(label, style: GoogleFonts.poppins(fontSize: 12)),
            selected: isSelected,
            onSelected: (_) {
              setState(() => filter = label);
              fetchInventoryData();
            },
            selectedColor: Colors.deepPurple.shade100,
            backgroundColor: Colors.grey.shade200,
            labelStyle: TextStyle(color: isSelected ? Colors.deepPurple : Colors.black),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F5F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F5F2),
        elevation: 0,
        title: Text('Inventory', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            buildFilterChips(),
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
                    child: inventoryData.isEmpty
                        ? const Center(child: Text('No inventory data found.'))
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingRowColor: MaterialStateProperty.all(Colors.deepPurple.shade100),
                              columns: [
                                DataColumn(label: Text('Item', style: GoogleFonts.poppins(fontSize: 11))),
                                DataColumn(label: Text('Qty', style: GoogleFonts.poppins(fontSize: 11))),
                                DataColumn(label: Text('Min Qty', style: GoogleFonts.poppins(fontSize: 11))),
                                DataColumn(label: Text('Unit', style: GoogleFonts.poppins(fontSize: 11))),
                              ],
                              rows: inventoryData.map((item) {
                                return DataRow(
                                  color: MaterialStateProperty.all(getRowColor(item)),
                                  cells: [
                                    DataCell(Text(item['itemName'], style: GoogleFonts.poppins(fontSize: 10))),
                                    DataCell(Text(item['quantity'].toString(), style: GoogleFonts.poppins(fontSize: 10))),
                                    DataCell(Text(item['minimum_quantity'].toString(), style: GoogleFonts.poppins(fontSize: 10))),
                                    DataCell(Text(item['unit'], style: GoogleFonts.poppins(fontSize: 10))),
                                  ],
                                );
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
