import 'package:Neevika/screens/Food/kitchenInventory/BarcodeTransferScreen.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:Neevika/screens/Food/kitchenInventory/TransferHistory.dart';
import 'package:Neevika/screens/Vendors/VendorAddScreen.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:open_file/open_file.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:flutter/foundation.dart';

class KitchenInventoryPage extends StatefulWidget {
  const KitchenInventoryPage({super.key});

  @override
  _KitchenInventoryPageState createState() => _KitchenInventoryPageState();
}

class _KitchenInventoryPageState extends State<KitchenInventoryPage> {
  List<dynamic> kitchenInventoryItems = [];
  List<dynamic> filteredKitchen= [];
  List<dynamic> mainInventoryItems = [];
  List<dynamic> filteredinventory = [];
  bool isInventoryLoading = true;
  bool hasInventoryErrorOccurred = false;

  bool iskitchenLoading = true;
  bool haskitchenErrorOccurred = false;
  String searchQuery = '';
  String selectedTab = "Kitchen"; // Manage selectedTab state
  Map<String, bool> selectedItems = {};
  Map<String, String> selectedItemIds = {};

  Map<String, TextEditingController> quantityControllers = {};

  Map<String, String?> rowUnits = {};

  void updateSelectedTab(String tab) {
    setState(() {
      selectedTab = tab;
    });
  }

  @override
  void initState() {
    super.initState();
    fetchkitchenInventory();
    fetchMainInventory();
  }

  Future<void> fetchMainInventory() async {
    try {
      final response = await http
          .get(Uri.parse('${dotenv.env['API_URL']}/inventory/'))
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        setState(() {
          mainInventoryItems = json.decode(response.body);
          filteredinventory = mainInventoryItems;
          isInventoryLoading = false;
          hasInventoryErrorOccurred = false;
        });
      } else {
        await Future.delayed(const Duration(seconds: 4));
        setState(() {
          isInventoryLoading = false;
          hasInventoryErrorOccurred = true;
        });
      }
    } catch (e) {
      await Future.delayed(const Duration(seconds: 4));
      setState(() {
        isInventoryLoading = false;
        hasInventoryErrorOccurred = true;
      });
      print('Error fetching vendors: $e');
    }
  }

  Future<void> fetchkitchenInventory() async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '${dotenv.env['API_URL']}/kitchen-inventory/inventory/',
            ),
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        setState(() {
          kitchenInventoryItems = json.decode(response.body);
          filteredinventory = kitchenInventoryItems;
          iskitchenLoading = false;
          haskitchenErrorOccurred = false;
        });
      } else {
        await Future.delayed(const Duration(seconds: 4));
        setState(() {
          iskitchenLoading = false;
          haskitchenErrorOccurred = true;
        });
      }
    } catch (e) {
      await Future.delayed(const Duration(seconds: 4));
      setState(() {
        iskitchenLoading = false;
        haskitchenErrorOccurred = true;
      });
      print('Error fetching vendors: $e');
    }
  }

  void transferItems(List<Map<String, dynamic>> items) async {
  final String apiUrl = '${dotenv.env['API_URL']}/kitchen-inventory/transfer/';
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('jwtToken');
  if (token == null) {
    print('No token found. User might not be logged in.');
    return;
  }
  final decodedToken = JwtDecoder.decode(token);
  final userId = decodedToken['id'];

  try {
    for (var item in items) {
      final quantity = item['quantity']?.toString();
      final unit = item['unit']?.toString();

      if (quantity == null || quantity.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Quantity is required for ${item['name'] ?? 'an item'}')),
        );
        return;
      }

      if (unit == null || unit.isEmpty || unit == 'null') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unit is required for ${item['name'] ?? 'an item'}')),
        );
        return;
      }

      final Map<String, dynamic> transferData = {
        'inventoryId': item['id'],
        'quantity': quantity,
        'unit': unit,            //----------> Update it to this --> unit,
        'userId': userId
      };

      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(transferData),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        final errorMessage = jsonDecode(response.body)['message'] ?? 'Unknown error';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Transfer failed: $errorMessage', style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),),
            backgroundColor: const Color(0xFFD95326),
          ),
        );
        return;
      }
    }

    fetchkitchenInventory();
    fetchMainInventory();

    // Clear quantity text fields
    quantityControllers.forEach((key, controller) {
      controller.clear();
    });

    // Reset dropdown unit selections
    rowUnits.updateAll((key, value) => null);

    // Unselect all items
    selectedItems.updateAll((key, value) => false);

    // Refresh UI
    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All items transferred successfully!')),
    );

  } catch (e) {
    await Future.delayed(const Duration(seconds: 4));
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error: $e')),
    );
  }
}

  void _handleTransferPressed(BuildContext context) {
  List<String> selectedItemNames = [];
  selectedItems.forEach((itemName, isSelected) {
    if (isSelected) {
      selectedItemNames.add(itemName);
    }
  });

  if (selectedItemNames.isNotEmpty) {
    String selectedDetails = selectedItemNames.map((itemName) {
      String qty = quantityControllers[itemName]?.text ?? 'N/A';
      String? unit = rowUnits[itemName] ?? 'N/A';
      String itemId = selectedItemIds[itemName] ?? 'Unknown ID';
      return "$itemName: $qty $unit";
    }).join("\n\n");

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Transfer Items"),
        content: Text("You selected:\n\n$selectedDetails"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              List<Map<String, dynamic>> itemsToTransfer = [];

              for (var itemName in selectedItemNames) {
                String qtyText = quantityControllers[itemName]?.text ?? '0';
                double quantity = double.tryParse(qtyText) ?? 0.0;
                String unit = rowUnits[itemName] ?? 'kg'; // default if not found
                String itemId = selectedItemIds[itemName] ?? '';

                if (itemId.isNotEmpty && quantity > 0) {
                  itemsToTransfer.add({
                    'id': itemId,
                    'quantity': quantity,
                    'unit': unit,
                  });
                }
              }

    Navigator.pop(context); // Close the dialog first
    transferItems(itemsToTransfer); // Then call the API
  },
  child: Text("Confirm Transfer"),
),
        ],
      ),
    );
  } else {
    print("No items selected.");
  }
}




