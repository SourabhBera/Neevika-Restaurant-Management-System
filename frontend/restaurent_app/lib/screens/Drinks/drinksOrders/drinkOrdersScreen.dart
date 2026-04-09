import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:Neevika/widgets/sidebar.dart';
import 'package:another_flushbar/flushbar.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'usb_printer.dart';

void showTopNotification(BuildContext context, String title, String body) {
  Flushbar(
    title: title,
    message: body,
    duration: const Duration(seconds: 3),
    flushbarPosition: FlushbarPosition.TOP,
    backgroundColor: Colors.green,
    margin: const EdgeInsets.all(8),
    borderRadius: BorderRadius.circular(8),
    icon: const Icon(Icons.notifications, color: Colors.white),
  ).show(context);
}

class ViewDrinkOrdersScreen extends StatefulWidget {
  const ViewDrinkOrdersScreen({super.key});

  @override
  _ViewDrinkOrdersScreenState createState() => _ViewDrinkOrdersScreenState();
}

class _ViewDrinkOrdersScreenState extends State<ViewDrinkOrdersScreen> {
  String selectedCategory = "All";
  List<String> categories = ["All", "Pending", "Accepted", "Completed"];
  TextEditingController searchController = TextEditingController();
  List<Map<String, dynamic>> orders = [];
  bool isLoading = true;
  bool hasErrorOccurred = false;
  String userRole = '';
  IO.Socket? socket;

  // Printing state
  final PrinterManager printerManager = PrinterManager.instance;
  List<PrinterDevice> availablePrinters = [];
  PrinterDevice? selectedPrinter; // will be auto-selected
  bool isScanning = false;
  bool isPrinting = false;
  List<String> debugLogs = [];
  final ScrollController _logScrollController = ScrollController();

  // Caches to resolve names when socket payload contains only IDs
  final Map<String, String> userCache = {}; // userId -> userName
  final Map<String, String> sectionCache = {}; // sectionId -> sectionName
  final Set<int> printedKOTs = {};

  bool _isKotDialogOpen = false;
  String? _shiftFromText;
  String? _shiftToText;
  List<String> _shiftedItemNames = [];
  final Map<String, Map<String, dynamic>> _shiftMetadataCache = {};



  @override
  void initState() {
    super.initState();
    tzdata.initializeTimeZones();
    _addDebugLog('Init: scanning printers and connecting socket...');
    _scanForPrinters(); // auto-scan and auto-select first printer
    connectToSocket();
    fetchOrders();
  }

  // ----------------- Logging -----------------
void _addDebugLog(String message) {
  final ts = DateFormat('HH:mm:ss').format(DateTime.now());
  final entry = '$ts: $message';
  debugPrint(entry); // Always print immediately
  
  // Defer setState to avoid calling it during build
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) {
      setState(() => debugLogs.add(entry));
      
      // Scroll to bottom after state update
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    }
  });
}

  void _clearDebugLogs() => setState(() => debugLogs.clear());

  // ----------------- Printer discovery -----------------
  Future<void> _scanForPrinters() async {
    try {
      setState(() => isScanning = true);
      _addDebugLog('Starting USB discovery (plugin)...');

      await [Permission.storage, Permission.photos].request();
      _addDebugLog('Requested permissions');

      availablePrinters.clear();
      selectedPrinter = null;

      Stream<PrinterDevice> stream = printerManager.discovery(
        type: PrinterType.usb,
      );
      final sub = stream.listen(
        (printer) {
          _addDebugLog(
            'Found device: ${printer.name} | VID:${printer.vendorId} PID:${printer.productId}',
          );
          availablePrinters.add(printer);
          if (selectedPrinter == null) {
            selectedPrinter = printer;
            _addDebugLog(
              'Auto-selected printer: ${printer.name} (VID:${printer.vendorId} PID:${printer.productId})',
            );
            showTopNotification(
              context,
              'Printer selected',
              '${printer.name} selected for printing',
            );
          }
          setState(() {});
        },
        onError: (e) {
          _addDebugLog('Discovery error: $e');
        },
      );

      await Future.delayed(const Duration(seconds: 2));
      await sub.cancel();

      if (availablePrinters.isEmpty) {
        _addDebugLog('No USB printers found after scan');
        showTopNotification(
          context,
          'Scan',
          'No USB printers found — connect the printer and tap Scan',
        );
      } else {
        _addDebugLog(
          'Discovery finished: ${availablePrinters.length} device(s) found',
        );
      }
    } catch (e) {
      _addDebugLog('Scan exception: $e');
    } finally {
      setState(() => isScanning = false);
    }
  }

  // Utility to coerce ID types to int
  int _intFromDynamic(dynamic v) {
    if (v == null) throw Exception('Null id');
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? int.parse(v);
    if (v is num) return v.toInt();
    throw Exception('Unsupported id type ${v.runtimeType}');
  }

  String _normalizeStatus(dynamic rawStatus) {
    final s = rawStatus?.toString().trim() ?? '';
    if (s.isEmpty) return '';
    final lower = s.toLowerCase();
    return '${lower[0].toUpperCase()}${lower.substring(1)}';
  }


void connectToSocket() {
  socket = IO.io(dotenv.env['API_URL_1'] ?? 'http://13.60.15.89:3000', <String, dynamic>{
    'transports': ['websocket'],
    'autoConnect': true,
  });

  socket!.on('connect', (_) {
    _addDebugLog('\n🆕 Connected to socket\n');
  });

    socket!.on('new_drinks_order', (data) {
      print("🆕 New order received: ${jsonEncode(data)}");

      try {
        final order = (data['order'] as Map<String, dynamic>?) ?? <String, dynamic>{};
        final items = (data['items'] as List<dynamic>?) ?? [];
        final topLevelKotNumber = data['kotNumber']; // Extract top-level kotNumber

        List<Map<String, dynamic>> itemEntries = [];

        for (var item in items) {
          if (item is! Map<String, dynamic>) continue;
          final itemData = item;

          // Extract orderItem
          final orderItem =
              (itemData['orderItem'] is Map<String, dynamic>)
                  ? itemData['orderItem'] as Map<String, dynamic>
                  : (itemData['order_item'] is Map<String, dynamic>)
                      ? itemData['order_item'] as Map<String, dynamic>
                      : <String, dynamic>{};

          // Extract menu info (drinks-specific)
          final menuMap =
              (itemData['drinkMenu'] is Map<String, dynamic>)
                  ? itemData['drinkMenu'] as Map<String, dynamic>
                  : (itemData['menuItem'] is Map<String, dynamic>)
                      ? itemData['menuItem'] as Map<String, dynamic>
                      : (itemData['drink'] is Map<String, dynamic>)
                          ? itemData['drink'] as Map<String, dynamic>
                          : (itemData['menu'] is Map<String, dynamic>)
                              ? itemData['menu'] as Map<String, dynamic>
                              : <String, dynamic>{};

          final nameCandidate =
              menuMap['name'] ??
              menuMap['title'] ??
              orderItem['desc'] ??
              itemData['name'] ??
              itemData['friendlyName'] ??
              '';

          // Extract quantity
          String quantityStr = '1';
          final q = orderItem['quantity'] ?? itemData['quantity'] ?? '1';
          if (q is int)
            quantityStr = q.toString();
          else if (q is String)
            quantityStr = q;
          else if (q is num) quantityStr = q.toInt().toString();

          // Extract price
          String priceStr = '0';
          final p = orderItem['price'] ?? itemData['price'] ?? 0;
          if (p is int)
            priceStr = p.toString();
          else if (p is String)
            priceStr = p;
          else if (p is double) priceStr = p.toInt().toString();

          // Extract description
          final desc =
              (orderItem['desc'] ??
                      itemData['desc'] ??
                      menuMap['desc'] ??
                      menuMap['description'] ??
                      '')
                  .toString();

          // KOT number extraction - prioritize item-level, then top-level
          final kotNumFromItem = (() {
            try {
              // First try item-level kotNumber
              final itemKot = orderItem['kotNumber'] ?? itemData['kotNumber'];
              if (itemKot != null) {
                if (itemKot is int) return itemKot;
                return int.tryParse(itemKot.toString()) ?? 0;
              }
              
              // Fallback to top-level kotNumber
              if (topLevelKotNumber != null) {
                if (topLevelKotNumber is int) return topLevelKotNumber;
                return int.tryParse(topLevelKotNumber.toString()) ?? 0;
              }
              
              return 0;
            } catch (_) {
              return 0;
            }
          })();

          final Map<String, dynamic> itemEntry = <String, dynamic>{
            "item_name": nameCandidate?.toString() ?? '',
            "quantity": quantityStr,
            "price": priceStr,
            "item_desc": desc,
            "orderItem": orderItem,
            "menu": menuMap,
            "kotNumber": kotNumFromItem,
            "order_item_id": orderItem['id']?.toString() ?? itemData['id']?.toString(),
          };

          itemEntries.add(itemEntry);
        }

        // Compute total amount
        int totalAmount = 0;
        for (var it in itemEntries) {
          final priceStr = (it['price'] ?? '0').toString();
          final qtyStr = (it['quantity'] ?? '1').toString();
          final price = int.tryParse(priceStr) ?? 0;
          final qty = int.tryParse(qtyStr) ?? 1;
          totalAmount += (price * qty);
        }

        final restTable =
            order['restaurant_table_number'] ??
            order['restaurent_table_number'] ??
            order['table_number'] ??
            '';

        // Use top-level kotNumber as the main kotNumber for the order
        final mainKotNumber = (() {
          try {
            if (topLevelKotNumber != null) {
              if (topLevelKotNumber is int) return topLevelKotNumber;
              return int.tryParse(topLevelKotNumber.toString()) ?? 0;
            }
            // Fallback to first item's kotNumber
            if (itemEntries.isNotEmpty) {
              return itemEntries.first['kotNumber'] ?? 0;
            }
            return 0;
          } catch (_) {
            return 0;
          }
        })();

        final Map<String, dynamic> newOrderEntry = <String, dynamic>{
          "id": order['id']?.toString() ?? '',
          "kotNumber": mainKotNumber, // Main KOT number for grouping
          "serverId":
              order['user']?['id']?.toString() ??
              order['userId']?.toString() ??
              '',
          "table_number": order['table_number']?.toString() ?? '',
          "amount": totalAmount.toString(),
          "quantity":
              itemEntries.fold<int>(
                0,
                (acc, e) =>
                    acc +
                    (int.tryParse(e['quantity']?.toString() ?? '0') ?? 0),
              ).toString(),
          "item_desc":
              itemEntries.isNotEmpty ? itemEntries[0]['item_desc'] ?? '' : '',
          "restaurent_table_number": restTable?.toString() ?? 'N/A',
          "server":
              order['user']?['name']?.toString() ??
              order['server']?.toString() ??
              'Unknown',
          "time": DateFormat('hh:mm a').format(DateTime.now()),
          "section_name":
              order['section']?['name']?.toString() ??
              order['section_name']?.toString() ??
              'Unknown',
          "item_name":
              (itemEntries.isNotEmpty &&
                      (itemEntries[0]['item_name']?.toString().isNotEmpty ?? false))
                  ? itemEntries[0]['item_name'].toString()
                  : (itemEntries.isNotEmpty
                      ? (itemEntries[0]['item_desc']?.toString() ?? '')
                      : 'Unknown Item'),
          "status": "Pending",
          "items": itemEntries,
        };

        // FIXED: Find existing order by kotNumber for proper grouping
        final existingOrderIndex = orders.indexWhere(
          (existingOrder) {
            final orderKotNumber = _extractKotNumberAsInt(existingOrder);
            return orderKotNumber != 0 && orderKotNumber == mainKotNumber;
          }
        );

        setState(() {
          if (existingOrderIndex >= 0 && mainKotNumber != 0) {
            // Merge with existing order with same kotNumber
            final existingOrder = orders[existingOrderIndex];
            
            // Combine items - ensure each item has kotNumber
            final existingItems = List<Map<String, dynamic>>.from(existingOrder['items'] ?? []);
            for (var newItem in itemEntries) {
              newItem['kotNumber'] = mainKotNumber; // Ensure kotNumber is set
              existingItems.add(newItem);
            }
            
            // Update totals
            final existingAmount = int.tryParse(existingOrder['amount']?.toString() ?? '0') ?? 0;
            final existingQuantity = int.tryParse(existingOrder['quantity']?.toString() ?? '0') ?? 0;
            
            final newTotalAmount = existingAmount + totalAmount;
            final newTotalQuantity = existingQuantity + (int.tryParse(newOrderEntry['quantity'].toString()) ?? 0);
            
            // Create summary item name
            final itemNameSummary = _createItemNameSummary(existingItems);
            
            // Update the existing order
            orders[existingOrderIndex] = {
              ...existingOrder,
              'items': existingItems,
              'amount': newTotalAmount.toString(),
              'quantity': newTotalQuantity.toString(),
              'item_name': itemNameSummary,
              'kotNumber': mainKotNumber, // Ensure kotNumber is maintained
            };
            
            print("✅ Merged order with existing KOT ${mainKotNumber}: ${existingOrder['id']}");
          } else {
            // Add as new order - ensure kotNumber is set
            newOrderEntry['kotNumber'] = mainKotNumber;
            orders.insert(0, newOrderEntry);
            print("✅ Added new order with KOT ${mainKotNumber}: ${newOrderEntry['id']}");
          }
        });

        // ✅ AUTO-PRINT AND ACCEPT NEW ORDERS
        final kotNo = mainKotNumber.toString();

        if (printedKOTs.contains(mainKotNumber)) {
          _addDebugLog('Skipping auto-print for drinks KOT $kotNo - already printed');
        } else {
          Future.delayed(const Duration(seconds: 2), () {
            if (!printedKOTs.contains(mainKotNumber)) {
              _addDebugLog('Auto-printing drinks order $kotNo after delay');
              printedKOTs.add(mainKotNumber);
              
              // Find the order we just added
              final orderIndex = orders.indexWhere((o) => 
                _extractKotNumberAsInt(o) == mainKotNumber
              );
              
              if (orderIndex >= 0) {
                final orderToPrint = orders[orderIndex];
                
                _printOrderNative(orderToPrint).then((_) {
                  // ✅ AFTER SUCCESSFUL PRINT, UPDATE STATUS TO ACCEPTED
                  _addDebugLog('Auto-print successful for drinks KOT $kotNo - updating status to Accepted');
                  
                  // Update local UI
                  if (mounted) {
                    setState(() {
                      orders[orderIndex]['status'] = 'Accepted';
                    });
                  }
                  
                  // Update backend
                  _acceptOrder(kotNo, orderToPrint);
                  
                }).catchError((e) {
                  _addDebugLog('Auto-print error for drinks: $e');
                  printedKOTs.remove(mainKotNumber);
                });
              }
            } else {
              _addDebugLog('Cancelled auto-print for drinks KOT $kotNo - was printed elsewhere');
            }
          });
        }

      } catch (e, st) {
        print("❌ Error handling new_drinks_order payload: $e");
        print("STACK: $st");
        _addDebugLog("Socket error: $e");
      }
    });



socket!.on('transfer_table', (data) {
  try {
    final payload = Map<String, dynamic>.from(data);

    final dynamic fromTableRaw = payload['fromTable'];
    final dynamic toTableRaw   = payload['toTable'];

    if (fromTableRaw == null || toTableRaw == null) return;

    final fromTable = Map<String, dynamic>.from(fromTableRaw as Map);
    final toTable   = Map<String, dynamic>.from(toTableRaw as Map);

    final String fromTableDbId     = fromTable['id']?.toString() ?? '';
    final String toTableDbId       = toTable['id']?.toString() ?? '';
    final String toDisplayNumber   = toTable['display_number']?.toString() ?? '';
    final String fromDisplayNumber = fromTable['display_number']?.toString() ?? '';
    final String fromSectionName   = fromTable['section_name']?.toString() ?? '';

    final String shiftedFromLabel = fromSectionName.isNotEmpty
        ? '$fromSectionName Table $fromDisplayNumber'
        : 'Table $fromDisplayNumber';

    if (mounted) {
      setState(() {
        for (int i = 0; i < orders.length; i++) {
          final order = Map<String, dynamic>.from(orders[i]);

          final String orderTableNum    = order['table_number']?.toString() ?? '';
          final String orderDisplayNum1 = order['restaurent_table_number']?.toString() ?? '';
          final String orderDisplayNum2 = order['restaurant_table_number']?.toString() ?? '';

          final bool matchesDb       = fromTableDbId.isNotEmpty && orderTableNum == fromTableDbId;
          final bool matchesDisplay1 = fromDisplayNumber.isNotEmpty && orderDisplayNum1 == fromDisplayNumber;
          final bool matchesDisplay2 = fromDisplayNumber.isNotEmpty && orderDisplayNum2 == fromDisplayNumber;

          if (!matchesDb && !matchesDisplay1 && !matchesDisplay2) continue;

          orders[i] = {
            ...order,
            'table_number'            : toTableDbId,
            'restaurent_table_number' : toDisplayNumber,
            'restaurant_table_number' : toDisplayNumber,
            'isShifted'               : true,
            'is_shifted'              : true,
            'shifted_from_table'      : shiftedFromLabel,
          };
        }
      });
    }

    if (mounted) {
      _shiftFromText    = shiftedFromLabel;
      _shiftToText      = 'Table $toDisplayNumber';
      _shiftedItemNames = [];
      _showKotShiftedPopup();
    }
  } catch (e, st) {
    _addDebugLog('❌ transfer_table error: $e');
    _addDebugLog('STACK: $st');
  }
});


  // Keep your existing delete handler
  socket!.on('delete_drinks_orders', (data) {
    _addDebugLog(
      "🗑️ order_deleted event (raw): ${data.runtimeType} -> ${data.toString()}",
    );
    try {
      String? deletedItemId;
      String? deletedOrderId;
      Map<String, dynamic>? payload;

      if (data is String) {
        try {
          final parsed = jsonDecode(data);
          if (parsed is Map)
            payload = Map<String, dynamic>.from(parsed);
          else
            deletedItemId = data.trim();
        } catch (_) {
          deletedItemId = data.trim();
        }
      } else if (data is Map) {
        payload = Map<String, dynamic>.from(data);
      } else if (data is int) {
        deletedItemId = data.toString();
      }

      if (payload != null) {
        deletedItemId =
            _extractId(payload, [
              'itemId',
              'item_id',
              'orderItemId',
              'order_item_id',
              'deletedItemId',
              'idToDelete',
              'id',
            ]) ??
            deletedItemId;

        deletedOrderId =
            _extractId(payload, ['orderId', 'order_id', 'order', 'id']) ??
            deletedOrderId;

        try {
              _handleDeleteEvent(payload);
            } catch (e) {
              _addDebugLog('Error calling _handleDeleteEvent: $e');
            }
      }

      if (deletedItemId?.trim().isEmpty ?? true) deletedItemId = null;
      if (deletedOrderId?.trim().isEmpty ?? true) deletedOrderId = null;

      _addDebugLog(
        "Extracted - ItemID: $deletedItemId, OrderID: $deletedOrderId",
      );

      if (deletedOrderId != null && deletedItemId == null) {
        _maybeRemoveEntireOrder(deletedOrderId, payload);
      } else if (deletedOrderId != null && deletedItemId != null) {
        _removeItemFromOrderById(orderId: deletedOrderId, itemId: deletedItemId);
      } else if (deletedItemId != null) {
        _removeItemFromAllOrders(deletedItemId);
      } else {
        _addDebugLog('order_deleted event missing both itemId and orderId; ignoring');
      }
    } catch (e, st) {
      _addDebugLog('Error in order_deleted handler: $e');
      _addDebugLog('STACK: $st');
    }
  });


socket!.on('drinks_order_shifted', (data) {
  try {
    final payload = Map<String, dynamic>.from(data);
    
    // Extract shift tracking data
    final String fromTableId = payload['fromTableId'].toString();
    final String toTableId = payload['toTableId'].toString();
    final String fromSectionName = payload['fromSectionName'].toString();
    final String toSectionName = payload['toSectionName'].toString();
    final List<dynamic> shiftedOrderIds = payload['orderIds'] ?? [];
    
    // Get shifted KOT number from backend
    final String shiftedKotNumber = payload['shiftedKotNumber']?.toString() ?? '';
    final String originalKotNumber = payload['originalKotNumber']?.toString() ?? '';
    
    _addDebugLog('🔄 Received drinks_order_shifted event:');
    _addDebugLog('   From: $fromSectionName - Table $fromTableId');
    _addDebugLog('   To: $toSectionName - Table $toTableId');
    _addDebugLog('   Original KOT: $originalKotNumber → Shifted KOT: $shiftedKotNumber');
    _addDebugLog('   Order IDs: ${shiftedOrderIds.join(", ")}');
    
    if (mounted) {
      setState(() {
        // Step 1: Find and collect items from original orders
        List<Map<String, dynamic>> shiftedItems = [];
        List<int> indicesToRemove = [];
        
        for (final rawId in shiftedOrderIds) {
          final orderId = rawId.toString();
          final orderIndex = orders.indexWhere((o) => o['id']?.toString() == orderId);
          
          if (orderIndex == -1) {
            _addDebugLog('⚠️ Order $orderId not found in orders list');
            continue;
          }
          
          final sourceOrder = orders[orderIndex];
          final orderItems = _normalizeItems(sourceOrder['items']);
          
          _addDebugLog('✅ Found order $orderId with ${orderItems.length} items');
          
          // Collect items with new shifted KOT number
          for (var item in orderItems) {
            if (item is Map<String, dynamic>) {
              // Create a copy to avoid mutating original
              final shiftedItem = Map<String, dynamic>.from(item);
              shiftedItem['kotNumber'] = int.tryParse(shiftedKotNumber) ?? 0;
              shiftedItem['original_kot_number'] = originalKotNumber;
              shiftedItem['is_shifted'] = true;
              shiftedItems.add(shiftedItem);
              
              // Track item name for popup
              final itemName = _getItemName(shiftedItem);
              if (itemName.isNotEmpty && !_shiftedItemNames.contains(itemName)) {
                _shiftedItemNames.add(itemName);
              }
            }
          }
          
          // Mark for removal
          indicesToRemove.add(orderIndex);
        }

        // Remove original orders (in reverse order to maintain indices)
        indicesToRemove.sort((a, b) => b.compareTo(a));
        for (final index in indicesToRemove) {
          _addDebugLog('🗑️ Removing original order at index $index');
          orders.removeAt(index);
        }

        if (shiftedItems.isEmpty) {
          _addDebugLog('⚠️ No items collected for shifted order');
          return;
        }

        // Step 2: Calculate totals
        int totalAmount = 0;
        int totalQuantity = 0;
        String firstServer = 'Unknown';
        
        for (var item in shiftedItems) {
          final qty = int.tryParse((item['quantity'] ?? '1').toString()) ?? 1;
          final price = int.tryParse((item['price'] ?? '0').toString()) ?? 0;
          totalQuantity += qty;
          totalAmount += (price * qty);
          
          // Get server from first item if available
          if (firstServer == 'Unknown') {
            if (item['orderItem'] is Map) {
              final orderItem = item['orderItem'] as Map;
              if (orderItem['user'] is Map) {
                firstServer = (orderItem['user']['name'] ?? 'Unknown').toString();
              }
            }
          }
        }
        
        final itemNameSummary = _createItemNameSummary(shiftedItems);
        
        // Step 3: Create NEW shifted order with unique ID
        // Use a combination that ensures uniqueness: shiftedKOT_section_table
        final uniqueShiftedId = '${shiftedKotNumber}_${toSectionName}_${toTableId}';
        
        final shiftedOrder = {
          'id': uniqueShiftedId, // Unique ID to prevent consolidation
          'kotNumber': int.tryParse(shiftedKotNumber) ?? 0, // Numeric shifted KOT
          'original_kot_number': originalKotNumber,
          'items': shiftedItems,
          'amount': totalAmount.toString(),
          'quantity': totalQuantity.toString(),
          'item_name': itemNameSummary,
          'status': 'Pending',
          'server': firstServer,
          'section_name': toSectionName,
          'restaurent_table_number': toTableId,
          'time': DateFormat('hh:mm a').format(DateTime.now()),
          'createdAt': DateTime.now().toIso8601String(),
          'isShifted': true,
          'is_shifted': true,
          'shifted_from_table': '$fromSectionName - Table $fromTableId',
          'skipConsolidation': true, // CRITICAL: Prevent consolidation
          'orderCount': shiftedOrderIds.length,
        };
        
        _addDebugLog('📦 Created new shifted order:');
        _addDebugLog('   ID: $uniqueShiftedId');
        _addDebugLog('   KOT: ${shiftedOrder['kotNumber']}');
        _addDebugLog('   Location: ${toSectionName} - Table ${toTableId}');
        _addDebugLog('   Items: ${shiftedItems.length}');
        _addDebugLog('   Amount: ₹$totalAmount');
        
        // Insert at top of orders list
        orders.insert(0, shiftedOrder);
        
        _addDebugLog('✅ Total orders in list: ${orders.length}');
      });
    }

    // Step 4: Show popup notification
    if (mounted && shiftedOrderIds.isNotEmpty) {
      _shiftFromText = '$fromSectionName - Table $fromTableId';
      _shiftToText = '$toSectionName - Table $toTableId';
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showKotShiftedPopup();
        }
      });
    }
  } catch (e, st) {
    _addDebugLog('❌ drinks_order_shifted error: $e');
    _addDebugLog('STACK: $st');
  }
});


    socket!.on('drinks_order_accepted', (data) {
      _handleStatusEvent(data, 'Accepted');
    });

    socket!.on('drinks_order_completed', (data) {
      _handleStatusEvent(data, 'Completed');
    });

    socket!.on('disconnect', (_) => _addDebugLog('Socket disconnected'));
  }




