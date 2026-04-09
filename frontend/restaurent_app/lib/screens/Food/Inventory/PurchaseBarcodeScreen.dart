import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';

class PurchaseBarcodeScreen extends StatefulWidget {
  @override
  _PurchaseBarcodeScreenState createState() => _PurchaseBarcodeScreenState();
}

class _PurchaseBarcodeScreenState extends State<PurchaseBarcodeScreen> {
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _controller = TextEditingController();

  List<ScannedItem> scannedItems = [];
  final Map<int, TextEditingController> qtyControllers = {};

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

  @override
  void dispose() {
    for (var c in qtyControllers.values) {
      c.dispose();
    }
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
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

      // ✅ If item already exists, increase its quantity
      final index = scannedItems.indexWhere((item) => item.inventoryId == inventoryId);
      if (index != -1) {
        setState(() {
          scannedItems[index].quantity += quantity;
          qtyControllers[inventoryId]?.text =
              scannedItems[index].quantity.toString();
        });
        _controller.clear();
        _focusNode.requestFocus();
        return;
      }

      // Fetch item details
      final res = await http.get(Uri.parse('$baseUrl/inventory/$inventoryId'));
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

      final newItem = ScannedItem(
        inventoryId: inventoryId,
        itemName: itemName,
        quantity: quantity,
        unit: unit,
      );

      setState(() {
        scannedItems.add(newItem);
        qtyControllers[inventoryId] =
            TextEditingController(text: quantity.toString());
        _controller.clear();
        _focusNode.requestFocus();
      });
    } catch (e) {
      print('Error processing barcode: $e');
    }
  }

  Future<void> transferItems() async {
    if (scannedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items to transfer')),
      );
      return;
    }

    setState(() => isTransferring = true);
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() => isTransferring = false);

    Navigator.pop(context, scannedItems);
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
                        child: DataTable(
                          columnSpacing: 40,
                          headingRowColor: MaterialStateColor.resolveWith(
                              (states) => Colors.grey.shade200),
                          columns: const [
                            DataColumn(label: Text('Item Name')),
                            DataColumn(label: Text('Quantity')),
                            DataColumn(label: Text('Unit')),
                            DataColumn(label: Text('')),
                          ],
                          rows: scannedItems.map((item) {
                            final qtyController = qtyControllers[item.inventoryId]!;

                            return DataRow(
                              cells: [
                                DataCell(Text(item.itemName)),
                                DataCell(
                                  SizedBox(
                                    width: 80,
                                    child: TextField(
                                      controller: qtyController,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                            vertical: 4, horizontal: 8),
                                      ),
                                      onChanged: (val) {
                                        final newQty =
                                            double.tryParse(val) ?? item.quantity;
                                        setState(() {
                                          final index = scannedItems.indexWhere(
                                              (i) => i.inventoryId == item.inventoryId);
                                          if (index != -1) {
                                            scannedItems[index].quantity = newQty;
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                ),
                                DataCell(Text(item.unit)),
                                DataCell(
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () {
                                      setState(() {
                                        qtyControllers.remove(item.inventoryId);
                                        scannedItems.removeWhere((i) =>
                                            i.inventoryId == item.inventoryId);
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
                  label: Text(isTransferring ? 'Saving...' : 'Done'),
                  onPressed: isTransferring ? null : transferItems,
                  style: ElevatedButton.styleFrom(
                    textStyle: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
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
  double quantity;
  final String unit;

  ScannedItem({
    required this.inventoryId,
    required this.itemName,
    required this.quantity,
    required this.unit,
  });

  Map<String, dynamic> toMap() {
    return {
      'inventoryId': inventoryId,
      'itemName': itemName,
      'quantity': quantity,
      'unit': unit,
    };
  }
}
