import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';

class DrinksBarcodeTransferScreen extends StatefulWidget {
  @override
  _DrinksBarcodeTransferScreenState createState() => _DrinksBarcodeTransferScreenState();
}

class _DrinksBarcodeTransferScreenState extends State<DrinksBarcodeTransferScreen> {
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _controller = TextEditingController();

  List<ScannedItem> scannedItems = [];
  bool isTransferring = false;

  late final String baseUrl;

  @override
  void initState() {
    super.initState();
    final envBaseUrl = dotenv.env['API_URL'];
    if (envBaseUrl == null) {
      throw Exception('API_URL not found in .env file');
    }
    baseUrl = envBaseUrl;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  void handleBarcode(String barcodeText) async {
  try {
    print('Scanned barcode: $barcodeText');

    final parts = barcodeText.trim().split('#');
    if (parts.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid barcode format')),
      );
      return;
    }

    final inventoryId = int.tryParse(parts[0]);
    final quantity = double.tryParse(parts[1]);
    final unit = parts[2];

    if (inventoryId == null || quantity == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid barcode values')),
      );
      return;
    }

    final index = scannedItems.indexWhere((item) => item.inventoryId == inventoryId);

    if (index != -1) {
      // ✅ Increase quantity if item already exists
      setState(() {
        scannedItems[index] = ScannedItem(
          inventoryId: scannedItems[index].inventoryId,
          itemName: scannedItems[index].itemName,
          quantity: scannedItems[index].quantity + quantity,
          unit: scannedItems[index].unit,
        );
        _controller.clear();
        _focusNode.requestFocus();
      });
      return;
    }

    final res = await http.get(Uri.parse('$baseUrl/drinks-inventory/$inventoryId'));
    if (res.statusCode != 200) {
      print('API error: ${res.statusCode}');
      return;
    }

    final data = jsonDecode(res.body);
    final itemName = data['itemName'];

    if (itemName == null) {
      print('Invalid item data');
      return;
    }

    setState(() {
      scannedItems.add(ScannedItem(
        inventoryId: inventoryId,
        itemName: itemName,
        quantity: quantity,
        unit: unit,
      ));
      _controller.clear();
      _focusNode.requestFocus();
    });
  } catch (e) {
    print('Error processing barcode: $e');
  }
}

  Future<void> transferItems() async {
    if (scannedItems.isEmpty) return;

    setState(() => isTransferring = true);

    for (final item in scannedItems) {
      final response = await http.post(
        Uri.parse('$baseUrl/drinks-kitchen-inventory/scan-barcode-transfer'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'barcode': '${item.inventoryId}#${item.quantity}#${item.unit}',
          'userId': 2, // Replace with actual user ID
        }),
      );

      if (response.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to transfer ${item.itemName}')),
        );
      }
    }

    setState(() {
      scannedItems.clear();
      isTransferring = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All items transferred successfully')),
    );

    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = GoogleFonts.poppinsTextTheme();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text('Barcode Transfer', style: textTheme.titleMedium),
        centerTitle: true,
        elevation: 1,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Scanned Items',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // 🔍 Hidden TextField for barcode input
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              onSubmitted: handleBarcode,
              autofocus: true,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Scan barcode...',
              ),
              style: const TextStyle(color: Colors.transparent),
              cursorColor: Colors.transparent,
            ),

            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                  color: Colors.white,
                ),
                child: scannedItems.isEmpty
                    ? const Center(
                        child: Text(
                          'Scan items with your barcode scanner...',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: DataTable(
                          columnSpacing: 40,
                          headingRowColor: MaterialStateColor.resolveWith(
                              (states) => Colors.grey.shade200),
                          dataRowColor:
                              MaterialStateColor.resolveWith((states) => Colors.white),
                          columns: const [
                            DataColumn(label: Text('Item Name')),
                            DataColumn(label: Text('Quantity')),
                            DataColumn(label: Text('Unit')),
                            DataColumn(label: Text('')),
                          ],
                          rows: scannedItems.map((item) {
                            return DataRow(
                              cells: [
                                DataCell(Text(item.itemName)),
                                DataCell(Text(item.quantity.toString())),
                                DataCell(Text(item.unit)),
                                DataCell(
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () {
                                      setState(() {
                                        scannedItems.removeWhere((i) => i.inventoryId == item.inventoryId);
                                      });
                                    },
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 24),

            Align(
              alignment: Alignment.center,
              child: SizedBox(
                width: 300,
                height: 50,
                child: ElevatedButton.icon(
                  icon: isTransferring
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.check),
                  label: Text(isTransferring ? 'Transferring...' : 'Transfer Items'),
                  onPressed: isTransferring ? null : transferItems,
                  style: ElevatedButton.styleFrom(
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

class ScannedItem {
  final int inventoryId;
  final String itemName;
  final double quantity;
  final String unit;

  ScannedItem({
    required this.inventoryId,
    required this.itemName,
    required this.quantity,
    required this.unit,
  });
}