/// Handles delete event payload and prepares a minimal orderData for printing
Future<void> _handleDeleteEvent(Map<String, dynamic> payload) async {
  try {
    if (payload == null) return;

    final String id = (payload['id'] ?? payload['orderId'] ?? payload['order_id'] ?? '').toString();
    final String kotNumber = (payload['kotNumber'] ?? payload['kot'] ?? payload['kot_no'] ?? '').toString();
    final String itemName = (payload['itemName'] ?? payload['item_name'] ?? payload['item'] ?? '').toString();

    // Build a minimal order-like map that _printDeleteKOT expects
    final Map<String, dynamic> deletePrintData = {
      'id': id.isNotEmpty ? id : (kotNumber.isNotEmpty ? kotNumber : 'deleted'),
      'kotNumber': kotNumber.isNotEmpty ? kotNumber : (id.isNotEmpty ? id : 'deleted'),
      'server': '', // unknown from payload — optional
      'section_name': '',
      'restaurent_table_number': '',
      'items': [
        {
          'name': itemName.isNotEmpty ? itemName : 'Deleted Item',
          'qty': '1',
          'note': '',
        }
      ],
    };

    _addDebugLog('Calling delete-print for kot=${deletePrintData['kotNumber']} item=${itemName}');
    // fire-and-forget
    _printDeleteKOT(deletePrintData).catchError((e, st) {
      _addDebugLog('Error printing delete KOT: $e');
      _addDebugLog('STACK: $st');
    });
  } catch (e, st) {
    _addDebugLog('Exception in _handleDeleteEvent: $e');
    _addDebugLog('STACK: $st');
  }
}

Future<void> _reprintKOT(Map<String, dynamic> orderData) async {
  print(orderData);
  if (selectedPrinter == null) {
    _addDebugLog('No printer auto-selected yet — cannot reprint KOT for ${orderData['id']}');
    if (context.mounted) {
      showTopNotification(context, 'Printer Missing', 'Please connect USB printer and tap Scan');
    }
    return;
  }

  if (mounted) setState(() => isPrinting = true);
  try {
    final vendor = _intFromDynamic(selectedPrinter!.vendorId);
    final product = _intFromDynamic(selectedPrinter!.productId);
    _addDebugLog('Preparing Reprint KOT bytes for order ${orderData['id']} (VID=$vendor PID=$product)');

    // ---------- Canonical values ----------
    final sectionName = (orderData['section_name'] ?? '').toString().trim();
    final kotNumber = (orderData['kotNumber'] ?? orderData['id']).toString();
    final tableNo = (orderData['restaurent_table_number'] ?? orderData['table_number'] ?? '').toString().trim();
    final server = (orderData['server'] ?? '').toString().trim();
    final kotNo = kotNumber;
    final now = DateTime.now();
    final dateFormatted = DateFormat('dd/MM/yy').format(now);
    final timeFormatted = DateFormat('HH:mm').format(now);
    final dateTimeFormatted = '$dateFormatted $timeFormatted';

    // ---------- Collect items and metadata ----------
    List<Map<String, String>> items = [];
    if (orderData['items'] is List) {
      for (final raw in (orderData['items'] as List)) {
        if (raw is! Map) continue;
        final it = Map<String, dynamic>.from(raw);

        final name = (it['item_name'] ?? it['name'] ?? it['menuItem']?['name'] ?? '').toString();
        final qty = (it['quantity'] ?? it['qty'] ?? it['orderItem']?['quantity'] ?? '1').toString();
        final note = (it['item_desc'] ?? it['description'] ?? it['orderItem']?['desc'] ?? '').toString();

        // Extract kotCategory from likely places (menuItem.kotCategory or flattened)
        String kotCategory = '';
        try {
          if (it['menuItem'] is Map) {
            final mm = Map<String, dynamic>.from(it['menuItem']);
            kotCategory = (mm['kotCategory'] ?? mm['kot_category'] ?? '').toString();
          }
        } catch (_) {}
        if (kotCategory.trim().isEmpty) {
          kotCategory = (it['kotCategory'] ?? it['kot_category'] ?? '').toString();
        }

        // Extract categoryName if provided by backend
        String categoryName = '';
        try {
          if (it['menuItem'] is Map) {
            final mm = Map<String, dynamic>.from(it['menuItem']);
            categoryName = (mm['categoryName'] ?? mm['category_name'] ?? '').toString();
          }
        } catch (_) {}

        // Determine Indian Bread status (categoryName == "Indian Breads" OR name contains "bakhri")
        final nameLower = name.toLowerCase();
        final catNameTrim = categoryName.trim();
        final isIndianBread = (catNameTrim.toLowerCase() == 'indian breads'.toLowerCase()) || nameLower.contains('bakhri');

        items.add({
          'name': name,
          'qty': qty,
          'note': note,
          'kotCategory': kotCategory.trim().isEmpty ? 'Other' : kotCategory.trim(),
          'categoryName': catNameTrim,
          'isIndianBread': isIndianBread ? '1' : '0',
        });
      }
    }

    // Fallback single item if none present
    if (items.isEmpty) {
      items.add({
        'name': orderData['item_name']?.toString() ?? 'Item',
        'qty': orderData['quantity']?.toString() ?? '1',
        'note': orderData['item_desc']?.toString() ?? '',
        'kotCategory': 'Other',
        'categoryName': '',
        'isIndianBread': '0',
      });
    }

    // ---------- Decide grouping with Indian Breads rules ----------
    final indianItems = items.where((i) => i['isIndianBread'] == '1').toList();
    final nonIndianItems = items.where((i) => i['isIndianBread'] != '1').toList();
    final orderOnlyIndian = (indianItems.isNotEmpty && nonIndianItems.isEmpty);

    // Check presence of Veg-Indian or NonVeg-Indian kotCategory (case-insensitive)
    final hasIndianMainGroup = items.any((i) {
      final cat = (i['kotCategory'] ?? '').toString().trim().toLowerCase();
      return cat == 'veg-indian' || cat == 'nonveg-indian';
    });

    final Map<String, List<Map<String, String>>> grouped = {};

    if (orderOnlyIndian) {
      // Entire order is Indian Breads -> single group named "Indian Breads"
      grouped['Indian Breads'] = indianItems.map((e) => Map<String, String>.from(e)).toList();
    } else {
      // Place non-Indian items into their kotCategory buckets
      for (final it in nonIndianItems) {
        final cat = (it['kotCategory'] ?? 'Other').toString();
        grouped.putIfAbsent(cat, () => []);
        grouped[cat]!.add(Map<String, String>.from(it));
      }

      if (indianItems.isNotEmpty) {
        if (hasIndianMainGroup) {
          // Merge Indian breads into the first existing Veg-Indian or NonVeg-Indian bucket
          String targetKey = grouped.keys.firstWhere(
            (k) {
              final kk = k.toString().trim().toLowerCase();
              return kk == 'veg-indian' || kk == 'nonveg-indian';
            },
            orElse: () => '',
          );

          if (targetKey.isEmpty) {
            final foundInItems = items.firstWhere(
              (i) {
                final kk = (i['kotCategory'] ?? '').toString().trim().toLowerCase();
                return kk == 'veg-indian' || kk == 'nonveg-indian';
              },
              orElse: () => <String, String>{'kotCategory': ''},
            );
            targetKey = (foundInItems['kotCategory'] ?? '').toString();
            if (targetKey.trim().isEmpty) targetKey = 'Veg-Indian';
          }

          grouped.putIfAbsent(targetKey, () => []);
          for (final ib in indianItems) grouped[targetKey]!.add(Map<String, String>.from(ib));
        } else {
          for (final ib in indianItems) {
            final originalCat = (ib['kotCategory'] ?? '').toString();
            if (originalCat.isNotEmpty && originalCat.toLowerCase() != 'other') {
              grouped.putIfAbsent(originalCat, () => []);
              grouped[originalCat]!.add(Map<String, String>.from(ib));
            } else {
              grouped.putIfAbsent('Indian Breads', () => []);
              grouped['Indian Breads']!.add(Map<String, String>.from(ib));
            }
          }
        }
      }
    }

    // ---------- Prepare generator ----------
    final profile = await CapabilityProfile.load();
    const paper = PaperSize.mm80;
    final generator = Generator(paper, profile);

    // Helper: chunk string into fixed width pieces with smart word wrapping
    List<String> _chunks(String text, int width) {
      if (text.isEmpty) return [''];
      if (text.length <= width) return [text];
      
      List<String> result = [];
      String remaining = text.trim();
      
      while (remaining.length > width) {
        int splitIndex = width;
        
        // Try to find a space to break at (within reasonable distance from the edge)
        int lastSpace = remaining.lastIndexOf(' ', width);
        if (lastSpace > width * 0.7) { // Only use space if it's not too far back (70% of width)
          splitIndex = lastSpace;
        }
        
        String chunk = remaining.substring(0, splitIndex).trim();
        if (chunk.isNotEmpty) {
          result.add(chunk);
        }
        
        remaining = remaining.substring(splitIndex).trim();
      }
      
      if (remaining.isNotEmpty) {
        result.add(remaining);
      }
      
      return result.isEmpty ? [''] : result;
    }

    // ---------- Iterate groups and print KOT per group ----------
    for (final entry in grouped.entries) {
      final category = 'REPRINT KOT'; // Changed to show REPRINT
      final catItems = entry.value;

      if (catItems.isEmpty) continue;

      List<int> bytes = [];
      bytes += generator.reset();
      bytes += [0x1B, 0x4D, 0x00]; // ESC M 0 - Select Font A

      // Header: REPRINT category (modified from original)
      bytes += generator.text(category, styles: PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size1,
        width: PosTextSize.size2,
      ));

      bytes += generator.text(dateTimeFormatted, styles: PosStyles(
        align: PosAlign.center,
        bold: false,
        height: PosTextSize.size1,
        width: PosTextSize.size2,
      ));

      bytes += generator.text('KOT - $kotNo', styles: PosStyles(
        align: PosAlign.center,
        bold: false,
        height: PosTextSize.size1,
        width: PosTextSize.size2,
      ));

      // Table line
      String tablePart;
      if (tableNo.isNotEmpty && sectionName.isNotEmpty) {
        tablePart = 'Table No: ${sectionName}-${tableNo}';
      } else if (tableNo.isNotEmpty) {
        tablePart = 'Table No: $tableNo';
      } else {
        tablePart = 'Table No: N/A';
      }
      bytes += generator.text(tablePart, styles: PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size1,
        width: PosTextSize.size2,
      ));

      // Dotted line separator
      bytes += generator.text('.' * 48);

      // Server info
      if (server.isNotEmpty) {
        bytes += generator.text('Captain: ${server.toUpperCase()}', styles: PosStyles(
          align: PosAlign.left,
          bold: false,
        ));
        bytes += generator.text('.' * 48);
      }

      // Table header
      String headerLine = 'Item'.padRight(28) +
          'Special Note'.padRight(10) +
          'Qty'.padLeft(10);

      bytes += generator.text(headerLine, styles: PosStyles(
        align: PosAlign.left,
        bold: false,
      ));

      // Print items in this group with improved text handling and duplicate filtering
      for (int idx = 0; idx < catItems.length; idx++) {
        final it = catItems[idx];
        final name = (it['name'] ?? '').toString().trim();
        final rawNote = (it['note'] ?? '').toString().trim();
        final qty = (it['qty'] ?? '1').toString().trim();

        // Apply duplicate filtering logic - same as UI components
        String note = rawNote;
        bool isDuplicateNote = false;
        if (rawNote.isNotEmpty && name.isNotEmpty) {
          final nameLower = name.toLowerCase().trim();
          final noteLower = rawNote.toLowerCase().trim();
          
          // Exact match
          if (nameLower == noteLower) {
            isDuplicateNote = true;
          }
          // Check if note is contained in name or vice versa
          else if (nameLower.contains(noteLower) || noteLower.contains(nameLower)) {
            final shorter = nameLower.length < noteLower.length ? nameLower : noteLower;
            final longer = nameLower.length >= noteLower.length ? nameLower : noteLower;
            // If the shorter string is at least 70% of the longer string, consider it duplicate
            if (shorter.length >= longer.length * 0.7) {
              isDuplicateNote = true;
            }
          }
        }

        // Don't print note if it's a duplicate, otherwise wrap in parentheses
        if (isDuplicateNote) {
          note = '';
        } else if (note.isNotEmpty) {
          note = '($note)';
        }

        // Handle long item names by truncating or abbreviating if necessary (same logic as _printOrderNative)
        String displayName = name;
        if (name.length > 25) {
          // Try smart truncation - keep important words
          List<String> words = name.split(' ');
          if (words.length > 1) {
            String abbreviated = words.map((word) {
              // Keep first word full, abbreviate others if needed
              if (word == words.first) return word;
              if (word.length > 4) return '${word.substring(0, 3)}.';
              return word;
            }).join(' ');
            
            if (abbreviated.length <= 25) {
              displayName = abbreviated;
            } else {
              displayName = name.length > 25 ? '${name.substring(0, 22)}...' : name;
            }
          } else {
            displayName = name.length > 25 ? '${name.substring(0, 22)}...' : name;
          }
        }

        // For very long names that still don't fit, use chunking as fallback
        final nameChunks = displayName.length <= 28 ? [displayName] : _chunks(displayName, 28);
        final noteChunks = note.isEmpty ? [''] : _chunks(note, 10);
        final maxLines = [nameChunks.length, noteChunks.length].reduce((a, b) => a > b ? a : b);

        for (int line = 0; line < maxLines; line++) {
          final namePart = (line < nameChunks.length) ? nameChunks[line] : '';
          final notePart = (line < noteChunks.length) ? noteChunks[line] : '';

          if (line == 0) {
            // First line: show item name, note, and qty
            final nameField = namePart.padRight(28);
            final noteField = notePart.padRight(10);
            final qtyField = qty.padLeft(10);
            final outLine = nameField + noteField + qtyField;
            bytes += generator.text(outLine, styles: PosStyles(
              align: PosAlign.left,
              bold: true,
              height: PosTextSize.size1,
              width: PosTextSize.size2,
            ));
          } else {
            // Continuation lines: show remaining name/note, no qty
            final nameField = namePart.padRight(28);
            final noteField = notePart.padRight(10);
            final qtyField = ''.padLeft(10);
            final outLine = nameField + noteField + qtyField;
            bytes += generator.text(outLine, styles: PosStyles(
              align: PosAlign.left,
              bold: false,
              height: PosTextSize.size1,
              width: PosTextSize.size2,
            ));
          }
        }
      }

      // Final separator + total for this group
      bytes += generator.text('.' * 48);
      final totalQty = catItems.fold<int>(0, (acc, it) => acc + (int.tryParse(it['qty'] ?? '0') ?? 0));
      bytes += generator.text('Total Qty: $totalQty', styles: PosStyles(
        align: PosAlign.right,
        bold: false,
      ));

      // Final spacing and cut
      bytes += generator.feed(1);
      try {
        bytes += generator.cut();
      } catch (_) {
        bytes += generator.feed(5);
      }

      // Send to printer
      try {
        final result = await UsbPrinter.printRawBytes(
          vendorId: vendor,
          productId: product,
          bytes: Uint8List.fromList(bytes),
          timeoutMillis: 5000,
        );
        _addDebugLog('Reprint KOT printed for category="$category" (result=$result) for order ${orderData['id']}');
        if (context.mounted) {
          showTopNotification(context, 'Reprinted', 'Reprint KOT ${orderData['id']} ($category) printed.');
        }
      } catch (e) {
        _addDebugLog('Print error while reprinting category="$category" for order ${orderData['id']}: $e');
        if (context.mounted) showTopNotification(context, 'Reprint Error', 'Failed to reprint $category KOT: $e');
      }
    } // end grouped loop

  } catch (e, st) {
    _addDebugLog('Reprint error for order ${orderData['id']}: $e');
    _addDebugLog('STACK: $st');
    if (context.mounted) showTopNotification(context, 'Reprint Error', e.toString());
  } finally {
    if (mounted) setState(() => isPrinting = false);
  }
}