// Filter vendors based on search query
  void filterKitchen(String query) {
    final lowerQuery = query.toLowerCase();
    List<dynamic> filteredItems =
        kitchenInventoryItems.where((kitchen) {
          final name = kitchen["inventory"]["itemName"]?.toString().toLowerCase() ?? '';
          return name.contains(lowerQuery) ;
        }).toList();

    setState(() {
      filteredKitchen = filteredItems;
    });
  }

Widget buildBarcodeButton() {
  return ElevatedButton.icon(
    onPressed: () async {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => BarcodeTransferScreen()),
      );
      await fetchkitchenInventory();
      await fetchMainInventory();
    },
    style: ElevatedButton.styleFrom(
      backgroundColor: Color(0xFFD95326),
      elevation: 0,
      padding: const EdgeInsets.symmetric(vertical: 20),
      minimumSize: const Size.fromHeight(60),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    icon: Icon(LucideIcons.scanLine, color: Colors.white, size: 18),
    label: Text(
      'Barcode Scanner',
      style: GoogleFonts.poppins(
        color: Colors.white,
        fontSize: 13,
      ),
    ),
  );
}



Widget buildAddButton() {
  return ElevatedButton.icon(
    onPressed: () {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => TransferHistoryPage()),
      );
    },
    style: ElevatedButton.styleFrom(
      backgroundColor: Color(0xFFD95326),
      elevation: 0,
      padding: const EdgeInsets.symmetric(vertical: 20),
      minimumSize: const Size.fromHeight(60),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    icon: Icon(LucideIcons.clock, color: Colors.white, size: 18),
    label: Text(
      'Transfer History',
      style: GoogleFonts.poppins(
        color: Colors.white,
        fontSize: 13,
      ),
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
      iconTheme: const IconThemeData(color: Colors.black),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Text(
            'Kitchen Inventory',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Manage your food kitchen inventory',
            style: GoogleFonts.poppins(
              fontSize: 10.2,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    ),
    body: isInventoryLoading || iskitchenLoading
        ? Center(
            child: LoadingAnimationWidget.staggeredDotsWave(
              color: Colors.black,
              size: 40,
            ),
          )
        : hasInventoryErrorOccurred || haskitchenErrorOccurred
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.alertTriangle,
                      size: 60,
                      color: Color(0xFFEF4444),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "Something went wrong",
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Please check your connection or try again.",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          isInventoryLoading = true;
                          iskitchenLoading = true;
                          hasInventoryErrorOccurred = false;
                          haskitchenErrorOccurred = false;
                        });
                        fetchkitchenInventory();
                        fetchMainInventory();
                      },
                      icon: const Icon(
                        LucideIcons.refreshCw,
                        size: 20,
                        color: Colors.white,
                      ),
                      label: Text(
                        "Retry",
                        style: GoogleFonts.poppins(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
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
            : SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: kIsWeb
                            ? const EdgeInsets.symmetric(horizontal: 40)
                            : EdgeInsets.zero,
                        child: kIsWeb
                          ? Row(
                              children: [
                                Expanded(child: buildAddButton()),
                                const SizedBox(width: 12),
                                Expanded(child: buildBarcodeButton()),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                buildAddButton(),
                                const SizedBox(height: 12),
                                buildBarcodeButton(),
                              ],
                            ),
                      ),
                      const SizedBox(height: 7),
                      InventoryStatusCard(
                        kitchenCount: kitchenInventoryItems.length,
                        mainCount: mainInventoryItems.length,
                      ),
                      const SizedBox(height: 20),
                      TransferItemsCard(
                        selectedTab: selectedTab,
                        onTransferPressed: () {
                          _handleTransferPressed(context);
                        },
                      ),
                      const SizedBox(height: 20),
                      InventoryListContainer(
                        selectedTab: selectedTab,
                        searchQuery: searchQuery,
                        onTabChange: updateSelectedTab,
                        kitchenInventory: kitchenInventoryItems,
                        mainInventory: mainInventoryItems,
                        selectedItems: selectedItems,
                        selectedItemIds: selectedItemIds,
                        quantityControllers: quantityControllers,
                        rowUnits: rowUnits,
                        onSelectionChanged: (items) {
                          setState(() {
                            selectedItems = items;
                          });
                        },
                        onUnitChanged: (units) {
                          setState(() {
                            rowUnits = units;
                          });
                        },
                        onSearchChanged: (query) {
                          setState(() {
                            searchQuery = query;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
  );
}
}

class InventoryListContainer extends StatefulWidget {
  final Function(String) onTabChange;
  final String selectedTab;
  final List<dynamic> kitchenInventory;
  final List<dynamic> mainInventory;
  final Map<String, bool> selectedItems;
  final Map<String, String> selectedItemIds ;
  final Map<String, TextEditingController> quantityControllers;
  final Map<String, String?> rowUnits;
  final Function(Map<String, bool>) onSelectionChanged;
  final Function(Map<String, String?>) onUnitChanged;
  final String searchQuery;
  final Function(String) onSearchChanged;

  const InventoryListContainer({
  super.key,
  required this.searchQuery,
  required this.selectedTab,
  required this.onTabChange,
  required this.kitchenInventory,
  required this.mainInventory,
  required this.quantityControllers,
  required this.rowUnits,
  required this.onUnitChanged,
  required this.onSelectionChanged,
  required this.selectedItems,
  required this.selectedItemIds,
  required this.onSearchChanged, // <-- add this
});


  @override
  _InventoryListContainerState createState() => _InventoryListContainerState();
}

class _InventoryListContainerState extends State<InventoryListContainer> {
  Map<String, TextEditingController> quantityControllers = {};
  
  List<Map<String, String>> get currentInventory {
    final source = widget.selectedTab == "Kitchen"
    ? widget.kitchenInventory
    : widget.mainInventory;

final lowerQuery = widget.searchQuery.toLowerCase();

final filteredSource = source.where((item) {
  final itemName = widget.selectedTab == "Kitchen"
      ? item["inventory"]["itemName"]?.toString().toLowerCase() ?? ''
      : item["itemName"]?.toString().toLowerCase() ?? '';
  return itemName.contains(lowerQuery);
}).toList();

    return filteredSource.map<Map<String, String>>((item) {
      if (widget.selectedTab == "Kitchen") {
        return {
          "item": item["inventory"]["itemName"]?.toString() ?? '',
          "quantity": item["quantity"]?.toString() ?? '0',
          "unit": item["unit"]?.toString() ?? '',
        };
      } else {
        return {
          "item": item["itemName"]?.toString() ?? '',
          "quantity": item["quantity"]?.toString() ?? '0',
          "unit": item["unit"]?.toString() ?? '',
          "id" : item['id']?.toString() ?? '0',
        };
      }
    }).toList();
  }

  void _handleTabChange(String tab) {
    widget.onTabChange(tab);
    setState(() {
      widget.selectedItems.clear(); // Clear previous selection when tab changes
      quantityControllers.clear();
    });
  }

    Future<void> downloadKitchenInventoryFile(BuildContext context) async {
    final url = Uri.parse(
      '${dotenv.env['API_URL']}/kitchen-inventory/download',
    );

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

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;

        final dir = await getExternalStorageDirectory();
        final downloadsDir = Directory("${dir!.path}/downloads");

        if (!downloadsDir.existsSync()) {
          downloadsDir.createSync(recursive: true);
        }

        final filePath = '${downloadsDir.path}/Kitchen-Inventory.xlsx';
        final file = File(filePath);
        await file.writeAsBytes(bytes);

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Downloaded to: $filePath")));

        OpenFile.open(filePath);
      } else {
        final errorMessage = jsonDecode(response.body)['message'] ?? 'Unknown error';
        throw Exception('Failed to download. Status: $errorMessage');
      }
    } catch (e) {
      print("Error: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Download failed: $e")));
    }
  }

  // Build the button below the search bar
  Widget buildKitchenInventoryDownloadButton() {
    return Center(
      child: SizedBox(
        width:MediaQuery.of(context).size.width * 0.7,
        height:70,
        
        child: SizedBox(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12,), 
            child: ElevatedButton(
              onPressed: () {
                downloadKitchenInventoryFile(context);
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
                  Icon(LucideIcons.download, color: Colors.black, size: 14,),
                  SizedBox(width: 8),
                  Text(
                    'Download Kitchen List',
                    style: GoogleFonts.poppins(color: Colors.black, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }


  Future<void> downloadInventoryFile(BuildContext context) async {
    final url = Uri.parse(
      '${dotenv.env['API_URL']}/inventory/download',
    );

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

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;

        final dir = await getExternalStorageDirectory();
        final downloadsDir = Directory("${dir!.path}/downloads");

        if (!downloadsDir.existsSync()) {
          downloadsDir.createSync(recursive: true);
        }

        final filePath = '${downloadsDir.path}/Inventory.xlsx';
        final file = File(filePath);
        await file.writeAsBytes(bytes);

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Downloaded to: $filePath")));

        OpenFile.open(filePath);
      } else {
        final errorMessage = jsonDecode(response.body)['message'] ?? 'Unknown error';
        throw Exception('Failed to download. Status: $errorMessage');
      }
    } catch (e) {
      print("Error: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Download failed: $e")));
    }
  }

  // Build the button below the search bar downloadInventoryFile(context);
  Widget buildInventoryDownloadButton() {
    return Center(
      child: SizedBox(
        width:MediaQuery.of(context).size.width * 0.6,
        height:70,
        child: Padding(
          padding: const EdgeInsets.only(
            bottom: 12,
          ), // Remove top margin, keep bottom padding
          child: ElevatedButton(
            onPressed: () {
              downloadInventoryFile(context);
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
                Icon(LucideIcons.download, color: Colors.black, size: 14,),
                SizedBox(width: 8),
                Text(
                  'Download Inventory List',
                  style: GoogleFonts.poppins(color: Colors.black, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width:MediaQuery.of(context).size.width * 0.92, 
        child: Card(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: const Color(0xFFE5E5E5)),
          ),
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Inventory List",
                  style: GoogleFonts.poppins(
                    fontSize: 15.2,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1C1917),
                  ),
                ),
                SizedBox(height: 16),
        
                // Tab Switcher
                Row(
                  children: [
                    _buildTab("Kitchen"),
                    SizedBox(width: 12),
                    _buildTab("Main Storage"),
                  ],
                ),
        
                SizedBox(height: 12),
        
                // Search Bar
                SizedBox(
                  width:MediaQuery.of(context).size.width * 0.79, 
                  // height: MediaQuery.of(context).size.width * 0.14,
                  height: 48,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: "Search items...",
                      prefixIcon: Icon(Icons.search, color: Color(0xFF1C1917)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8F5F2),
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
                    onChanged: widget.onSearchChanged,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.black, // Updated text color for visibility
                    ),
                  ),
                ),
        
                SizedBox(height: 26),
        
                // Inventory Table
                Table(
                  columnWidths: {
                    if (widget.selectedTab == "Main Storage")
                      0: FlexColumnWidth(0.7), //Checkbox
                    1: FlexColumnWidth(1.2), // Item
                    2: FlexColumnWidth(1), // Quantity
                    3: FlexColumnWidth(1), // Unit
                    if (widget.selectedTab == "Main Storage")
                      4: FlexColumnWidth(1), // Input box
                    if (widget.selectedTab == "Main Storage")
                      5: FlexColumnWidth(1), // Input box
                  },
                  border: TableBorder(
                    horizontalInside: BorderSide(
                      width: 1,
                      color: Colors.grey.shade300,
                    ),
                  ),
                  children: [
                    _buildTableHeader(),
                    ...currentInventory.map((item) => _buildTableRow(item)),
                  ],
                ),
                const SizedBox(height: 40),
                  if (widget.selectedTab == "Kitchen")
                  buildKitchenInventoryDownloadButton(),
        
                  if (widget.selectedTab == "Main Storage")
                  buildInventoryDownloadButton(),
                
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTab(String name) {
    bool isActive = widget.selectedTab == name;
    return GestureDetector(
      onTap: () {
        widget.onTabChange(name);
      },
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        decoration: BoxDecoration(
          color: isActive ? Color(0xFFD95326) : Colors.grey[300],
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          name,
          style: GoogleFonts.poppins(
            color: isActive ? Colors.white : Colors.black,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  TableRow _buildTableHeader() {
    return TableRow(
      decoration: BoxDecoration(color: Colors.grey[200]),
      children: [
        if (widget.selectedTab == "Main Storage")
          Padding(
            padding: EdgeInsets.only(left: 10.0, top: 8.0),
            child: Text(
              "#",
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600,  fontSize: 10),
            ),
          ),
        Padding(
          padding: EdgeInsets.only(left: 10.0, top: 8.0),
          child: Text(
            "Item",
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600,  fontSize: 10),
          ),
        ),
        Container(
          margin: EdgeInsets.only(
            top: 8.0,
            left: 18.0,
            bottom: 8.0,
          ), // Set margin here
          child: Padding(
            padding: EdgeInsets.only(
              top: 0.0,
              bottom: 0,
            ), // Padding remains inside the widget
            child: Text(
              "Qty",
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600,  fontSize: 10),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: 8.0, left: 5),
          child: Text(
            "Unit",
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600,  fontSize: 10),
          ),
        ),
        if (widget.selectedTab == "Main Storage")
          Padding(
            padding: EdgeInsets.only(top: 8.0, bottom: 8.0, left: 5),
            child: Text(
              "Enter-",
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600,  fontSize: 9.6),
            ),
          ),
        if (widget.selectedTab == "Main Storage")
          Padding(
            padding: EdgeInsets.only(top: 8.0, bottom: 8.0, right: 10, left: 0),
            child: Text(
              "Value",
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600,  fontSize: 9.6),
            ),
          ),
      ],
    );
  }

  Widget buildDropdown(BuildContext context, String itemName) {
    return GestureDetector(
      onTap:
          () => showDialog(
            context: context,
            builder:
                (_) => Center(
                  child: Material(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 200,
                      padding: EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ...[
                            'Kg',
                            'Liter',
                            'Unit',
                          ].map(
                            (unit) => ListTile(
                              title: Text(
                                unit,
                                style: GoogleFonts.poppins(fontSize: 12),
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                setState(() {
                                  widget.rowUnits[itemName] = unit;
                                  widget.onUnitChanged(widget.rowUnits);
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          ),
      child: Container(
        width: 80,
        height: 28,
        padding: EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.centerLeft,
        child: Text(
          widget.rowUnits[itemName] ?? 'Unit',
          style: GoogleFonts.poppins(fontSize: 13),
        ),
      ),
    );
  }

  TableRow _buildTableRow(Map<String, String> item) {
    String itemName = item["item"]!;
    bool isSelected = widget.selectedItems[itemName] ?? false;
    TextEditingController controller =
        widget.quantityControllers[itemName] ?? TextEditingController();
    if (!widget.quantityControllers.containsKey(itemName)) {
      widget.quantityControllers[itemName] = controller;
    }
    return TableRow(
      children: [
        if (widget.selectedTab == "Main Storage")
          Padding(
            padding: EdgeInsets.only(right: 10),
            child: Checkbox(
              value: isSelected,
              onChanged: (bool? value) {
                setState(() {
                  final updated = Map<String, bool>.from(widget.selectedItems);
                  updated[itemName] = value ?? false;
                  widget.onSelectionChanged(updated);

                  if (value == true) {
                widget.quantityControllers[itemName] = TextEditingController();
                widget.selectedItemIds[itemName] = item["id"] ?? 'Unknown';
              } else {
                widget.quantityControllers.remove(itemName);
                widget.selectedItemIds.remove(itemName);
              }
                });
              },
            ),
          ),

        Padding(
          padding: EdgeInsets.only(top: 12.0, left: 5.0, bottom: 12),
          child: Text(itemName, style: GoogleFonts.poppins(fontSize: 11),),
        ),

        Padding(
          padding: EdgeInsets.only(top: 12.0, left: 16),
          child: Text(item["quantity"]!, style: GoogleFonts.poppins( fontSize: 11),),
        ),
        Padding(
          padding: EdgeInsets.only(top: 12.0, left: 6),
          child: Text(item["unit"]!, style: GoogleFonts.poppins( fontSize: 11),),
        ),
        if (widget.selectedTab == "Main Storage")
          Padding(
            padding: EdgeInsets.only(bottom: 10.0, right: 6),
            child:
                isSelected
                    ? Container(
                      margin: EdgeInsets.only(top: 8, right: 0),
                      child: SizedBox(
                        width: 90,
                        height: 30,
                        child: TextField(
                          controller: controller,
                          decoration: InputDecoration(
                            hintText: "Qty",
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 4,
                            ),
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(fontSize: 12),
                        ),
                      ),
                    )
                    : SizedBox(),
          ),
        if (widget.selectedTab == "Main Storage")
          Padding(
            padding: EdgeInsets.only(bottom: 10.0, right: 8),
            child:
                isSelected
                    ? Container(
                      margin: EdgeInsets.only(top: 8),
                      child: buildDropdown(context, itemName),
                    )
                    : SizedBox(),
          ),
      ],
    );
    
  }
}

class InventoryStatusCard extends StatelessWidget {
  final int kitchenCount;
  final int mainCount;

  const InventoryStatusCard({
    super.key,
    required this.kitchenCount,
    required this.mainCount,
  });

  @override
  Widget build(BuildContext context) {
    final int totalCount = kitchenCount + mainCount;

    return Center(
      child: SizedBox(
        width:MediaQuery.of(context).size.width * 0.92, 
        child: Card(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: const Color(0xFFE5E5E5)),
          ),
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.only(
              top: 16,
              left: 24,
              bottom: 20,
              right: 30,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Inventory Status",
                  style: GoogleFonts.poppins(
                    fontSize: 15.2,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1C1917),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  "Current inventory levels across locations",
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF78726D),
                  ),
                ),
                SizedBox(height: 20),
        
                Padding(
                  padding: const EdgeInsets.only(left: 5.0, right: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        totalCount <= 9 ? "0$totalCount" : "$totalCount",
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1C1917),
                        ),
                      ),
                      Text(
                        "Total Inventory Items",
                        style: GoogleFonts.poppins(
                          fontSize: 11.4,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF78726D),
                        ),
                      ),
                    ],
                  ),
                ),
        
                SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    _inventoryItem("Kitchen", "$kitchenCount"),
                    SizedBox(width: 20),
                    _inventoryItem("Main Storage", "$mainCount"),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _inventoryItem(String location, String countStr) {
    final int count = int.tryParse(countStr) ?? 0;

    return Container(
      width: 127,
      height: 90,
      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Text(
            location,
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: Color(0xFF78726D),
            ),
          ),
          SizedBox(height: 8),
          Text(
            '$count ${count <= 1 ? "item" : "items"}',
            style: GoogleFonts.poppins(
              fontSize: 11.7,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1C1917),
            ),
          ),
        ],
      ),
    );
  }
}

class TransferItemsCard extends StatelessWidget {
  final String selectedTab;
  final VoidCallback onTransferPressed;

  const TransferItemsCard({
    super.key,
    required this.selectedTab,
    required this.onTransferPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width:MediaQuery.of(context).size.width * 0.92, 
        child: Card(
          color: Colors.white, // Set background color to white
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: const Color(0xFFE5E5E5)), // Add black border
          ),
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Transfer Items",
                  style: GoogleFonts.poppins(
                    fontSize: 15.2,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1C1917),
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  "Move items from main to kitchen inventory",
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF78726D),
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  "Select items from the main inventory tab and specify quantities to transfer them to the kitchen.",
                  style: GoogleFonts.poppins(
                    fontSize: 11.4,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF1C1917),
                  ),
                ),
                SizedBox(height: 20),
                SizedBox(
                  height: 48,
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed:
                        selectedTab == "Main Storage" ? onTransferPressed : null,
                    icon: Icon(Icons.arrow_downward),
                    label: Text("Transfer to Kitchen", 
                        style: GoogleFonts.poppins(
                        fontSize: 11.2,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF1C1917),
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFD95326),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