/// Print a "Delete Order" KOT. Simpler than full _printOrderNative — single heading "DELETE ORDER".
Future<void> _printDeleteKOT(Map<String, dynamic> orderData) async {
  if (selectedPrinter == null) {
    _addDebugLog('No printer selected — cannot print delete KOT for ${orderData['id']}');
    try {
      await _scanForPrinters();
    } catch (_) {}
    if (selectedPrinter == null) {
      if (context.mounted) showTopNotification(context, 'Print skipped', 'No USB printer connected for Delete KOT');
      return;
    }
  }

  if (mounted) setState(() => isPrinting = true);

  try {
    final vendor = _intFromDynamic(selectedPrinter!.vendorId);
    final product = _intFromDynamic(selectedPrinter!.productId);
    final profile = await CapabilityProfile.load();
    const paper = PaperSize.mm80;
    final generator = Generator(paper, profile);

    final kotNo = (orderData['kotNumber'] ?? orderData['id'] ?? '').toString();
    final now = DateTime.now();
    final dateFormatted = DateFormat('dd/MM/yy').format(now);
    final timeFormatted = DateFormat('HH:mm').format(now);
    final dateTimeFormatted = '$dateFormatted $timeFormatted';
    final server = (orderData['server'] ?? '').toString();
    final tableNo = (orderData['restaurent_table_number'] ?? orderData['table_number'] ?? '').toString();

    // Build items list
    List<Map<String, String>> items = [];
    final rawItems = orderData['items'];
    if (rawItems is List && rawItems.isNotEmpty) {
      for (final raw in rawItems) {
        if (raw is Map) {
          items.add({
            'name': (raw['name'] ?? raw['item_name'] ?? '').toString(),
            'qty': (raw['qty'] ?? raw['quantity'] ?? '1').toString(),
            'note': (raw['note'] ?? raw['item_desc'] ?? '').toString(),
          });
        }
      }
    } else {
      items.add({
        'name': orderData['item_name']?.toString() ?? 'Deleted Item',
        'qty': orderData['quantity']?.toString() ?? '1',
        'note': orderData['item_desc']?.toString() ?? '',
      });
    }

    // Helper chunker (same as _printOrderNative)
    List<String> _chunks(String s, int width) {
      final List<String> out = [];
      if (s.isEmpty) {
        return [''];
      }
      int i = 0;
      while (i < s.length) {
        int end = (i + width < s.length) ? i + width : s.length;
        out.add(s.substring(i, end));
        i = end;
      }
      return out;
    }

    // Compose bytes
    List<int> bytes = [];
    bytes += generator.reset();
    bytes += [0x1B, 0x4D, 0x00]; // ESC M 0 - Select Font A (same as native)

    // Header: DELETE ORDER (using same styling pattern as native)
    bytes += generator.text('* DELETED ORDER *', styles: PosStyles(
      align: PosAlign.center,
      bold: true,
      height: PosTextSize.size1,
      width: PosTextSize.size2,
    ));

    // Date and time - same format as native
    bytes += generator.text(dateTimeFormatted, styles: PosStyles(
      align: PosAlign.center,
      bold: false,
      height: PosTextSize.size1,
      width: PosTextSize.size2,
    ));

    // KOT number - same format as native
    bytes += generator.text('KOT - $kotNo', styles: PosStyles(
      align: PosAlign.center,
      bold: false,
      height: PosTextSize.size1,
      width: PosTextSize.size2,
    ));

    // Table info (same logic as native)
    if (tableNo.isNotEmpty) {
      bytes += generator.text('Table No: $tableNo', styles: PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size1,
        width: PosTextSize.size2,
      ));
    }

    // Dotted line separator (same as native)
    bytes += generator.text('.' * 48);

    // Server info (same as native)
    if (server.isNotEmpty) {
      bytes += generator.text('Captain: ${server.toUpperCase()}', styles: PosStyles(
        align: PosAlign.left,
        bold: false,
      ));
      bytes += generator.text('.' * 48);
    }

    // Table header (EXACT same as native: name=31, note=10, qty=7)
    String headerLine = 'Item'.padRight(30) +
        'Special Note'.padRight(10) +
        'Qty'.padLeft(8);

    bytes += generator.text(headerLine, styles: PosStyles(
      align: PosAlign.left,
      bold: false,
    ));

    // Items (EXACT same logic as native)
    for (int idx = 0; idx < items.length; idx++) {
      final it = items[idx];
      final name = (it['name'] ?? '').toString().trim();
      final note = (it['note'] ?? '').toString().trim();
      final qty = (it['qty'] ?? '1').toString().trim();

      // Break name/note into chunks matching columns (same as native)
      final nameChunks = _chunks(name, 30);
      final noteChunks = _chunks(note, 10);
      final maxLines = [nameChunks.length, noteChunks.length].reduce((a, b) => a > b ? a : b);

      for (int line = 0; line < maxLines; line++) {
        final namePart = (line < nameChunks.length) ? nameChunks[line] : '';
        final notePart = (line < noteChunks.length) ? noteChunks[line] : '';

        if (line == 0) {
          final nameField = namePart.padRight(30);
          final noteField = notePart.padRight(10);
          final qtyField = qty.padLeft(8);
          final outLine = nameField + noteField + qtyField;
          bytes += generator.text(outLine, styles: PosStyles(
            align: PosAlign.left,
            bold: true,
            height: PosTextSize.size1,
            width: PosTextSize.size2,
          ));
        } else {
          final nameField = namePart.padRight(30);
          final noteField = notePart.padRight(10);
          final qtyField = ''.padLeft(8);
          final outLine = nameField + noteField + qtyField;
          bytes += generator.text(outLine, styles: PosStyles(
            align: PosAlign.left,
            bold: false,
            height: PosTextSize.size1,
            width: PosTextSize.size2,
          ));
        }
      }
    }

    // Final dotted separator (same as native)
    bytes += generator.text('.' * 48);

    // Total items line (same as native)
    final totalQty = items.fold<int>(
      0,
      (acc, it) => acc + (int.tryParse(it['qty'] ?? '0') ?? 0),
    );

    bytes += generator.text('Total Qty: $totalQty', styles: PosStyles(
      align: PosAlign.right,
      bold: false,
    ));

    // Final spacing and cut (same as native)
    bytes += generator.feed(1);
    try {
      bytes += generator.cut();
    } catch (_) {
      bytes += generator.feed(5);
    }

    // Send to USB printer
    try {
      final result = await UsbPrinter.printRawBytes(
        vendorId: vendor,
        productId: product,
        bytes: Uint8List.fromList(bytes),
        timeoutMillis: 5000,
      );
      _addDebugLog('Delete KOT printed for kot=$kotNo id=${orderData['id']} (result=$result)');
      if (context.mounted) showTopNotification(context, 'Printed', 'Delete KOT $kotNo printed.');
    } catch (e) {
      _addDebugLog('Error sending delete KOT to printer: $e');
      if (context.mounted) showTopNotification(context, 'Print Error', 'Failed to print Delete KOT: $e');
    }
  } catch (e, st) {
    _addDebugLog('Exception in _printDeleteKOT: $e');
    _addDebugLog('STACK: $st');
    if (context.mounted) showTopNotification(context, 'Print Error', e.toString());
  } finally {
    if (mounted) setState(() => isPrinting = false);
  }
}






// Generic handler used by both accepted/completed events
void _handleStatusEvent(dynamic data, String newStatus) {
  try {
    _addDebugLog("Socket event for status '$newStatus' received: ${data.runtimeType} -> $data");

    Map<String, dynamic>? payload;
    String? kotNumber;
    List<String> orderIds = [];

    // Normalize payload (could be a plain string, JSON string, or Map)
    if (data is String) {
      // If it's JSON string try decode, otherwise treat as kotNumber string
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) payload = Map<String, dynamic>.from(decoded);
        else if (decoded is String) kotNumber = decoded;
      } catch (_) {
        kotNumber = data.trim();
      }
    } else if (data is Map) {
      payload = Map<String, dynamic>.from(data);
    }

    // Extract kotNumber from common keys if payload exists
    if (payload != null) {
      kotNumber = payload['kotNumber']?.toString() ??
                  payload['kot']?.toString() ??
                  payload['kot_no']?.toString() ??
                  kotNumber;
      // extract orderIds if provided
      final rawIds = payload['orderIds'] ?? payload['orderIds'] ?? payload['orderIds'];
      if (rawIds is List) {
        orderIds = rawIds.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
      } else if (rawIds is String) {
        orderIds = [rawIds];
      } else if (payload['orderIds'] == null && payload['orderId'] != null) {
        // some servers send a single orderId
        orderIds = [payload['orderId'].toString()];
      }
    }

    // If we still have neither kotNumber nor orderIds, try to interpret `data` as a small map
    if ((kotNumber == null || kotNumber.isEmpty) && payload == null && data is! String) {
      // try a last-ditch convert
      try {
        final asJson = jsonDecode(data.toString());
        if (asJson is Map) {
          payload = Map<String, dynamic>.from(asJson);
          kotNumber = kotNumber ?? payload['kotNumber']?.toString();
        }
      } catch (_) {}
    }

    // Update the local orders list
    if (mounted) {
      setState(() {
        int matched = 0;

        // 1) Update by kotNumber (preferred)
        if (kotNumber != null && kotNumber.toString().trim().isNotEmpty) {
          final k = kotNumber.toString().trim();
          for (int i = 0; i < orders.length; i++) {
            final orderKot = (orders[i]['kotNumber'] ?? orders[i]['id'] ?? '').toString();
            if (orderKot == k) {
              orders[i]['status'] = newStatus;
              matched++;
            }
          }
        }

        // 2) If no kotNumber matched but server supplied orderIds, update by order id(s)
        if (matched == 0 && orderIds.isNotEmpty) {
          for (final oid in orderIds) {
            for (int i = 0; i < orders.length; i++) {
              final currentId = (orders[i]['id'] ?? '').toString();
              if (_orderIdMatches(currentId, oid)) {
                orders[i]['status'] = newStatus;
                matched++;
              }
            }
          }
        }

        // 3) If still nothing matched, try a more permissive pass: check each order's items for matching ids.
        if (matched == 0 && orderIds.isNotEmpty) {
          for (final oid in orderIds) {
            for (int i = 0; i < orders.length; i++) {
              final items = _normalizeItems(orders[i]['items']);
              if (_hasItemWithId(items, oid)) {
                orders[i]['status'] = newStatus;
                matched++;
              }
            }
          }
        }

        // Debug log
        _addDebugLog("Applied status '$newStatus' to $matched local order(s) for kot='$kotNumber' orderIds=$orderIds");
      });
    }

    // Notification for user
    if (context.mounted) {
      final displayKot = kotNumber ?? (orderIds.isNotEmpty ? orderIds.first : 'unknown');
      // showTopNotification(context, 'KOT $newStatus', 'KOT #$displayKot marked $newStatus');
    }
  } catch (e, st) {
    _addDebugLog("Error handling socket status event ($newStatus): $e");
    _addDebugLog('STACK: $st');
  }
}




  // ----------------- Helper utilities (add these inside your State class) -----------------

  String? _extractId(Map<String, dynamic> payload, List<String> fieldNames) {
    for (String field in fieldNames) {
      final raw = payload[field];
      if (raw == null) continue;
      final value = raw.toString().trim();
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  /// Safety-first strategy:
  /// 1) If top-level order found with <=1 item or payload.force==true -> remove whole order
  /// 2) If top-level order found with >1 items -> try to remove matching nested item(s) inside that order first
  /// 3) If no top-level order found -> search across orders for nested item matches and remove them
  void _maybeRemoveEntireOrder(
    String orderIdToRemove,
    Map<String, dynamic>? payload,
  ) {
    _addDebugLog('Attempting safe remove check for order: $orderIdToRemove');

    // Try find top-level order by id
    final orderIndex = orders.indexWhere(
      (o) => _orderIdMatches(o['id']?.toString(), orderIdToRemove),
    );
    if (orderIndex >= 0) {
      final order = orders[orderIndex];
      final items = _normalizeItems(order['items']);
      final itemCount = items.length;
      _addDebugLog(
        'Order $orderIdToRemove found (top-level) with $itemCount item(s)',
      );

      final forceRemove =
          payload != null &&
          (payload['force'] == true || payload['force']?.toString() == 'true');
      if (forceRemove || itemCount <= 1) {
        _addDebugLog(
          'Removing whole order $orderIdToRemove (force=$forceRemove or itemCount<=1)',
        );
        _removeEntireOrder(orderIdToRemove);
        return;
      }

      // order has >1 items: try to remove nested item(s) inside this order that match the incoming id
      _addDebugLog(
        'Order $orderIdToRemove has multiple items; trying nested-item removal inside this order before refusing full deletion.',
      );

      for (var it in items) {
        if (it is! Map<String, dynamic>) continue;
        if (_itemMatchesId(it, orderIdToRemove)) {
          // pick the best candidate id inside the item for removal
          String candidateItemId = '';
          try {
            if ((it['order_item_id']?.toString().trim().isNotEmpty ?? false))
              candidateItemId = it['order_item_id'].toString().trim();
          } catch (_) {}
          if (candidateItemId.isEmpty) {
            try {
              if (it['orderItem'] is Map && it['orderItem']['id'] != null)
                candidateItemId = it['orderItem']['id'].toString().trim();
            } catch (_) {}
          }
          if (candidateItemId.isEmpty) {
            try {
              if (it['id'] != null)
                candidateItemId = it['id'].toString().trim();
            } catch (_) {}
          }
          if (candidateItemId.isEmpty) {
            try {
              if (it['menu_item_id'] != null)
                candidateItemId = it['menu_item_id'].toString().trim();
            } catch (_) {}
          }
          if (candidateItemId.isEmpty) {
            try {
              if (it['menu'] is Map && it['menu']['id'] != null)
                candidateItemId = it['menu']['id'].toString().trim();
            } catch (_) {}
          }
          if (candidateItemId.isEmpty) candidateItemId = orderIdToRemove;

          _addDebugLog(
            'Nested match inside same order: removing itemId=$candidateItemId from orderId=${order['id']} (matched by $orderIdToRemove)',
          );
          _removeItemFromOrderById(
            orderId: order['id']?.toString() ?? '',
            itemId: candidateItemId,
            notify: true,
          );
          return;
        }
      }

      // No nested match inside top-level order -> refuse to remove whole order
      _addDebugLog(
        'No nested item matched inside top-level order $orderIdToRemove. Refusing to remove whole order (no force flag).',
      );
      return;
    }

    // No top-level match; try nested match across all orders
    _addDebugLog(
      'Top-level order $orderIdToRemove not found — attempting nested item match across orders.',
    );
    final found = _findAndRemoveItemByNestedId(orderIdToRemove);
    if (found) {
      _addDebugLog(
        'Successfully removed matching nested item(s) for id $orderIdToRemove',
      );
      return;
    }

    _addDebugLog(
      'Safer-guard: nothing matched for id $orderIdToRemove (no top-level order, no nested item). Not removing any order.',
    );
  }

  /// Search all orders' items to find any item that matches the provided id in any nested shape
  /// If found, remove that item from its parent order and return true.
  bool _findAndRemoveItemByNestedId(String idToMatch) {
    if (idToMatch.trim().isEmpty) return false;
    final target = idToMatch.trim();

    for (int oi = 0; oi < orders.length; oi++) {
      final order = orders[oi];
      final parentOrderId = order['id']?.toString() ?? '';
      final items = _normalizeItems(order['items']);

      for (var it in items) {
        if (it is! Map<String, dynamic>) continue;
        if (_itemMatchesId(it, target)) {
          // choose candidate item id to remove
          String candidateItemId = '';
          try {
            if ((it['order_item_id']?.toString().trim().isNotEmpty ?? false))
              candidateItemId = it['order_item_id'].toString().trim();
          } catch (_) {}
          if (candidateItemId.isEmpty) {
            try {
              if (it['orderItem'] is Map && it['orderItem']['id'] != null)
                candidateItemId = it['orderItem']['id'].toString().trim();
            } catch (_) {}
          }
          if (candidateItemId.isEmpty) {
            try {
              if (it['id'] != null)
                candidateItemId = it['id'].toString().trim();
            } catch (_) {}
          }
          if (candidateItemId.isEmpty) {
            try {
              if (it['menu'] is Map && it['menu']['id'] != null)
                candidateItemId = it['menu']['id'].toString().trim();
            } catch (_) {}
          }
          if (candidateItemId.isEmpty) candidateItemId = target;

          _addDebugLog(
            'Nested match: removing itemId=$candidateItemId from parent orderId=$parentOrderId (matched by $target)',
          );
          _removeItemFromOrderById(
            orderId: parentOrderId,
            itemId: candidateItemId,
            notify: true,
          );
          return true;
        }
      }
    }

    _addDebugLog('No nested item matched id $target in any current order');
    if (debugLogs.length < 200) {
      // avoid huge dumps in production
      for (int i = 0; i < orders.length; i++) {
        _addDebugLog(
          'DEBUG ORD ${i} id=${orders[i]['id']} items=${orders[i]['items']}',
        );
      }
    }
    return false;
  }

  /// Try many common keys and nested shapes to decide whether item matches target id.
  /// This mirrors the robust matcher used in food screen.
  bool _itemMatchesId(Map<String, dynamic> item, String targetId) {
    try {
      if (targetId.trim().isEmpty) return false;
      final t = targetId.trim();

      bool equalLoose(dynamic a, String b) {
        if (a == null) return false;
        final as = a.toString().trim();
        if (as == b) return true;
        final ai = int.tryParse(as);
        final bi = int.tryParse(b);
        if (ai != null && bi != null) return ai == bi;
        return false;
      }

      final keysToCheck = [
        'id',
        'item_id',
        'itemId',
        'order_item_id',
        'orderItemId',
        'menu_item_id',
        'menuItemId',
        'menu_item',
        'menu',
        'orderItem',
        'order_item',
      ];
      for (final k in keysToCheck) {
        try {
          if (item.containsKey(k) && equalLoose(item[k], t)) {
            _addDebugLog('Match by key "$k" -> ${item[k]} == $t');
            return true;
          }
        } catch (_) {}
      }

      // nested orderItem
      if (item['orderItem'] is Map) {
        final om = item['orderItem'] as Map;
        if (equalLoose(om['id'], t)) {
          _addDebugLog('Match by orderItem.id -> ${om['id']} == $t');
          return true;
        }
        if (equalLoose(om['orderId'], t) || equalLoose(om['order_id'], t)) {
          _addDebugLog(
            'Match by orderItem.orderId -> ${om['orderId'] ?? om['order_id']} == $t',
          );
          return true;
        }
        if (equalLoose(om['menuId'], t) || equalLoose(om['menu_id'], t)) {
          _addDebugLog(
            'Match by orderItem.menuId -> ${om['menuId'] ?? om['menu_id']} == $t',
          );
          return true;
        }
      }

      if (item['menu'] is Map) {
        final mm = item['menu'] as Map;
        if (equalLoose(mm['id'], t)) {
          _addDebugLog('Match by menu.id -> ${mm['id']} == $t');
          return true;
        }
        if ((mm['name']?.toString() ?? '').trim() == t) {
          _addDebugLog(
            'Match by menu.name -> ${mm['name']} == $t (string match)',
          );
          return true;
        }
      }

      // shallow nested search
      bool shallowSearch(Map m) {
        for (final entry in m.entries) {
          final v = entry.value;
          if (v == null) continue;
          if (v is String || v is num) {
            if (equalLoose(v, t)) {
              _addDebugLog(
                'Shallow nested match by key "${entry.key}" -> $v == $t',
              );
              return true;
            }
          }
        }
        return false;
      }

      for (final key in [
        'orderItem',
        'menu',
        'drinkMenu',
        'drink',
        'order_item',
        'menu_item',
      ]) {
        try {
          final val = item[key];
          if (val is Map && shallowSearch(val)) return true;
        } catch (_) {}
      }
      return false;
    } catch (e) {
      _addDebugLog('Error matching item ID: $e');
      return false;
    }
  }

  /// Remove specific item from specific order (updates UI). Mirrors the implementation used in food screen.
  Future<void> _removeItemFromOrderById({
    required String orderId,
    required String itemId,
    bool notify = true,
  }) async {
    final orderIndex = orders.indexWhere(
      (order) => _orderIdMatches(order['id']?.toString(), orderId),
    );

    if (orderIndex < 0) {
      _addDebugLog('Order with ID $orderId not found for item removal');
      return;
    }

    final order = orders[orderIndex];
    List<Map<String, dynamic>> currentItems = _normalizeItems(order['items']);

    if (currentItems.isEmpty) {
      _addDebugLog('Order $orderId has no structured items to remove from');
      return;
    }

    final initialItemCount = currentItems.length;

    // remove matching items using matcher
    currentItems.removeWhere((item) => _itemMatchesId(item, itemId));

    final removedCount = initialItemCount - currentItems.length;
    if (removedCount == 0) {
      _addDebugLog('No matching item with ID=$itemId found in order $orderId');
      return;
    }

    // recompute totals
    int totalQty = 0;
    int totalAmount = 0;
    for (var it in currentItems) {
      try {
        final qty =
            int.tryParse((it['quantity'] ?? it['qty'] ?? '1').toString()) ?? 1;
        totalQty += qty;
        final price = int.tryParse((it['price'] ?? '0').toString()) ?? 0;
        totalAmount += price;
      } catch (e) {
        totalQty += 1;
        _addDebugLog('Error calculating totals for item: $e');
      }
    }

    final itemNameSummary =
        currentItems.isEmpty
            ? ''
            : (currentItems.length == 1
                ? (currentItems.first['item_name'] ??
                    currentItems.first['name'] ??
                    'Unnamed Item')
                : '${currentItems.first['item_name'] ?? currentItems.first['name'] ?? 'Item'} +${currentItems.length - 1} more');

    // update UI
    if (mounted) {
      setState(() {
        if (currentItems.isEmpty) {
          orders.removeAt(orderIndex);
          _addDebugLog('Removed order card $orderId - no items remaining');
        } else {
          order['items'] = currentItems;
          order['quantity'] = totalQty.toString();
          order['item_name'] = itemNameSummary;
          order['amount'] = totalAmount.toString();
          orders[orderIndex] = order;
          _addDebugLog(
            'Updated order card $orderId - ${currentItems.length} items remaining',
          );
        }
      });
    } else {
      if (currentItems.isEmpty) {
        orders.removeAt(orderIndex);
      } else {
        order['items'] = currentItems;
        order['quantity'] = totalQty.toString();
        order['item_name'] = itemNameSummary;
        order['amount'] = totalAmount.toString();
        orders[orderIndex] = order;
      }
    }

    _addDebugLog(
      'Removed $removedCount item(s) with ID=$itemId from order $orderId. Remaining items: ${currentItems.length}',
    );
    if (notify && context.mounted) {
      if (currentItems.isEmpty) {
        showTopNotification(
          context,
          'Order Removed',
          'Order #$orderId deleted (no items left)',
        );
      } else {
        showTopNotification(
          context,
          'Item Removed',
          'Item removed from Order #$orderId',
        );
      }
    }
  }

  /// Remove entire order card by id (safe remove).
  void _removeEntireOrder(String orderIdToRemove) {
    final initialCount = orders.length;
    _addDebugLog('Attempting to remove entire order with ID: $orderIdToRemove');
    _addDebugLog('Current orders count: ${orders.length}');
    for (int i = 0; i < orders.length && i < 50; i++) {
      final id = orders[i]['id']?.toString();
      _addDebugLog('Order $i: ID = "$id"');
    }

    if (mounted) {
      setState(() {
        orders.removeWhere(
          (order) => _orderIdMatches(order['id']?.toString(), orderIdToRemove),
        );
      });
    } else {
      orders.removeWhere(
        (order) => _orderIdMatches(order['id']?.toString(), orderIdToRemove),
      );
    }

    final removedCount = initialCount - orders.length;
    _addDebugLog('Removed $removedCount order(s) with ID $orderIdToRemove');
    _addDebugLog('Orders count after removal: ${orders.length}');
    if (removedCount > 0 && context.mounted) {
      showTopNotification(
        context,
        'Order Removed',
        'Order #$orderIdToRemove has been deleted',
      );
    } else if (removedCount == 0) {
      _addDebugLog('Order $orderIdToRemove not found in current orders list');
    }
  }

  bool _orderIdMatches(String? currentId, String targetId) {
    if (currentId == null || targetId.isEmpty) return false;
    if (currentId == targetId) return true;
    try {
      final currentNum = int.tryParse(currentId);
      final targetNum = int.tryParse(targetId);
      if (currentNum != null && targetNum != null)
        return currentNum == targetNum;
    } catch (_) {}
    if (currentId.trim() == targetId.trim()) return true;
    return false;
  }

  List<Map<String, dynamic>> _normalizeItems(dynamic raw) {
    try {
      if (raw == null) return <Map<String, dynamic>>[];
      if (raw is List) {
        return raw.map<Map<String, dynamic>>((e) {
          if (e is Map<String, dynamic>) return e;
          if (e is Map) return Map<String, dynamic>.from(e);
          if (e is String) {
            try {
              final dec = jsonDecode(e);
              if (dec is Map) return Map<String, dynamic>.from(dec);
            } catch (_) {}
          }
          return <String, dynamic>{};
        }).toList();
      }
      if (raw is String) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.map<Map<String, dynamic>>((e) {
            if (e is Map<String, dynamic>) return e;
            if (e is Map) return Map<String, dynamic>.from(e);
            return <String, dynamic>{};
          }).toList();
        }
      }
    } catch (e) {
      _addDebugLog('Error normalizing items: $e');
    }
    return <Map<String, dynamic>>[];
  }

  void _removeItemFromAllOrders(String itemId) {
    bool itemFound = false;
    List<String> affectedOrders = [];

    for (int orderIndex = 0; orderIndex < orders.length; orderIndex++) {
      final order = orders[orderIndex];
      final orderId = order['id']?.toString() ?? '';
      if (orderId.isEmpty) continue;
      final items = _normalizeItems(order['items']);
      final hasMatchingItem = _hasItemWithId(items, itemId);
      if (hasMatchingItem) {
        itemFound = true;
        affectedOrders.add(orderId);
        _removeItemFromOrderById(
          orderId: orderId,
          itemId: itemId,
          notify: false,
        );
      }
    }

    if (itemFound && context.mounted) {
      final orderText =
          affectedOrders.length == 1
              ? 'Order #${affectedOrders.first}'
              : '${affectedOrders.length} orders';
      showTopNotification(
        context,
        'Item Removed',
        'Item removed from $orderText',
      );
    } else {
      _addDebugLog('Item with ID $itemId not found in any order');
    }
  }

  bool _hasItemWithId(List<Map<String, dynamic>> items, String targetId) {
    for (var item in items) {
      if (_itemMatchesId(item, targetId)) return true;
    }
    return false;
  }

  // ----------------- Printing (Generator -> native) -----------------
  Future<void> _printOrderNative(Map<String, dynamic> orderData) async {
    if (selectedPrinter == null) {
      _addDebugLog(
        'No printer auto-selected yet — cannot print order ${orderData['id']}',
      );
      showTopNotification(
        context,
        'Printer Missing',
        'Please connect USB printer and tap Scan',
      );
      return;
    }

    setState(() => isPrinting = true);
    try {
      final vendor = _intFromDynamic(selectedPrinter!.vendorId);
      final product = _intFromDynamic(selectedPrinter!.productId);
      _addDebugLog(
        'Preparing KOT bytes for order ${orderData['id']} (VID=$vendor PID=$product)',
      );

      // ---------- Build canonical values ----------
      final sectionName = (orderData['section_name'] ?? '').toString().trim();
      final tableNo =
          (orderData['restaurent_table_number'] ?? '').toString().trim();
      final server = (orderData['server'] ?? '').toString().trim();
      final kotNo = orderData['id']?.toString() ?? '';

      // Format date and time properly
      final now = DateTime.now();
      final dateFormatted = DateFormat('dd/MM/yy').format(now);
      final timeFormatted = DateFormat('HH:mm').format(now);
      final dateTimeFormatted = '$dateFormatted $timeFormatted';

      // Build items list
      List<Map<String, String>> items = [];
      if (orderData['items'] is List) {
        for (final it in (orderData['items'] as List)) {
          if (it is Map) {
            final name = (it['item_name'] ?? it['name'] ?? '').toString();
            final qty = (it['quantity'] ?? it['qty'] ?? '1').toString();
            final note =
                (it['item_desc'] ?? it['description'] ?? '').toString();
            items.add({'name': name, 'qty': qty, 'note': note});
          }
        }
      }
      if (items.isEmpty) {
        items.add({
          'name': orderData['item_name']?.toString() ?? 'Item',
          'qty': orderData['quantity']?.toString() ?? '1',
          'note': orderData['item_desc']?.toString() ?? '',
        });
      }

      // ---------- Create ESC/POS bytes ----------
      final profile = await CapabilityProfile.load();
      const paper = PaperSize.mm80;
      final generator = Generator(paper, profile);

      List<int> bytes = [];

      // Reset printer and use font A (cleaner font)
      bytes += generator.reset();

      // Try to select Font A (most printers have Font A and Font B)
      bytes += [0x1B, 0x4D, 0x00]; // ESC M 0 - Select Font A

      // Or try alternative font selection
      // bytes += [0x1B, 0x21, 0x00]; // ESC ! 0 - Reset font to default

      // ----------------- HEADER SECTION -----------------
      // "Running Table" - centered, normal size
      bytes += generator.text('Running Table', styles: PosStyles(
        align: PosAlign.center,
        bold: false,
        height: PosTextSize.size1,
        width: PosTextSize.size2,
      ));

      // "KOT" - centered, bold
      bytes += generator.text('KOT', styles: PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size1,
        width: PosTextSize.size2,
      ));

      // Date and time - centered
      bytes += generator.text(dateTimeFormatted, styles: PosStyles(
        align: PosAlign.center,
        bold: false,
        height: PosTextSize.size1,
        width: PosTextSize.size2,
      ));

      // KOT number - centered
      bytes += generator.text('KOT - $kotNo', styles: PosStyles(
        align: PosAlign.center,
        bold: false,
        height: PosTextSize.size1,
        width: PosTextSize.size2,
      ));


      // "Dine In" - centered, bold
      bytes += generator.text('Dine In', styles: PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size1,
        width: PosTextSize.size2,
      ));


      // Table number - centered, bold
      String sectionNameClean = sectionName.replaceAll(RegExp(r'\s+'), '').trim(); // remove spaces in section part if you prefer
      String tablePart;
      if (tableNo.isNotEmpty && sectionName.isNotEmpty) {
        // Combine with a hyphen as requested
        tablePart = 'Table No: ${sectionName}-${tableNo}';
      } else if (tableNo.isNotEmpty) {
        tablePart = 'Table No: $tableNo';
      } else {
        tablePart = 'Table No: N/A';
      }

      bytes += generator.text(tablePart, styles: PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size1,
        width: PosTextSize.size2,
      ));

      // Dotted line separator
      bytes += generator.text('.' * 48);

      // Captain/Server name - left aligned, normal
      if (server.isNotEmpty) {
        bytes += generator.text('Captain: ${server.toUpperCase()}', styles: PosStyles(
          align: PosAlign.left,
          bold: false,
        ));
        // keep a single dotted line here if you want separation after server:
        bytes += generator.text('.' * 48);
      }

      // ----------------- ITEMS TABLE HEADER -----------------
      // Create a proper 3-column header like PetPooja
      String headerLine = 'Item'.padRight(27) +
          'Special Note'.padRight(14) +
          'Qty.'.padLeft(7);

      bytes += generator.text(headerLine, styles: PosStyles(
        align: PosAlign.left,
        bold: false,
      ));

      // ----------------- ITEMS -----------------
      List<String> _chunks(String s, int width) {
        final List<String> out = [];
        if (s.isEmpty) {
          return [''];
        }
        int i = 0;
        while (i < s.length) {
          int end = (i + width < s.length) ? i + width : s.length;
          out.add(s.substring(i, end));
          i = end;
        }
        return out;
      }

      for (int idx = 0; idx < items.length; idx++) {
        final it = items[idx];
        final name = (it['name'] ?? '').toString().trim();
        final note = (it['note'] ?? '').toString().trim();
        final qty = (it['qty'] ?? '1').toString().trim();

        // Break name/note into chunks matching columns
        final nameChunks = _chunks(name, 27);
        final noteChunks = _chunks(note, 14);
        final maxLines = [nameChunks.length, noteChunks.length].reduce((a, b) => a > b ? a : b);

        for (int line = 0; line < maxLines; line++) {
          final namePart = (line < nameChunks.length) ? nameChunks[line] : '';
          final notePart = (line < noteChunks.length) ? noteChunks[line] : '';

          if (line == 0) {
            final nameField = namePart.padRight(27);
            final noteField = notePart.padRight(14);
            final qtyField = qty.padLeft(7);
            final outLine = nameField + noteField + qtyField;
            bytes += generator.text(outLine, styles: PosStyles(
              align: PosAlign.left,
              bold: true,
              height: PosTextSize.size1,
              width: PosTextSize.size2,
            ));
          } else {
            final nameField = namePart.padRight(27);
            final noteField = notePart.padRight(14);
            final qtyField = ''.padLeft(7);
            final outLine = nameField + noteField + qtyField;
            bytes += generator.text(outLine, styles: PosStyles(
              align: PosAlign.left,
              bold: false,
              height: PosTextSize.size1,
              width: PosTextSize.size2,
            ));
          }
        }
      }

      // Add a single dotted separator after all items (if desired)
      bytes += generator.text('.' * 48);


      // ----------------- TOTAL -----------------
      final totalQty = items.fold<int>(
        0,
        (acc, it) => acc + (int.tryParse(it['qty'] ?? '0') ?? 0),
      );

      // Total items line - right aligned
      bytes += generator.text('Total Qty: $totalQty', styles: PosStyles(
        align: PosAlign.right,
        bold: false,
      ));

      // Final spacing
      bytes += generator.feed(1);

      // Cut the paper
      try {
        bytes += generator.cut();
      } catch (_) {
        bytes += generator.feed(5);
      }
      
      // SEND TO PRINTER
      final result = await UsbPrinter.printRawBytes(
        vendorId: vendor,
        productId: product,
        bytes: Uint8List.fromList(bytes),
        timeoutMillis: 5000,
      );

      _addDebugLog(
        'KOT printed (native result=$result) for order ${orderData['id']}',
      );
      // showTopNotification(
      //   context,
      //   'Printed',
      //   'KOT ${orderData['id']} printed.',
      // );
    } catch (e, st) {
      _addDebugLog('Print error for order ${orderData['id']}: $e');
      _addDebugLog('STACK: $st');
      showTopNotification(context, 'Print Error', e.toString());
    } finally {
      setState(() => isPrinting = false);
    }
  }

  void _ensureShiftedOrdersIndependent(List<Map<String, dynamic>> ordersList) {
  for (var order in ordersList) {
    final kotNumber = order['kotNumber']?.toString() ?? '';
    
    // If KOT contains _SHIFTED but flags are missing, add them
    if (kotNumber.contains('_SHIFTED')) {
      if (order['is_shifted'] != true) {
        _addDebugLog('⚠️ Found shifted order without flags, fixing: $kotNumber');
        order['is_shifted'] = true;
        order['skipConsolidation'] = true;
        order['isShifted'] = true;
      }
      
      // Extract original KOT if missing
      if (order['original_kot_number'] == null) {
        try {
          final originalKot = kotNumber.split('_SHIFTED')[0];
          order['original_kot_number'] = originalKot;
          _addDebugLog('   Inferred original KOT: $originalKot');
        } catch (e) {
          _addDebugLog('   Could not extract original KOT: $e');
        }
      }
    }
  }
}

  // ----------------- fetchOrders (populates caches) -----------------
  // Replace your existing fetchOrders method with this updated version

Future<void> fetchOrders() async {
  Timer? timeoutTimer;
  
  try {
    setState(() {
      isLoading = true;
      hasErrorOccurred = false;
    });

    timeoutTimer = Timer(const Duration(seconds: 10), () {
      debugPrint("❌ FETCH ORDERS TIMEOUT");
      if (mounted) {
        setState(() {
          isLoading = false;
          hasErrorOccurred = true;
        });
      }
    });

    final apiUrl = dotenv.env['API_URL'];
    if (apiUrl == null || apiUrl.isEmpty) {
      throw Exception("API_URL not configured");
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwtToken');
    if (token == null || token.isEmpty) {
      throw Exception("No JWT token found");
    }

    final decodedToken = JwtDecoder.decode(token);
    userRole = decodedToken['role'] ?? '';

    final response = await http.get(
      Uri.parse('$apiUrl/drinks-orders'),
      headers: {
        'Content-Type': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    ).timeout(const Duration(seconds: 8));

    if (timeoutTimer?.isActive ?? false) {
      timeoutTimer!.cancel();
    }

    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(response.body);
      print("✅ Fetched ${data.length} orders from API");
      print("Raw Orders Data: $data");
      final ist = tz.getLocation('Asia/Kolkata');

      // ✅ Group orders by KOT number to detect shifts
      Map<int, List<Map<String, dynamic>>> ordersByKot = {};

      List<Map<String, dynamic>> ordersWithItems = [];

      for (final order in data) {
        try {
          final user = order['user'];
          final section = order['table']?['section'];
          final drink = order['drink'];
          final table = order['table'];
          
          final createdAtUtc = DateTime.tryParse(order['createdAt']?.toString() ?? '') ?? DateTime.now().toUtc();
          final createdAtIst = tz.TZDateTime.from(createdAtUtc, ist);

          final serverName = (user != null && user['name'] != null) ? user['name'].toString() : 'Unknown';
          final statusFormatted = _normalizeStatus(order['status']);

          int orderKotNumber = 0;
          try {
            final rawKot = order['kotNumber'] ?? order['kotNo'] ?? order['kot'];
            if (rawKot != null) {
              orderKotNumber = int.tryParse(rawKot.toString()) ?? 0;
            }
          } catch (_) {
            orderKotNumber = 0;
          }

          // ✅ Extract shift metadata from API response
          final shiftedFrom = order['shifted_from_table']?.toString() ?? '';
          final originalTableNumber = order['original_table_number']?.toString() ?? '';
          final originalSectionName = order['original_section_name']?.toString() ?? '';

          // ✅ FIX: Mark as shifted if the DB column is non-empty, regardless of
          // whether other orders share the same KOT at a different location.
          final isShifted = shiftedFrom.isNotEmpty || originalTableNumber.isNotEmpty;

          // ✅ Use table.display_number if available
          final displayNumber = table != null 
              ? (order['table_display_name']?.toString() ?? table['display_number']?.toString() ?? order['restaurent_table_number']?.toString() ?? '')
              : (order['restaurent_table_number']?.toString() ?? '');

          final itemEntry = {
            "item_name": drink != null ? drink['name'].toString() : (order['item_desc']?.toString() ?? 'Unknown Item'),
            "quantity": order['quantity']?.toString() ?? '1',
            "price": order['amount']?.toString() ?? '0',
            "item_desc": order['item_desc']?.toString() ?? '',
            "orderItem": order,
            "menu": drink,
            "order_item_id": order['id']?.toString(),
            "kotNumber": orderKotNumber,
          };

          final orderId = order['id'].toString();
          
          Map<String, dynamic> orderEntry = {
            "id": orderId,
            "kotNumber": orderKotNumber,
            "serverId": order['userId']?.toString() ?? '',
            "table_number": order['table_number']?.toString() ?? '',
            "amount": order['amount']?.toString() ?? '0',
            "quantity": order['quantity']?.toString() ?? '1',
            "item_desc": order['item_desc']?.toString() ?? '',
            "restaurent_table_number": displayNumber,
            "server": serverName,
            "time": DateFormat('hh:mm a').format(createdAtIst),
            "section_name": section != null ? section['name'].toString() : "Section Not Found",
            "item_name": drink != null ? drink['name'].toString() : (order['item_desc']?.toString() ?? 'Unknown Item'),
            "status": statusFormatted,
            "items": [itemEntry],
            "createdAt": order['createdAt'],
            "isShifted": isShifted,
            "shifted_from_table": shiftedFrom,
            "original_table_number": originalTableNumber,
            "original_section_name": originalSectionName,
          };

          // ✅ Group by KOT to detect multiple tables with same KOT (shifts)
          if (orderKotNumber != 0) {
            ordersByKot.putIfAbsent(orderKotNumber, () => []);
            ordersByKot[orderKotNumber]!.add(orderEntry);
          } else {
            ordersWithItems.add(orderEntry);
          }
          
        } catch (e) {
          debugPrint("❌ Error processing order ${order['id']}: $e");
        }
      }

      // ✅ Process grouped orders to create separate cards for shifted orders
      for (var entry in ordersByKot.entries) {
        final kotNumber = entry.key;
        final kotOrders = entry.value;

        if (kotOrders.isEmpty) continue;

        // Group by table location
        Map<String, List<Map<String, dynamic>>> ordersByTable = {};
        
        for (var order in kotOrders) {
          final tableKey = '${order['section_name']}_${order['restaurent_table_number']}';
          ordersByTable.putIfAbsent(tableKey, () => []);
          ordersByTable[tableKey]!.add(order);
        }

        // If multiple table locations exist for same KOT, mark as shifted
        if (ordersByTable.length > 1) {
          // Find the "from" table (earliest created order)
          DateTime? earliestTime;
          String? fromTable;
          String? fromSection;
          String? fromTableNumber;
          
          for (var tableEntry in ordersByTable.entries) {
            for (var order in tableEntry.value) {
              try {
                final orderTime = DateTime.parse(order['createdAt'].toString());
                if (earliestTime == null || orderTime.isBefore(earliestTime)) {
                  earliestTime = orderTime;
                  fromTable = tableEntry.key;
                  fromSection = order['section_name']?.toString();
                  fromTableNumber = order['restaurent_table_number']?.toString();
                }
              } catch (_) {}
            }
          }

          // Mark shifted orders
          for (var tableEntry in ordersByTable.entries) {
            final tableKey = tableEntry.key;
            final tableOrders = tableEntry.value;
            
            // Calculate if this is a shifted location
            final isShiftedLocation = (fromTable != null && tableKey != fromTable);
            
            if (isShiftedLocation && fromTable != null) {
              // This is a shifted order - create consolidated card
              final fromTableDisplay = '$fromSection - Table $fromTableNumber';
              
              // Collect all items
              List<Map<String, dynamic>> allItems = [];
              int totalAmount = 0;
              int totalQuantity = 0;
              
              for (var order in tableOrders) {
                allItems.addAll(_normalizeItems(order['items']));
                totalAmount += int.tryParse(order['amount']?.toString() ?? '0') ?? 0;
                totalQuantity += int.tryParse(order['quantity']?.toString() ?? '0') ?? 0;
              }
              
              final baseOrder = tableOrders.first;
              final shiftedOrder = {
                ...baseOrder,
                'id': '${kotNumber}_SHIFTED_${tableKey}',
                'kotNumber': kotNumber,
                'items': allItems,
                'amount': totalAmount.toString(),
                'quantity': totalQuantity.toString(),
                'item_name': _createItemNameSummary(allItems),
                'isShifted': true,
                'shifted_from_table': fromTableDisplay,
                'skipConsolidation': true,
                'orderCount': tableOrders.length,
                'originalOrders': tableOrders,
              };
              
              ordersWithItems.add(shiftedOrder);
            } else {
              // Original location — but individual orders may still have
              // shifted_from_table set in the DB, so preserve that flag.
              for (var o in tableOrders) {
                final dbShiftedFrom = o['shifted_from_table']?.toString() ?? '';
                if (dbShiftedFrom.isNotEmpty) {
                  o['isShifted'] = true; // ✅ Restore badge from DB value
                }
                ordersWithItems.add(o);
              }
            }
          }
        } else {
          // Single location — still check if individual orders were shifted
          for (var o in kotOrders) {
            final dbShiftedFrom = o['shifted_from_table']?.toString() ?? '';
            if (dbShiftedFrom.isNotEmpty) {
              o['isShifted'] = true; // ✅ Restore badge from DB value
            }
            ordersWithItems.add(o);
          }
        }
      }

      if (mounted) {
        setState(() {
          orders = ordersWithItems;
          isLoading = false;
          hasErrorOccurred = false;
        });
      }
    } else {
      throw Exception("HTTP ${response.statusCode}");
    }

  } catch (e, stackTrace) {
    debugPrint("❌ FETCH ORDERS ERROR: $e");
    debugPrint("Stack trace: $stackTrace");
    if (mounted) {
      setState(() {
        isLoading = false;
        hasErrorOccurred = true;
      });
    }
  } finally {
    if (timeoutTimer?.isActive ?? false) {
      timeoutTimer!.cancel();
    }
  }
}


// Add this helper method to clear cached shift metadata:
void _clearShiftMetadata(String orderId) {
  _shiftMetadataCache.remove(orderId);
  debugPrint("Cleared shift metadata for order $orderId");
}

// Update your _completeOrder method to clear metadata:
Future<void> _completeOrder(String kotNumber, [Map<String, dynamic>? order]) async {
  final url = Uri.parse('${dotenv.env['API_URL']}/drinks-orders/complete');
  try {
    debugPrint("=== COMPLETE ORDER (kot-only) DEBUG ===");
    debugPrint("KOT Number: $kotNumber");

    final requestBody = {'kotNumber': kotNumber};
    debugPrint("Request Body: ${jsonEncode(requestBody)}");

    final response = await http.put(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(requestBody),
    );

    if (response.statusCode == 200) {
      final responseData = jsonDecode(response.body);
      debugPrint("KOT $kotNumber completed successfully.");
      
      // ✅ NEW: Clear shift metadata for this order
      if (order != null) {
        final orderId = order['id']?.toString();
        if (orderId != null && orderId.contains('_SHIFTED_')) {
          // Extract original order ID
          final originalId = orderId.split('_SHIFTED_')[0];
          _clearShiftMetadata(originalId);
        }
      }
    } else {
      debugPrint("❌ FAILED TO COMPLETE KOT $kotNumber");
      try {
        final errorData = jsonDecode(response.body);
        debugPrint("Error message: ${errorData['message']}");
      } catch (_) {}
    }
  } catch (e) {
    debugPrint("❌ EXCEPTION in _completeOrder: $e");
  }
}

  // ----------------- Send notification -----------------

  Future<void> sendTableNotification({
    required String userId,
    required String tableNumber,
  }) async {
    try {
      final url = Uri.parse('${dotenv.env['API_URL']}/notify-user/');

      final body = {
        'userId': userId,
        'title': 'Order Ready for table ${tableNumber}',
        'message': 'Pick your order',
      };

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        debugPrint('✅ Notification sent successfully');
      } else {
        final error = jsonDecode(response.body);
        debugPrint('❌ Failed to send notification: ${error['message']}');
      }
    } catch (e) {
      debugPrint('❌ Error sending table notification: $e');
    }
  }




@override
void dispose() {
  _kotShiftOverlay?.remove();
  _kotShiftOverlay = null;
  socket?.dispose();
  _logScrollController.dispose();
  super.dispose();
}




  // ----------------- Printer Status Indicator -----------------
Widget _buildPrinterStatusIndicator() {
  final bool isConnected = selectedPrinter != null;
  
  return GestureDetector(
    onTap: () {
      if (!isConnected && !isScanning) {
        _scanForPrinters();
      }
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isConnected ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isConnected ? Colors.green.shade300 : Colors.red.shade300,
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Status dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isConnected ? Colors.green : Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          // Status text
          Text(
            isConnected ? 'Connected' : 'Disconnected',
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isConnected ? Colors.green.shade700 : Colors.red.shade700,
            ),
          ),
          // Retry button for disconnected state
          if (!isConnected) ...[
            const SizedBox(width: 6),
            if (isScanning)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.red.shade700),
                ),
              )
            else
              Icon(
                Icons.refresh,
                size: 14,
                color: Colors.red.shade700,
              ),
          ],
        ],
      ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return WillPopScope(
      onWillPop: () async => false, // Disable back button
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F5F2),
        drawer: const Sidebar(),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF8F5F2),
          elevation: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Text(
                'Drinks Orders',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Manage restaurant orders',
                style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 7),
            ],
          ),
          actions: [
            _buildPrinterStatusIndicator(),
            const SizedBox(width: 16),
          ],
        ),
        body:
            isLoading
                ? Center(
                  child: LoadingAnimationWidget.staggeredDotsWave(
                    color: Colors.black,
                    size: 40,
                  ),
                )
                : hasErrorOccurred
                ? _buildErrorWidget()
                : LayoutBuilder(
                  builder: (context, constraints) {
                    // Responsive breakpoint (e.g., 800px)
                    if (constraints.maxWidth > 800) {
                      return _buildDesktopLayout(); // Kitchen screen layout
                    } else {
                      return _buildMobileLayout(); // Keep existing design
                    }
                  },
                ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
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
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Please check your connection or try again.",
            style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                isLoading = true;
                hasErrorOccurred = false;
              });
              fetchOrders(); // Retry fetch
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
              backgroundColor: Color(0xFF2563EB),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 16, left: 20, right: 20),
      child: Column(
        children: [
          const SizedBox(height: 12),
          _buildSearchBar(),
          const SizedBox(height: 12),
          _buildCategoryFilter(),
          if (userRole == 'Admin') _buildAddItemButton(context),
          ..._buildOrderCards(), // same as before
        ],
      ),
    );
  }


Widget _buildDesktopLayout() {
  // First filter orders
  List<Map<String, dynamic>> filteredOrders = orders.where((order) {
    // ✅ FIXED: Proper category filtering including Completed
    bool matchesCategory;
    if (selectedCategory == "All") {
      // Show all non-completed orders
      matchesCategory = order["status"] != "Completed";
    } else if (selectedCategory == "Completed") {
      // Show only completed orders
      matchesCategory = order["status"] == "Completed";
    } else {
      // Show specific status (Pending, Accepted)
      matchesCategory = order["status"] == selectedCategory;
    }
    
    final searchText = searchController.text.trim().toLowerCase();
    bool matchesSearch = searchText.isEmpty ||
        (order["id"]?.toString().toLowerCase().contains(searchText) ?? false) ||
        (order["kotNumber"]?.toString().toLowerCase().contains(searchText) ?? false) ||
        (order["server"]?.toString().toLowerCase().contains(searchText) ?? false) ||
        (order["section_name"]?.toString().toLowerCase().contains(searchText) ?? false) ||
        (order["restaurent_table_number"]?.toString().toLowerCase().contains(searchText) ?? false);
    return matchesCategory && matchesSearch;
  }).toList();
  
  // Group by kotNumber
  final groupedOrders = _groupOrdersByKotNumber(filteredOrders);
  
  // Create consolidated orders
  final consolidatedOrders = _createConsolidatedOrders(groupedOrders);

  return Padding(
    padding: const EdgeInsets.all(24),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search + Category
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: _buildSearchBar(dense: true),
                ),
              ),
              Expanded(
                flex: 2,
                child: _buildCategoryFilter(dense: true),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Top Item Groups
          _buildTopItemGroupsRow(context),

          const SizedBox(height: 12),

          // Grid of consolidated orders
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: consolidatedOrders.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 20,
              mainAxisSpacing: 20,
              childAspectRatio: 1.8,
            ),
            itemBuilder: (context, index) {
              return _buildOrderCard(consolidatedOrders[index]);
            },
          ),
        ],
      ),
    ),
  );
}


  void _updateOrderStatus(Map<String, dynamic> order, String newStatus) {
    setState(() {
      order["status"] = newStatus;
    });
  }

  Widget _buildCategoryFilter({bool dense = false}) {
  return Container(
    padding: EdgeInsets.symmetric(
      vertical: dense ? 4 : 8,
      horizontal: dense ? 8 : 10,
    ),
    decoration: BoxDecoration(
      color: const Color(0xFFEDEBE9),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: categories.map((category) {
            bool isSelected = selectedCategory == category;
            return GestureDetector(
              onTap: () => setState(() => selectedCategory = category),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: isSelected ? Color(0xFFFCFAF8) : Color(0xFFEDEBE9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  category,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isSelected
                        ? const Color(0xFF1C1917)
                        : const Color(0xFF78726D),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    ),
  );
}

Future<void> _acceptOrder(String kotNumber, [Map<String, dynamic>? order]) async {
  final url = Uri.parse('${dotenv.env['API_URL']}/drinks-orders/accept'); // use a generic accept endpoint or keep original path if needed
  try {
    debugPrint("=== ACCEPT ORDER (kot-only) DEBUG ===");
    debugPrint("KOT Number: $kotNumber");
    debugPrint("Request URL: $url");
    debugPrint("Request Method: PUT");

    final requestBody = {
      'kotNumber': kotNumber,
    };

    debugPrint("Request Body: ${jsonEncode(requestBody)}");

    final response = await http.put(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(requestBody),
    );

    debugPrint("Response Status: ${response.statusCode}");
    debugPrint("Response Body: ${response.body}");

    if (response.statusCode == 200) {
      final responseData = jsonDecode(response.body);
      debugPrint("KOT $kotNumber accepted successfully.");
      debugPrint("Backend response: ${responseData['message'] ?? 'No message'}");
    } else {
      debugPrint("❌ FAILED TO ACCEPT KOT $kotNumber");
      try {
        final errorData = jsonDecode(response.body);
        debugPrint("Error message: ${errorData['message']}");
        if ((response.statusCode == 400 || response.statusCode == 404) && context.mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              showTopNotification(context, 'Cannot Accept KOT', errorData['message'] ?? 'Error accepting order');
            }
          });
        }
      } catch (parseError) {
        debugPrint("Could not parse error response: $parseError");
      }
    }
  } catch (e) {
    debugPrint("❌ EXCEPTION in _acceptOrder (kot-only): $e");
    if (context.mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) showTopNotification(context, 'Error', 'Failed to accept order');
      });
    }
  }
}



// FIXED _buildActionButtons FOR DRINKS ORDERS
// Replace the entire _buildActionButtons method (around line 950) with this:

Widget _buildActionButtons(
  BuildContext context,
  Map<String, dynamic> order,
  String primaryAction,
) {
  IconData primaryIcon =
      primaryAction == "Accepted" ? Icons.access_time : Icons.done_all;
  print('-->>${order}');
  return Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      SizedBox(
        width: 240,
        height: 70,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await Future.delayed(Duration.zero);

              try {
                final kotNo = order['kotNumber']?.toString() ?? order['id']?.toString() ?? '';
                
                if (primaryAction == "Accepted") {
                  // ✅ Don't print here - already auto-printed when order arrived
                  // Just update status
                  await _acceptOrder(kotNo, order);
                  
                } else if (primaryAction == "Completed") {
                  await _completeOrder(kotNo, order);
                }

                _updateOrderStatus(order, primaryAction);

                if (context.mounted) {
                  _showSuccessSnackBar(
                    message:
                        "Status Updated to $primaryAction for ${order['table_number']}",
                  );
                }

                // ✅ REMOVED: All printing logic for "Accepted" action
                // The KOT will only be printed automatically when the order first arrives via socket

              } catch (e, st) {
                _addDebugLog(
                    'Error handling button action ($primaryAction) for order ${order['id']}: $e');
                _addDebugLog('STACK: $st');
                if (context.mounted) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (context.mounted) {
                      showTopNotification(
                          context, 'Error', 'Failed to update status: ${e.toString()}');
                    }
                  });
                }
              }
            },
            icon: Icon(primaryIcon, color: Colors.white),
            label: Text(
              primaryAction,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
              elevation: 2,
            ),
          ),
        ),
      ),
    ],
  );
}


Widget _buildSearchBar({bool dense = false}) {
  return SizedBox(
    height: dense ? 48 : MediaQuery.of(context).size.width * 0.14,
    child: TextField(
      controller: searchController,
      decoration: InputDecoration(
        hintText: "Search by KOT number, server name...", // Updated hint text
        prefixIcon: Icon(Icons.search),
        filled: true,
        fillColor: Color(0xFFFCFAF8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: const Color.fromARGB(255, 141, 140, 140),
            width: 1.8,
          ),
        ),
        contentPadding: EdgeInsets.symmetric(
          vertical: dense ? 10 : 14,
          horizontal: 16,
        ),
      ),
      onChanged: (query) => setState(() {}),
    ),
  );
}


  /// Unified Success SnackBar
  void _showSuccessSnackBar({required String message}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(fontWeight: FontWeight.bold), // Make text bold
        ),
        backgroundColor: Colors.green,
      ),
    );
  }




// Individual item card with complete button
Widget _buildItemCardWithCompleteButton(
  Map<String, dynamic> item,
  Map<String, dynamic> parentOrder,
  List<Map<String, dynamic>> allItems,
  Function(VoidCallback) setDialogState,
) {
  String itemName = '';
  String quantity = '';
  String itemDesc = '';
  String itemId = '';

  print("\n\n🧩 Item Debug: $item\n\n");

  // --- Extract item name ---
  if (item['item_name'] != null &&
      item['item_name'].toString().trim().isNotEmpty &&
      item['item_name'].toString() != 'null') {
    itemName = item['item_name'].toString();
  } else if (item['item_desc'] != null &&
      item['item_desc'].toString().trim().isNotEmpty) {
    itemName = item['item_desc'].toString();
  } else if (item['menu'] is Map && item['menu']['name'] != null) {
    itemName = item['menu']['name'].toString();
  } else if (item['drinkMenu'] is Map && item['drinkMenu']['name'] != null) {
    itemName = item['drinkMenu']['name'].toString();
  } else if (item.containsKey('name') && item['name'] != null) {
    itemName = item['name'].toString();
  } else {
    itemName = 'Unnamed Drink';
  }

  // --- Extract quantity ---
  quantity = (item['quantity'] ??
          item['orderItem']?['quantity'] ??
          item['qty'] ??
          '1')
      .toString();

  // --- Extract description ---
  itemDesc =
      (item['item_desc'] ?? item['orderItem']?['desc'] ?? '').toString();

  // --- Extract item ID ---
  try {
  final originalOrders = parentOrder['originalOrders'];
  
  if (originalOrders is List && originalOrders.isNotEmpty) {
    for (var originalOrder in originalOrders) {
      if (originalOrder is Map) {
        final origItemName = (originalOrder['item_name']?.toString() ?? '').trim();
        final origItemDesc = (originalOrder['item_desc']?.toString() ?? '').trim();
        final origQty = (originalOrder['quantity']?.toString() ?? '').trim();

        bool nameMatches = false;
        if (origItemName.isNotEmpty && origItemName == itemName) {
          nameMatches = true;
        } else if (origItemDesc.isNotEmpty && (origItemDesc == itemName || origItemDesc == itemDesc)) {
          nameMatches = true;
        }

        bool qtyMatches = (origQty == quantity);

        if (nameMatches && qtyMatches) {
          itemId = originalOrder['id']?.toString() ?? '';
          if (itemId.isNotEmpty) {
            debugPrint('✅ Found matching ID from originalOrders: $itemId'); // Just print
            break;
          }
        }
      }
    }
  }
  
  if (itemId.isEmpty && item['orderItem'] is Map) {
    itemId = item['orderItem']['orderId']?.toString() ?? '';
    if (itemId.isNotEmpty) {
      debugPrint('✅ Found ID from item.orderItem: $itemId');
    }
  }
  
  if (itemId.isEmpty) {
    itemId = (item['id'] ?? item['order_item_id'] ?? '').toString();
    if (itemId.isNotEmpty) {
      debugPrint('⚠️ Using fallback ID: $itemId');
    }
  }
} catch (e) {
  debugPrint('❌ Error extracting item ID: $e');
  itemId = '';
}

if (itemId.isEmpty) {
  debugPrint('⚠️ WARNING: No valid ID found for item: $itemName');
}

  // if (itemId.isEmpty) {
  //   itemId = (item['id'] ?? item['orderItem']?['orderId'] ?? '').toString();
  // }

  // --- Detect duplicate note ---
  bool isDuplicateNote = false;
  if (itemDesc.isNotEmpty) {
    final nameLower = itemName.toLowerCase().trim();
    final descLower = itemDesc.toLowerCase().trim();
    if (nameLower == descLower) {
      isDuplicateNote = true;
    } else if (nameLower.contains(descLower) ||
        descLower.contains(nameLower)) {
      final shorter =
          nameLower.length < descLower.length ? nameLower : descLower;
      final longer =
          nameLower.length >= descLower.length ? nameLower : descLower;
      if (shorter.length >= longer.length * 0.7) {
        isDuplicateNote = true;
      }
    }
  }

  bool isCustom = item is Map &&
      (item['is_custom'] == true ||
          item['is_custom'] == 'true' ||
          (item['orderItem'] is Map &&
              (item['orderItem']['is_custom'] == true ||
                  item['orderItem']['is_custom'] == 'true')));

  // --- UI card layout ---
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.grey.shade400),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    itemName,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Quantity: $quantity",
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w500,
                      fontSize: 11,
                    ),
                  ),
                  if (itemDesc.isNotEmpty && !isDuplicateNote && !isCustom) ...[
                    const SizedBox(height: 8),
                    Text(
                      "Note: $itemDesc",
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w500,
                        fontSize: 10,
                        color: const Color.fromARGB(255, 196, 49, 49),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Buttons
            Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                // Reprint
                SizedBox(
                  width: 100,
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final itemForPrint =
                          Map<String, dynamic>.from(parentOrder);
                      itemForPrint['items'] = [item];
                      itemForPrint['item_name'] = itemForPrint['item_name'] ?? itemName;
                      itemForPrint['quantity'] = quantity;
                      itemForPrint['item_desc'] = itemDesc;

                      await _reprintKOT(itemForPrint);

                      if (context.mounted) {
                        showTopNotification(
                          context,
                          'Item Printed',
                          '$itemName KOT printed',
                        );
                      }
                    },
                    icon: const Icon(Icons.print, size: 12, color: Colors.white),
                    label: Text(
                      'Print',
                      style: GoogleFonts.poppins(
                        fontSize: 8,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[600],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // ✅ Complete button
                if (parentOrder['status'] == 'Accepted')
                  SizedBox(
                    width: 100,
                    height: 40,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        try {
                          final url = Uri.parse('${dotenv.env['API_URL']}/drinks-orders/$itemId/complete');

                          debugPrint("=== COMPLETE DRINK ITEM DEBUG ===");
                          debugPrint("Item ID: $itemId");
                          debugPrint("Item Name: $itemName");
                          debugPrint("Quantity: $quantity");
                          debugPrint("Request URL: $url");

                          final response = await http.put(
                            url,
                            headers: {'Content-Type': 'application/json'},
                            body: jsonEncode({
                              'itemId': itemId,
                              'itemName': itemName,
                              'quantity': quantity,
                            }),
                          );

                          if (response.statusCode == 200) {
                            _addDebugLog('Item $itemId completed successfully. Removing from UI...');

                            // Remove the item from allItems
                            allItems.removeWhere((it) => _itemMatchesId(it, itemId));

                            setState(() {
                              // Also remove from parentOrder originalOrders if exists
                              if (parentOrder['originalOrders'] is List) {
                                parentOrder['originalOrders'].removeWhere((it) => _itemMatchesId(it, itemId));
                              }

                              // Remove from main orders list if needed
                              for (int i = 0; i < orders.length; i++) {
                                final order = orders[i];
                                if (_normalizeItems(order['items']).any((it) => _itemMatchesId(it, itemId))) {
                                  order['items'].removeWhere((it) => _itemMatchesId(it, itemId));
                                  if ((order['items'] as List).isEmpty) {
                                    orders.removeAt(i);
                                    i--;
                                  }
                                }
                              }
                            });

                            // If all items are completed, close modal first, then show notification
                            if (allItems.isEmpty) {
                              _addDebugLog('All items completed. Closing dialog immediately...');
                              if (context.mounted) {
                                WidgetsBinding.instance.addPostFrameCallback((_) async {
                                  if (context.mounted) {
                                    try {
                                      await Navigator.of(context, rootNavigator: false).maybePop();
                                      if (context.mounted) {
                                        showTopNotification(
                                          context,
                                          'Item Completed',
                                          '$itemName marked as complete',
                                        );
                                      }
                                    } catch (e) {
                                      _addDebugLog('Error closing dialog: $e');
                                    }
                                  }
                                });
                              }
                            } else {
                              // Otherwise just update dialog
                              setDialogState(() {});
                            }
                          } else {
                            try {
                              final errorData = jsonDecode(response.body);
                              showTopNotification(
                                context,
                                'Error',
                                errorData['message'] ?? 'Failed to complete item',
                              );
                            } catch (_) {
                              showTopNotification(
                                context,
                                'Error',
                                'Failed to complete item (HTTP ${response.statusCode})',
                              );
                            }
                          }
                        } catch (e, st) {
                          _addDebugLog('Exception in item complete: $e\nSTACK: $st');
                          showTopNotification(context, 'Error', 'Failed to complete: $e');
                        }
                      },

                      icon: const Icon(Icons.done_all, size: 12, color: Colors.white),
                      label: Text(
                        'Done',
                        style: GoogleFonts.poppins(
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[600],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ],
    ),
  );
}


// New widget to display items with individual complete buttons
Widget _buildOrderItemsWithCompleteButtons(
  List<Map<String, dynamic>> items,
  Map<String, dynamic> parentOrder,
  Function(VoidCallback) setDialogState,
) {

  print("\n\nItems: $items\n\n");
  print("\n\nparentOrder: $parentOrder\n\n");

  if (items.isEmpty) {
    // Fallback: if top-level fields exist, show them
    final singleName = parentOrder['item_name']?.toString() ?? parentOrder['item_desc']?.toString() ?? '';
    final singleQty = parentOrder['quantity']?.toString() ?? '';
    final singleDesc = parentOrder['item_desc']?.toString() ?? '';

    if (singleName.isEmpty && singleQty.isEmpty && singleDesc.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text('No items available', style: GoogleFonts.poppins()),
      );
    }

    return _buildItemCardWithCompleteButton(
      {
        'item_name': singleName,
        'quantity': singleQty,
        'item_desc': singleDesc,
      },
      parentOrder,
      items,
      setDialogState,
    );
  }

  return Column(
    children: items.asMap().entries.map((entry) {
      final item = entry.value;
      return _buildItemCardWithCompleteButton(item, parentOrder, items, setDialogState);
    }).toList(),
  );
}




// REPLACE the existing _showOrderDetails method with this updated version:
void _showOrderDetails(BuildContext context, Map<String, dynamic> order) {
  _addDebugLog("\n\n Printing Order: ${order.toString()}\n\n");
  _addDebugLog("\n\n Printing order['items']: ${order['items'].toString()}\n\n");
  // _addDebugLog("\n\n Printing: ${order['items'].toString()}\n\n");
  // _addDebugLog("\n\n Printing: ${order['items'].toString()}\n\n");
  
  // Create a mutable copy of items for this dialog
  List<Map<String, dynamic>> dialogItems = [];
  final rawItems = order['items'];
  dialogItems = _normalizeItems(rawItems);
  
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final status = (order["status"] ?? "").toString().toLowerCase();
          final kotNumber = order['kotNumber']?.toString() ?? order['id']?.toString() ?? 'N/A';

          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border.all(color: Colors.grey, width: 1),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        "Order Details",
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const Divider(),
                  const SizedBox(height: 12),
                  _buildDetailRow("KOT Number", 'KOT #$kotNumber'),
                  _buildDetailRow("Section", order["section_name"]?.toString() ?? "N/A"),
                  _buildDetailRow("Table", order["restaurent_table_number"]?.toString() ?? "N/A"),
                  _buildDetailRow("Server", order["server"]?.toString() ?? "N/A"),
                  _buildDetailRow("Time", order["time"]?.toString() ?? "N/A"),
                  _buildDetailRow("Status", order["status"]?.toString() ?? "N/A"),
                  
                  if (order['orderCount'] != null && order['orderCount'] > 1)
                    _buildDetailRow("Orders Grouped", "${order['orderCount']} orders"),
                  
                  const SizedBox(height: 16),
                  
                  // Common Accept Button (only if status is Pending)
                  if (status == "pending")
                    Center(
                      child: SizedBox(
                        width: 240,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final kotNo = order['kotNumber']?.toString() ?? order['id']?.toString() ?? '';
                            final kotNumberInt = _extractKotNumberAsInt(order);
                            
                            // ✅ Check if already printed (should be for new orders)
                            if (!printedKOTs.contains(kotNumberInt)) {
                              // Not printed yet - print now (fallback for manual orders or print failures)
                              _addDebugLog('Manual accept - printing drinks KOT $kotNo');
                              printedKOTs.add(kotNumberInt);
                              await _printOrderNative(order).catchError((e) {
                                _addDebugLog('Manual print error: $e');
                                printedKOTs.remove(kotNumberInt);
                              });
                            }
                            
                            // Update status
                            await _acceptOrder(kotNo, order);
                            
                            if (context.mounted) {
                              setDialogState(() {
                                order["status"] = "Accepted";
                              });
                              _updateOrderStatus(order, "Accepted");
                              showTopNotification(context, 'Accepted', 'Order #$kotNo accepted');
                            }
                          },
                          icon: const Icon(Icons.access_time, color: Colors.white),
                          label: Text(
                            "Accept Order",
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
                            elevation: 2,
                          ),
                        ),
                      ),
                    ),

                  
                  if (status == "pending")
                    const SizedBox(height: 16),
                  
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      "Ordered Items:",
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: _buildOrderItemsWithCompleteButtons(
                      dialogItems,
                      order,
                      setDialogState,
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // Reprint KOT Button
                  Center(
                    child: SizedBox(
                      width: 240,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          await Future.delayed(Duration.zero);
                          
                          try {
                            final orderForReprint = Map<String, dynamic>.from(order);
                            await _reprintKOT(orderForReprint);
                            
                            if (context.mounted) {
                              showTopNotification(
                                context, 
                                'Reprint KOT', 
                                'KOT #$kotNumber reprinted successfully'
                              );
                            }
                          } catch (e, st) {
                            _addDebugLog('Error reprinting KOT: $e');
                            _addDebugLog('STACK: $st');
                            if (context.mounted) {
                              showTopNotification(context, 'Reprint Error', 'Failed to reprint KOT: $e');
                            }
                          }
                        },
                        icon: const Icon(Icons.print, color: Colors.white),
                        label: Text(
                          "Reprint KOT",
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[600],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
                          elevation: 2,
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 30),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 5, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

Widget _buildOrderItems(Map<String, dynamic> order) {
  final items = (order['items'] as List<dynamic>?) ?? [];

  return Column(
    children: items.map((it) {
      // Use the new helper method here too
      final itemName = it is Map ? _getDisplayName(Map<String, dynamic>.from(it)) : "Unnamed Item";
      final quantity = it['quantity'] ?? "N/A";
      final itemDesc = it['item_desc'] ?? "";
      
      // Check if custom to avoid showing desc twice
      bool isCustom = it is Map && (
        it['is_custom'] == true || 
        it['is_custom'] == 'true' ||
        (it['orderItem'] is Map && (it['orderItem']['is_custom'] == true || it['orderItem']['is_custom'] == 'true'))
      );

      return Container(
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        margin: EdgeInsets.only(bottom: 8),
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade400),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              itemName,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
            SizedBox(height: 6),
            Text(
              "Quantity: $quantity",
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            // Only show note section if not custom and desc is not empty
            if (!isCustom && itemDesc.isNotEmpty) ...[
              SizedBox(height: 6),
              Text(
                "Note: $itemDesc",
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: Colors.red[700],
                ),
              ),
            ],
          ],
        ),
      );
    }).toList(),
  );
}
  /// Add Item Button
  Widget _buildAddItemButton(BuildContext context) {
    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.90,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          // <-- This centers the button horizontally
          child: SizedBox(
            width:
                MediaQuery.of(context).size.width * 0.9, // <-- Sets the width
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFFD95326),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () {},
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'Add Item',
                    style: GoogleFonts.poppins(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
// FIXED: Replace your _buildOrderCards method with this corrected version:


List<Widget> _buildOrderCards() {
  // First filter orders
  List<Map<String, dynamic>> filteredOrders = orders.where((order) {
    // ✅ FIXED: Proper category filtering including Completed
    bool matchesCategory;
    if (selectedCategory == "All") {
      // Show all non-completed orders
      matchesCategory = order["status"] != "Completed";
    } else if (selectedCategory == "Completed") {
      // Show only completed orders
      matchesCategory = order["status"] == "Completed";
    } else {
      // Show specific status (Pending, Accepted)
      matchesCategory = order["status"] == selectedCategory;
    }
    
    final searchText = searchController.text.trim().toLowerCase();
    bool matchesSearch = searchText.isEmpty ||
        (order["id"]?.toString().toLowerCase().contains(searchText) ?? false) ||
        (order["kotNumber"]?.toString().toLowerCase().contains(searchText) ?? false) ||
        (order["server"]?.toString().toLowerCase().contains(searchText) ?? false) ||
        (order["section_name"]?.toString().toLowerCase().contains(searchText) ?? false) ||
        (order["restaurent_table_number"]?.toString().toLowerCase().contains(searchText) ?? false);
    return matchesCategory && matchesSearch;
  }).toList();
  
  // ✅ NEW: Group by both KOT number AND location (section + table)
  final groupedOrders = <String, List<Map<String, dynamic>>>{};
  
  for (var order in filteredOrders) {
    // Create a unique key that combines KOT number, location, AND status
    // This ensures completed orders are never merged with active orders
    final kotNumber = _extractKotNumber(order);
    final section = order['section_name']?.toString() ?? 'Unknown';
    final table = order['restaurent_table_number']?.toString() ?? 'N/A';
    final status = order['status']?.toString() ?? 'Pending';
    
    // Include status in key so completed orders stay separate
    final groupKey = '${kotNumber}_${section}_${table}_${status}';
    
    if (!groupedOrders.containsKey(groupKey)) {
      groupedOrders[groupKey] = [];
    }
    groupedOrders[groupKey]!.add(order);
  }
  
  // Create consolidated orders from groups
  final consolidatedOrders = <Map<String, dynamic>>[];
  
  for (var entry in groupedOrders.entries) {
    final groupKey = entry.key;
    final ordersInGroup = entry.value;
    
    if (ordersInGroup.isEmpty) continue;
    
    if (ordersInGroup.length == 1) {
      // Single order - use as-is but ensure kotNumber is set
      final singleOrder = Map<String, dynamic>.from(ordersInGroup.first);
      singleOrder['kotNumber'] = _extractKotNumberAsInt(singleOrder);
      consolidatedOrders.add(singleOrder);
    } else {
      // Multiple orders at SAME location - consolidate them
      final kotNumber = _extractKotNumber(ordersInGroup.first);
      final consolidated = _consolidateOrdersForSameKot(ordersInGroup, kotNumber);
      consolidatedOrders.add(consolidated);
    }
  }
  
  // Sort by KOT number (newest first)
  consolidatedOrders.sort((a, b) {
    final aKot = a['kotNumber'] ?? 0;
    final bKot = b['kotNumber'] ?? 0;
    if (aKot is int && bKot is int) {
      return bKot.compareTo(aKot);
    }
    return 0;
  });
  
  // Return card widgets
  return consolidatedOrders.map((order) => _buildOrderCard(order)).toList();
}


Map<String, List<Map<String, dynamic>>> _groupOrdersByKotNumber(
    List<Map<String, dynamic>> orders) {
  Map<String, List<Map<String, dynamic>>> grouped = {};

  for (var order in orders) {
    // ✅ CRITICAL: Skip consolidation for shifted orders
    if (order['skipConsolidation'] == true || 
        order['is_shifted'] == true) {
      // Use the order's unique ID as group key to keep it separate
      final uniqueKey = order['id'].toString();
      grouped[uniqueKey] = [order];
      _addDebugLog('🔒 Keeping order ${uniqueKey} separate (skipConsolidation)');
      continue;
    }

    // Normal grouping for non-shifted orders — include status so
    // completed orders are never merged with active orders
    final status = order['status']?.toString() ?? 'Pending';
    String kotNumberKey = '${_extractKotNumber(order)}_$status';
    
    grouped.putIfAbsent(kotNumberKey, () => []);
    grouped[kotNumberKey]!.add(order);
  }

  return grouped;
}
// Helper method to extract KOT number consistently
String _extractKotNumber(Map<String, dynamic> order) {
  // ✅ PRESERVE _SHIFTED suffix for proper grouping
  dynamic kotCandidate = order['kotNumber'] ?? 
                         order['kotNo'] ?? 
                         order['kot'];
  
  if (kotCandidate == null) {
    final items = _normalizeItems(order['items']);
    if (items.isNotEmpty) {
      for (var item in items) {
        if (item is Map<String, dynamic>) {
          kotCandidate = item['kotNumber'] ?? 
                        item['orderItem']?['kotNumber'];
          if (kotCandidate != null) break;
        }
      }
    }
  }
  
  String kotNumber = 'N/A';
  try {
    if (kotCandidate != null) {
      kotNumber = kotCandidate.toString();
      if (int.tryParse(kotNumber) != null || kotNumber.contains('_SHIFTED')) {
        // ✅ Keep _SHIFTED suffix for shifted orders
        return kotNumber;
      }
    }
  } catch (_) {}
  
  return order['id']?.toString() ?? 'unknown';
}


List<Map<String, dynamic>> _createConsolidatedOrders(Map<String, List<Map<String, dynamic>>> groupedOrders) {
  List<Map<String, dynamic>> consolidatedOrders = [];
  
  for (var entry in groupedOrders.entries) {
    final groupKey = entry.key; // This is now "kotNumber_section_table"
    final ordersInGroup = entry.value;
    
    if (ordersInGroup.isEmpty) continue;
    
    // Extract the KOT number from the group key (before first underscore)
    final kotNumber = groupKey.split('_').first;
    
    // Use the first order as the base template
    final baseOrder = Map<String, dynamic>.from(ordersInGroup.first);
    
    // Collect all items from all orders in this KOT group AT THIS LOCATION
    List<Map<String, dynamic>> allItems = [];
    int totalAmount = 0;
    int totalQuantity = 0;
    Set<String> allStatuses = {};
    Set<String> allServers = {};
    String section = '';
    String table = '';
    String earliestTime = '';
    DateTime? earliestDateTime;
    
    for (var order in ordersInGroup) {
      // Add items from this order
      final orderItems = _normalizeItems(order['items']);
      if (orderItems.isNotEmpty) {
        // Ensure each item has kotNumber for consistency
        for (var item in orderItems) {
          if (item is Map<String, dynamic>) {
            // Add kotNumber to item if missing
            if (item['kotNumber'] == null) {
              item['kotNumber'] = _extractKotNumberAsInt(order);
            }
            allItems.add(item);
          }
        }
      } else {
        // Fallback: create item from top-level order data
        final fallbackItem = {
          'item_name': order['item_name']?.toString() ?? 'Unknown Item',
          'quantity': order['quantity']?.toString() ?? '1',
          'price': order['amount']?.toString() ?? '0',
          'item_desc': order['item_desc']?.toString() ?? '',
          'status': order['status']?.toString() ?? 'Pending',
          'kotNumber': _extractKotNumberAsInt(order),
          'order_item_id': order['id']?.toString(),
        };
        allItems.add(fallbackItem);
      }
      
      // Accumulate totals
      totalAmount += int.tryParse(order['amount']?.toString() ?? '0') ?? 0;
      totalQuantity += int.tryParse(order['quantity']?.toString() ?? '0') ?? 0;
      
      // Collect unique values
      final status = order['status']?.toString() ?? 'Pending';
      allStatuses.add(status);
      
      final server = order['server']?.toString() ?? '';
      if (server.isNotEmpty) allServers.add(server);
      
      // ✅ Use the section/table from the order (all orders in this group have same location)
      if (section.isEmpty) section = order['section_name']?.toString() ?? 'Unknown';
      if (table.isEmpty) table = order['restaurent_table_number']?.toString() ?? 
                                   order['table_number']?.toString() ?? 'N/A';
      
      // Track earliest time
      try {
        if (order['createdAt'] != null) {
          final orderDateTime = DateTime.parse(order['createdAt'].toString());
          if (earliestDateTime == null || orderDateTime.isBefore(earliestDateTime)) {
            earliestDateTime = orderDateTime;
            earliestTime = order['time']?.toString() ?? '';
          }
        }
      } catch (_) {
        if (earliestTime.isEmpty) {
          earliestTime = order['time']?.toString() ?? '';
        }
      }
    }
    
    // Determine the consolidated status (most advanced status wins)
    String consolidatedStatus = _determineConsolidatedStatus(allStatuses);
    
    // Create consolidated display strings
    final serverDisplay = allServers.isEmpty ? 'Unknown' : allServers.join(', ');
    
    // Create consolidated item name summary
    String itemNameSummary = _createItemNameSummary(allItems);
    
    // Check if this is a shifted order by looking at the original orders
    bool isShifted = ordersInGroup.any((o) => o['isShifted'] == true);
    String shiftedFrom = '';
    if (isShifted) {
      // Get the shifted_from_table from one of the orders
      for (var o in ordersInGroup) {
        if (o['shifted_from_table'] != null && o['shifted_from_table'].toString().isNotEmpty) {
          shiftedFrom = o['shifted_from_table'].toString();
          break;
        }
      }
    }
    
    // Create the consolidated order
    final consolidatedOrder = {
      ...baseOrder,
      'id': groupKey, // Use the location-aware group key as ID
      'kotNumber': _extractKotNumberAsInt(baseOrder),
      'items': allItems,
      'amount': totalAmount.toString(),
      'quantity': totalQuantity.toString(),
      'item_name': itemNameSummary,
      'status': consolidatedStatus,
      'server': serverDisplay,
      'section_name': section, // ✅ Use the specific section for this location
      'restaurent_table_number': table, // ✅ Use the specific table for this location
      'time': earliestTime.isNotEmpty ? earliestTime : DateFormat('hh:mm a').format(DateTime.now()),
      'orderCount': ordersInGroup.length, // Track how many original orders are in this group
      'originalOrders': ordersInGroup, // Keep reference to original orders for detailed view
      'isShifted': isShifted, // ✅ Preserve shifted status
      'shifted_from_table': shiftedFrom, // ✅ Preserve shift metadata
    };
    
    consolidatedOrders.add(consolidatedOrder);
  }
  
  // Sort by KOT number (numeric sort)
  consolidatedOrders.sort((a, b) {
    final aKot = a['kotNumber'] ?? 0;
    final bKot = b['kotNumber'] ?? 0;
    if (aKot is int && bKot is int) {
      return bKot.compareTo(aKot); // Descending order (newest first)
    }
    return 0;
  });
  
  return consolidatedOrders;
}



// Helper method to extract KOT number as integer
int _extractKotNumberAsInt(Map<String, dynamic> order) {
  final kotString = _extractKotNumber(order);
  return int.tryParse(kotString) ?? 0;
}

// Helper method to determine the most advanced status
String _determineConsolidatedStatus(Set<String> statuses) {
  // Show the LEAST advanced status so completed items don't get hidden
  // under a non-completed group status
  if (statuses.any((s) => s.toLowerCase() == 'pending')) {
    return 'Pending';
  } else if (statuses.any((s) => s.toLowerCase() == 'accepted')) {
    return 'Accepted';
  } else if (statuses.any((s) => s.toLowerCase() == 'completed')) {
    return 'Completed';
  }
  return statuses.isNotEmpty ? statuses.first : 'Pending';
}


String _createItemNameSummary(List<Map<String, dynamic>> items) {
  // Handle empty or null list
  if (items.isEmpty) return 'No Items';
  
  // Filter out null or invalid items
  final validItems = items.where((item) => item != null).toList();
  if (validItems.isEmpty) return 'No Items';
  
  // Single item case
  if (validItems.length == 1) {
    final item = validItems.first;
    final itemName = _getItemName(item);
    return itemName.isNotEmpty ? itemName : 'Unknown Item';
  }
  
  // Multiple items case
  final firstItem = validItems.first;
  final firstName = _getItemName(firstItem);
  final displayName = firstName.isNotEmpty ? firstName : 'Item';
  
  return '$displayName +${validItems.length - 1} more';
}
String _getDisplayName(Map<String, dynamic> item) {
  // Check if item is custom
  bool isCustom = false;
  
  // Try to find is_custom flag in various possible locations
  if (item['is_custom'] == true || item['is_custom'] == 'true') {
    isCustom = true;
  } else if (item['orderItem'] is Map && 
             (item['orderItem']['is_custom'] == true || 
              item['orderItem']['is_custom'] == 'true')) {
    isCustom = true;
  } else if (item['menu'] is Map && 
             (item['menu']['is_custom'] == true || 
              item['menu']['is_custom'] == 'true')) {
    isCustom = true;
  } else if (item['drinkMenu'] is Map && 
             (item['drinkMenu']['is_custom'] == true || 
              item['drinkMenu']['is_custom'] == 'true')) {
    isCustom = true;
  }
  
  // If custom, return item_desc
  if (isCustom) {
    final desc = item['item_desc'] ?? 
                 item['desc'] ?? 
                 item['description'] ?? 
                 (item['orderItem'] is Map ? item['orderItem']['desc'] : null) ?? 
                 '';
    if (desc.toString().trim().isNotEmpty) {
      return desc.toString().trim();
    }
  }
  
  // Otherwise return the regular item name
  return _getItemName(item);
}



OverlayEntry? _kotShiftOverlay;

void _removeKotShiftOverlay() {
  _kotShiftOverlay?.remove();
  _kotShiftOverlay = null;
  if (mounted) {
    setState(() {
      _isKotDialogOpen = false;
      _shiftedItemNames = [];
    });
  }
}

void _showKotShiftedPopup() {
  if (_isKotDialogOpen) {
    _addDebugLog('Shift popup already open, skipping');
    return;
  }

  _isKotDialogOpen = true;

  final fromText = _shiftFromText;
  final toText = _shiftToText;
  final itemNames = List<String>.from(_shiftedItemNames);

  // Auto-close after 5 seconds
  Timer(const Duration(seconds: 5), () {
    if (_isKotDialogOpen) _removeKotShiftOverlay();
  });

  _kotShiftOverlay = OverlayEntry(
    builder: (ctx) => GestureDetector(
      // Tap barrier to dismiss
      onTap: _removeKotShiftOverlay,
      child: Material(
        color: Colors.black54,
        child: Center(
          child: GestureDetector(
            // Prevent barrier tap from firing when tapping the card
            onTap: () {},
            child: Container(
              width: MediaQuery.of(context).size.width * 0.9,
              constraints: const BoxConstraints(maxWidth: 450),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.blue[50]!, Colors.white],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.blue[700],
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.swap_horiz, color: Colors.white, size: 32),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Drinks Orders Shifted',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${itemNames.length} drink(s) moved',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Body
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // From
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red[200]!, width: 2),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.red[100],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.local_drink, color: Colors.red[700], size: 24),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('From',
                                        style: GoogleFonts.poppins(
                                            fontSize: 11,
                                            color: Colors.grey[600],
                                            fontWeight: FontWeight.w500)),
                                    const SizedBox(height: 4),
                                    Text(fromText ?? 'Unknown',
                                        style: GoogleFonts.poppins(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.red[900])),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Arrow
                        Icon(Icons.arrow_downward, color: Colors.blue[600], size: 32),

                        if (itemNames.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue[200]!),
                            ),
                            child: Column(
                              children: [
                                Text('Drinks Moved:',
                                    style: GoogleFonts.poppins(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.blue[900])),
                                const SizedBox(height: 4),
                                ...itemNames.take(3).map((name) => Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 2),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.local_drink, size: 12, color: Colors.blue[700]),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(name,
                                                style: GoogleFonts.poppins(
                                                    fontSize: 11, color: Colors.blue[800]),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis),
                                          ),
                                        ],
                                      ),
                                    )),
                                if (itemNames.length > 3)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text('+${itemNames.length - 3} more',
                                        style: GoogleFonts.poppins(
                                            fontSize: 10,
                                            color: Colors.blue[600],
                                            fontWeight: FontWeight.w500)),
                                  ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 20),

                        // To
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green[200]!, width: 2),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.green[100],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.local_drink, color: Colors.green[700], size: 24),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('To',
                                        style: GoogleFonts.poppins(
                                            fontSize: 11,
                                            color: Colors.grey[600],
                                            fontWeight: FontWeight.w500)),
                                    const SizedBox(height: 4),
                                    Text(toText ?? 'Unknown',
                                        style: GoogleFonts.poppins(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green[900])),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Close button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _removeKotShiftOverlay,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue[600],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            child: Text('Got it',
                                style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600, fontSize: 15)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Overlay.of(context).insert(_kotShiftOverlay!);
}








void _debugShiftStatus() {
  if (orders.isEmpty) return;
  
  final shiftedOrders = orders.where((o) => 
    o['is_shifted'] == true || 
    o['kotNumber']?.toString().contains('_SHIFTED') == true
  ).toList();
  
  if (shiftedOrders.isEmpty) return;
  
  print('\n=== SHIFTED ORDERS DEBUG (${shiftedOrders.length} found) ===');
  for (var order in shiftedOrders) {
    final kotNumber = order['kotNumber']?.toString() ?? 'N/A';
    final isShifted = order['is_shifted'] == true;
    final skipConsolidation = order['skipConsolidation'] == true;
    final originalKot = order['original_kot_number']?.toString() ?? 'N/A';
    
    print('📦 Order ${order['id']}:');
    print('   Display KOT: $kotNumber');
    print('   Original KOT: $originalKot');
    print('   is_shifted: $isShifted');
    print('   skipConsolidation: $skipConsolidation');
    print('   Table: ${order['section_name']}-${order['restaurent_table_number']}');
  }
  print('=== END SHIFTED ORDERS DEBUG ===\n');
}

// Update the _buildOrderCard method to show KOT number instead of ID


Widget _buildOrderCard(Map<String, dynamic> order) {
  final isLargeScreen = MediaQuery.of(context).size.width > 800;
  final statusColor = _getStatusColor(order["status"]?.toString() ?? '');
  final orderCount = order['orderCount'] ?? 1;
  
  // ✅ Detect shifted orders

    final isShifted = order['isShifted'] == true || 
                      order['is_shifted'] == true ||
                      (order['shifted_from_table']?.toString() ?? '').isNotEmpty;

    final shiftedFrom = order['shifted_from_table']?.toString() ?? '';
  
  // ✅ Format KOT number with _SHIFTED suffix for shifted orders
  final kotNumber = order["kotNumber"]?.toString() ?? order["id"]?.toString() ?? 'N/A';
  final displayKotNumber = kotNumber.contains('_SHIFTED') 
        ? kotNumber 
        : (isShifted ? "${kotNumber}_SHIFTED" : kotNumber);
  
  final rawItems = order['items'];
  List<dynamic> itemsList = [];
  try {
    if (rawItems is List) {
      itemsList = rawItems;
    } else if (rawItems is String && rawItems.isNotEmpty) {
      final decoded = jsonDecode(rawItems);
      if (decoded is List) itemsList = decoded;
    }
  } catch (e) {
    _addDebugLog('Error parsing items in card: $e');
    itemsList = [];
  }

  if (itemsList.isEmpty) {
    final topName = (order['item_name'] ?? order['name'] ?? '').toString().trim();
    final topQty = (order['quantity'] ?? order['qty'] ?? '').toString().trim();
    final topDesc = (order['item_desc'] ?? order['description'] ?? '').toString().trim();

    if (topName.isNotEmpty || topQty.isNotEmpty || topDesc.isNotEmpty) {
      itemsList = [
        {
          'item_name': topName,
          'quantity': topQty.isNotEmpty ? topQty : '1',
          'item_desc': topDesc,
        }
      ];
    }
  }

  final displayItems = itemsList.take(3).toList();
  final hasMoreItems = itemsList.length > 3;

  List<Widget> itemWidgets = [];
  for (var it in displayItems) {
    String displayName = '';
    String note = '';
    String qty = '';

    if (it is Map) {
      displayName = _getDisplayName(Map<String, dynamic>.from(it));
      
      note = (it['item_desc'] ?? it['description'] ?? '').toString().trim();
      qty = (it['quantity'] ?? it['qty'] ?? '').toString().trim();

      if (it['orderItem'] is Map) {
        if (note.isEmpty) {
          note = (it['orderItem']['desc'] ?? it['orderItem']['description'] ?? '').toString().trim();
        }
        if (qty.isEmpty) {
          qty = (it['orderItem']['quantity'] ?? '').toString().trim();
        }
      }
    } else {
      displayName = it?.toString() ?? '';
      qty = '1';
    }

    if (displayName.isEmpty) displayName = 'Unnamed Item';
    if (qty.isEmpty) qty = '1';

    bool isCustom = it is Map && (
      it['is_custom'] == true || 
      it['is_custom'] == 'true' ||
      (it['orderItem'] is Map && (it['orderItem']['is_custom'] == true || it['orderItem']['is_custom'] == 'true'))
    );
    
    final shouldShowNote = !isCustom && note.isNotEmpty && note.toLowerCase() != displayName.toLowerCase();
    final finalDisplayName = shouldShowNote ? '$displayName ($note)' : displayName;

    itemWidgets.add(
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.local_drink, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                finalDisplayName,
                style: GoogleFonts.poppins(
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'x$qty',
              style: GoogleFonts.poppins(
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  if (hasMoreItems) {
    itemWidgets.add(
      InkWell(
        onTap: () => _showOrderDetails(context, order),
        child: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            "+${itemsList.length - 3} more",
            style: GoogleFonts.poppins(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: Colors.blue,
            ),
          ),
        ),
      ),
    );
  }

  return InkWell(
    onTap: () => _showOrderDetails(context, order),
    borderRadius: BorderRadius.circular(12),
    child: Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      color: const Color.fromARGB(255, 245, 243, 240),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ Show shift badge for shifted orders
            if (isShifted && shiftedFrom.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange[100],
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.orange[300]!),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.swap_horiz, size: 12, color: Colors.orange[700]),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Shifted from $shiftedFrom',
                        style: GoogleFonts.poppins(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange[900],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
            ],
            
            // ✅ Top KOT Number with _SHIFTED suffix
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "#$displayKotNumber • ${order["section_name"] ?? ''} • Table ${order["restaurent_table_number"] ?? ''}",
                        style: GoogleFonts.poppins(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Text(
                  "₹ ${order["amount"] ?? ''}",
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    color: Colors.green[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  order["server"]?.toString() ?? "Unknown",
                  style: GoogleFonts.poppins(fontSize: 9),
                ),
                Text(
                  order["time"]?.toString() ?? "",
                  style: GoogleFonts.poppins(
                    fontSize: 9,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (isLargeScreen) ...[
              Container(
                padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 10),
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  order["status"]?.toString() ?? "",
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    fontSize: 7,
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: itemWidgets,
            ),
            if (!isLargeScreen) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 10),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    order["status"]?.toString() ?? "",
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      fontSize: 7,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}





// Update the _getTopItemGroups method to count individual drink items separately
List<Map<String, dynamic>> _getTopItemGroups(BuildContext context) {
  Map<String, int> itemCounts = {};

  for (var order in orders) {
    if (order["status"] == "Completed") continue;

    // Get the actual items array from each order
    final rawItems = order['items'];
    final items = _normalizeItems(rawItems);

    if (items.isNotEmpty) {
      // Count each individual item
      for (var item in items) {
        if (item is! Map<String, dynamic>) continue;

        // Extract item name from various possible fields (drinks-specific)
        String itemName = '';
        if (item.containsKey('item_name')) {
          itemName = item['item_name']?.toString() ?? '';
        } else if (item['drinkMenu'] is Map) {
          itemName = (item['drinkMenu']['name'] ?? '').toString();
        } else if (item['menuItem'] is Map) {
          itemName = (item['menuItem']['name'] ?? '').toString();
        } else if (item.containsKey('name')) {
          itemName = item['name']?.toString() ?? '';
        }

        if (itemName.isEmpty) itemName = 'Unnamed Drink';

        // Extract quantity for this specific item
        int itemQuantity = 1;
        if (item.containsKey('quantity')) {
          itemQuantity = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
        } else if (item['orderItem'] is Map) {
          itemQuantity = int.tryParse(item['orderItem']['quantity']?.toString() ?? '1') ?? 1;
        } else if (item.containsKey('qty')) {
          itemQuantity = int.tryParse(item['qty']?.toString() ?? '1') ?? 1;
        }

        // Add to the count
        itemCounts[itemName] = (itemCounts[itemName] ?? 0) + itemQuantity;
      }
    } else {
      // Fallback: use top-level order data if no structured items
      final itemName = order["item_name"]?.toString() ?? "Unnamed Drink";
      
      // Skip if this looks like a consolidated name (contains "+X more")
      if (itemName.contains('+') && itemName.contains('more')) {
        continue;
      }
      
      final quantity = int.tryParse(order["quantity"]?.toString() ?? '0') ?? 0;
      itemCounts[itemName] = (itemCounts[itemName] ?? 0) + quantity;
    }
  }

  List<Map<String, dynamic>> itemList = itemCounts.entries
      .map((e) => {"name": e.key, "quantity": e.value})
      .toList();

  itemList.sort((a, b) => (b["quantity"] as int).compareTo(a["quantity"] as int));

  // Limit to top 5 items
  return itemList.take(5).toList();
}

  /// Merge orders by item-level kotNumber and return a list of merged order maps
List<Map<String, dynamic>> _mergeOrdersByKot(List<Map<String, dynamic>> sourceOrders) {
  // Map<kotNumber, mergedOrder>
  final Map<int, Map<String, dynamic>> groups = {};

  int safeParseInt(dynamic v, [int fallback = 0]) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    final s = v.toString();
    return int.tryParse(s) ?? fallback;
  }

  String chooseStatus(List<String> statuses) {
    // Priority: Pending > Accepted > Completed > (else first)
    if (statuses.any((s) => s.toLowerCase() == 'pending')) return 'Pending';
    if (statuses.any((s) => s.toLowerCase() == 'accepted')) return 'Accepted';
    if (statuses.any((s) => s.toLowerCase() == 'completed')) return 'Completed';
    return statuses.isNotEmpty ? statuses.first : 'Pending';
  }

  DateTime parseDateSafe(dynamic v) {
    try {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v;
      return DateTime.parse(v.toString());
    } catch (_) {
      return DateTime.now();
    }
  }

  for (final order in sourceOrders) {
    final orderStatus = (order['status'] ?? '').toString();
    final serverName = (order['server'] ?? '').toString();
    final sectionName = (order['section_name'] ?? '').toString();
    final tableNo = (order['restaurent_table_number'] ?? order['table_number'] ?? '').toString();
    final orderTime = order['createdAt'] ?? order['time'] ?? '';
    final items = (order['items'] as List<dynamic>?) ?? [];

    for (final rawItem in items) {
      if (rawItem == null) continue;
      Map<String, dynamic> it;
      if (rawItem is Map<String, dynamic>) {
        it = Map<String, dynamic>.from(rawItem);
      } else if (rawItem is Map) {
        it = Map<String, dynamic>.from(rawItem);
      } else {
        // fallback - create minimal item map
        it = {
          'item_name': rawItem.toString(),
          'quantity': '1',
          'price': '0',
          'item_desc': '',
          'kotNumber': 0,
        };
      }

      // determine kot for this item (try multiple shapes)
      int kot = 0;
      try {
        final cand = it['kotNumber'] ?? it['orderItem']?['kotNumber'] ?? order['kotNumber'] ?? order['kotNo'] ?? order['kot'];
        kot = safeParseInt(cand, 0);
      } catch (_) {
        kot = 0;
      }

      // ensure quantity and price are strings
      it['quantity'] = (it['quantity'] ?? it['qty'] ?? '1').toString();
      it['price'] = (it['price'] ?? '0').toString();

      // create group if missing
      if (!groups.containsKey(kot)) {
        groups[kot] = {
          'id': 'KOT-$kot', // unique id for merged card
          'kotNumber': kot,
          'items': <Map<String, dynamic>>[],
          'amount': '0',
          'quantity': '0',
          'serverList': <String>[],
          'sectionList': <String>[],
          'tableList': <String>[],
          'statusList': <String>[],
          'timeList': <String>[],
          'createdAtList': <String>[],
        };
      }

      final merged = groups[kot]!;

      // add item
      (merged['items'] as List<Map<String, dynamic>>).add(it);

      // collect unique servers / sections / tables
      if (serverName.isNotEmpty && !(merged['serverList'] as List<String>).contains(serverName)) {
        (merged['serverList'] as List<String>).add(serverName);
      }
      if (sectionName.isNotEmpty && !(merged['sectionList'] as List<String>).contains(sectionName)) {
        (merged['sectionList'] as List<String>).add(sectionName);
      }
      if (tableNo.isNotEmpty && !(merged['tableList'] as List<String>).contains(tableNo)) {
        (merged['tableList'] as List<String>).add(tableNo);
      }

      // collect statuses and times
      if (orderStatus.isNotEmpty) (merged['statusList'] as List<String>).add(orderStatus);
      if (orderTime != null && orderTime.toString().isNotEmpty) (merged['timeList'] as List<String>).add(orderTime.toString());
      if (order['createdAt'] != null) (merged['createdAtList'] as List<String>).add(order['createdAt'].toString());

      // update numeric totals: parse price * quantity if possible
      try {
        final q = int.tryParse(it['quantity'].toString()) ?? 0;
        final p = int.tryParse(it['price'].toString()) ?? 0;
        final prevAmount = int.tryParse((merged['amount'] ?? '0').toString()) ?? 0;
        final prevQty = int.tryParse((merged['quantity'] ?? '0').toString()) ?? 0;
        merged['amount'] = (prevAmount + (p * q)).toString();
        merged['quantity'] = (prevQty + q).toString();
      } catch (_) {
        // ignore parse errors, leave totals as-is
      }
    } // end items loop
  } // end orders loop

  // Convert groups map to list and tidy fields
  final List<Map<String, dynamic>> mergedOrders = [];
  groups.forEach((kot, m) {
    final servers = (m['serverList'] as List<String>).where((s) => s.trim().isNotEmpty).toSet().toList();
    final sections = (m['sectionList'] as List<String>).where((s) => s.trim().isNotEmpty).toSet().toList();
    final tables = (m['tableList'] as List<String>).where((s) => s.trim().isNotEmpty).toSet().toList();
    final statuses = (m['statusList'] as List<String>);
    final times = (m['timeList'] as List<String>);
    final createdAts = (m['createdAtList'] as List<String>);

    // pick earliest createdAt if any (to show time)
    DateTime earliest = DateTime.now();
    if (createdAts.isNotEmpty) {
      try {
        earliest = createdAts.map((c) => parseDateSafe(c)).reduce((a, b) => a.isBefore(b) ? a : b);
      } catch (_) {}
    } else if (times.isNotEmpty) {
      // fallback: don't parse hh:mm a reliably here
      earliest = DateTime.now();
    }

    final mergedOrder = <String, dynamic>{
      'id': m['id'].toString(),
      'kotNumber': kot,
      'items': List<Map<String, dynamic>>.from(m['items'] as List),
      'amount': (m['amount'] ?? '0').toString(),
      'quantity': (m['quantity'] ?? '0').toString(),
      'server': servers.join(', '),
      'section_name': sections.isNotEmpty ? sections.join(', ') : 'Unknown',
      'restaurent_table_number': tables.isNotEmpty ? tables.join(', ') : 'N/A',
      'status': chooseStatus(statuses),
      'time': DateFormat('hh:mm a').format(earliest),
      'createdAt': createdAts.isNotEmpty ? createdAts.first : null,
    };

    mergedOrders.add(mergedOrder);
  });

  // sort by kotNumber ascending (change to descending if you prefer)
  mergedOrders.sort((a, b) => (a['kotNumber'] as int).compareTo(b['kotNumber'] as int));

  return mergedOrders;
}



Map<String, dynamic> _consolidateOrdersForSameKot(List<Map<String, dynamic>> ordersInGroup, String kotNumberKey) {
  // Use the first order as the base template
  final baseOrder = Map<String, dynamic>.from(ordersInGroup.first);
  
  // Collect all items from all orders in this KOT group
  List<Map<String, dynamic>> allItems = [];
  int totalAmount = 0;
  int totalQuantity = 0;
  Set<String> allStatuses = {};
  Set<String> allServers = {};
  Set<String> allSections = {};
  Set<String> allTables = {};
  String earliestTime = '';
  DateTime? earliestDateTime;
  
  for (var order in ordersInGroup) {
    // Add items from this order
    final orderItems = _normalizeItems(order['items']);
    if (orderItems.isNotEmpty) {
      for (var item in orderItems) {
        if (item is Map<String, dynamic>) {
          // Ensure item has kotNumber
          if (item['kotNumber'] == null) {
            item['kotNumber'] = _extractKotNumberAsInt(order);
          }
          allItems.add(item);
        }
      }
    } else {
      // Fallback: create item from top-level order data
      final fallbackItem = {
        'item_name': order['item_name']?.toString() ?? 'Unknown Item',
        'quantity': order['quantity']?.toString() ?? '1',
        'price': order['amount']?.toString() ?? '0',
        'item_desc': order['item_desc']?.toString() ?? '',
        'kotNumber': _extractKotNumberAsInt(order),
        'order_item_id': order['id']?.toString(),
      };
      allItems.add(fallbackItem);
    }
    
    // Accumulate totals
    totalAmount += int.tryParse(order['amount']?.toString() ?? '0') ?? 0;
    totalQuantity += int.tryParse(order['quantity']?.toString() ?? '0') ?? 0;
    
    // Collect unique values
    final status = order['status']?.toString() ?? 'Pending';
    allStatuses.add(status);
    
    final server = order['server']?.toString() ?? '';
    if (server.isNotEmpty) allServers.add(server);
    
    final section = order['section_name']?.toString() ?? '';
    if (section.isNotEmpty) allSections.add(section);
    
    final table = order['restaurent_table_number']?.toString() ?? 
                 order['table_number']?.toString() ?? '';
    if (table.isNotEmpty) allTables.add(table);
    
    // Track earliest time
    try {
      if (order['createdAt'] != null) {
        final orderDateTime = DateTime.parse(order['createdAt'].toString());
        if (earliestDateTime == null || orderDateTime.isBefore(earliestDateTime)) {
          earliestDateTime = orderDateTime;
          earliestTime = order['time']?.toString() ?? '';
        }
      }
    } catch (_) {
      if (earliestTime.isEmpty) {
        earliestTime = order['time']?.toString() ?? '';
      }
    }
  }
  
  // Determine the consolidated status (most advanced status wins)
  String consolidatedStatus = _determineConsolidatedStatus(allStatuses);
  
  // Create consolidated display strings
  final serverDisplay = allServers.isEmpty ? 'Unknown' : allServers.join(', ');
  final sectionDisplay = allSections.isEmpty ? 'Unknown' : allSections.join(', ');
  final tableDisplay = allTables.isEmpty ? 'N/A' : allTables.join(', ');
  
  // Create consolidated item name summary
  String itemNameSummary = _createItemNameSummary(allItems);

  // ✅ REMOVED: All shift metadata logic
  // Cards just show current location
  
  // Create the consolidated order
  return {
    ...baseOrder,
    'id': kotNumberKey,
    'kotNumber': _extractKotNumberAsInt(baseOrder),
    'items': allItems,
    'amount': totalAmount.toString(),
    'quantity': totalQuantity.toString(),
    'item_name': itemNameSummary,
    'status': consolidatedStatus,
    'server': serverDisplay,
    'section_name': sectionDisplay,
    'restaurent_table_number': tableDisplay,
    'time': earliestTime.isNotEmpty ? earliestTime : DateFormat('hh:mm a').format(DateTime.now()),
    'orderCount': ordersInGroup.length,
    'originalOrders': ordersInGroup,
    // ✅ REMOVED: No shift metadata on consolidated orders
  };
}

// Helper method to safely extract item name from various possible fields
String _getItemName(Map<String, dynamic> item) {
  // Try multiple possible field names for item name
  final possibleNameFields = [
    'item_name',
    'name',
    'friendlyName',
    'title',
  ];
  
  for (final field in possibleNameFields) {
    final value = item[field];
    if (value != null) {
      final name = value.toString().trim();
      if (name.isNotEmpty) return name;
    }
  }
  
  // Try nested objects (drinks-specific)
  try {
    // Check drinkMenu object
    if (item['drinkMenu'] is Map<String, dynamic>) {
      final drinkMenu = item['drinkMenu'] as Map<String, dynamic>;
      for (final field in possibleNameFields) {
        final value = drinkMenu[field];
        if (value != null) {
          final name = value.toString().trim();
          if (name.isNotEmpty) return name;
        }
      }
    }
    
    // Check menuItem object
    if (item['menuItem'] is Map<String, dynamic>) {
      final menuItem = item['menuItem'] as Map<String, dynamic>;
      for (final field in possibleNameFields) {
        final value = menuItem[field];
        if (value != null) {
          final name = value.toString().trim();
          if (name.isNotEmpty) return name;
        }
      }
    }
    
    // Check menu object
    if (item['menu'] is Map<String, dynamic>) {
      final menu = item['menu'] as Map<String, dynamic>;
      for (final field in possibleNameFields) {
        final value = menu[field];
        if (value != null) {
          final name = value.toString().trim();
          if (name.isNotEmpty) return name;
        }
      }
    }
    
    // Check orderItem for description as fallback
    if (item['orderItem'] is Map<String, dynamic>) {
      final orderItem = item['orderItem'] as Map<String, dynamic>;
      final desc = orderItem['desc'] ?? orderItem['description'];
      if (desc != null) {
        final name = desc.toString().trim();
        if (name.isNotEmpty) return name;
      }
    }
  } catch (e) {
    // Log error but continue with fallback
    debugPrint('Error extracting item name from nested objects: $e');
  }
  
  // Final fallback - try item_desc or description
  final desc = item['item_desc'] ?? item['description'] ?? item['desc'];
  if (desc != null) {
    final name = desc.toString().trim();
    if (name.isNotEmpty) return name;
  }
  
  return ''; // Return empty string if nothing found
}

  Widget _buildTopItemGroupsRow(BuildContext context) {
    final topItems = _getTopItemGroups(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        children:
            topItems.map((item) {
              final icon = _getIconForItem(item['name']);
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18, color: Colors.grey[700]),
                    const SizedBox(width: 6),
                    Text(
                      '${item["name"]} x${item["quantity"]}',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF1F2937),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
      ),
    );
  }

  /// Optional: Add different icons based on item name
  IconData _getIconForItem(String name) {
    final lower = name.toLowerCase();
    if (lower.contains("salad")) return Icons.eco;
    if (lower.contains("chicken")) return Icons.set_meal;
    if (lower.contains("mushroom")) return Icons.ramen_dining;
    return Icons.restaurant_menu;
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case "Pending":
        return Color.fromRGBO(255, 200, 1, 1);
      case "Accepted":
        return Color.fromARGB(255, 60, 99, 207);
      case "Completed":
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}
