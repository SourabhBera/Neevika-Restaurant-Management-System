import 'dart:async';
import 'package:Neevika/screens/Drinks/drinksOrders/usb_printer.dart';
import 'package:Neevika/widgets/sidebar.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:another_flushbar/flushbar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata; // ✅ Correct import
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'dart:typed_data';
import 'package:permission_handler/permission_handler.dart';


import 'dart:ui' as ui;
import 'package:flutter/services.dart' show rootBundle;
import 'dart:typed_data';

void showTopNotification(BuildContext context, String title, String body) {
  Flushbar(
    title: title,
    message: body,
    duration: const Duration(seconds: 6),
    flushbarPosition: FlushbarPosition.TOP,
    backgroundColor: Colors.green,
    margin: const EdgeInsets.all(8),
    borderRadius: BorderRadius.circular(8),
    icon: const Icon(Icons.notifications, color: Colors.white),
  ).show(context);
}

class ViewOrdersScreen extends StatefulWidget {
  const ViewOrdersScreen({super.key});

  @override
  _ViewOrdersScreenState createState() => _ViewOrdersScreenState();
}

class _ViewOrdersScreenState extends State<ViewOrdersScreen> {
  String selectedCategory = "All";
  List<String> categories = ["All", "Pending", "Accepted", "Completed"];
  TextEditingController searchController = TextEditingController();

  // Use dynamic maps for orders because different sources return nested maps
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
  final Set<String> _printedKotNumbers = {}; // to avoid duplicate prints

  // Keep a reference to listener so we can remove it on dispose
  late final VoidCallback _searchListener;

  bool _isKotDialogOpen = false;
  String? _shiftFromText;
  String? _shiftToText;
  List<String> _shiftedItemNames = [];

  @override
  void initState() {
    super.initState();
    tzdata.initializeTimeZones();
    _addDebugLog('Init: scanning printers and connecting socket...');

    // set up listener reference so we can remove later
    _searchListener = () {
      setState(() {});
    };
    searchController.addListener(_searchListener);

    _scanForPrinters(); // auto-scan and auto-select first printer
    connectToSocket();

    // Fetch orders once during init
    fetchOrders().whenComplete(() {
      // nothing extra required here; don't reconnect socket twice
      _addDebugLog('Initial fetchOrders completed');
    });
  }

// ----------------- Printer discovery -----------------
  Future<void> _scanForPrinters() async {
    try {
      setState(() => isScanning = true);
      _addDebugLog('Starting USB discovery (plugin)...');

      // Request permissions (multi-request returns Map)
      try {
        await [Permission.storage, Permission.photos].request();
        _addDebugLog('Requested permissions');
      } catch (e) {
        _addDebugLog('Permission request failed: $e');
      }

      availablePrinters.clear();
      selectedPrinter = null;

      Stream<PrinterDevice> stream = printerManager.discovery(type: PrinterType.usb);
      final sub = stream.listen((printer) {
        _addDebugLog('Found device: ${printer.name} | VID:${printer.vendorId} PID:${printer.productId}');
        availablePrinters.add(printer);
        if (selectedPrinter == null) {
          selectedPrinter = printer;
          _addDebugLog('Auto-selected printer: ${printer.name} (VID:${printer.vendorId} PID:${printer.productId})');
          if (context.mounted) {
            showTopNotification(context, 'Printer selected', '${printer.name} selected for printing');
          }
        }
        setState(() {});
      }, onError: (e) {
        _addDebugLog('Discovery error: $e');
      });

      await Future.delayed(const Duration(seconds: 2));
      await sub.cancel();

      if (availablePrinters.isEmpty) {
        _addDebugLog('No USB printers found after scan');
        if (context.mounted) {
          showTopNotification(context, 'Scan', 'No USB printers found — connect the printer and tap Scan');
        }
      } else {
        _addDebugLog('Discovery finished: ${availablePrinters.length} device(s) found');
      }
    } catch (e) {
      _addDebugLog('Scan exception: $e');
    } finally {
      if (mounted) setState(() => isScanning = false);
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

  // ----------------- SOCKET -----------------
  void connectToSocket() {
    try {
      socket = IO.io(dotenv.env['API_URL_1'] ?? 'http://13.60.15.89:3000', <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': true,
      });

      socket!.on('connect', (_) {
        _addDebugLog('\n🆕 Connected to socket\n');
      });

      socket!.on('new_foods_order', (data) {
        _addDebugLog('\n🆕 New order received (raw): ${data.runtimeType} -> ${data.toString()}\n');

        try {
          // 1) Ensure we have a Map<String, dynamic> in `payload`
          Map<String, dynamic> payload;
          if (data is String) {
            payload = jsonDecode(data) as Map<String, dynamic>;
          } else if (data is Map) {
            // cast to desired type safely
            payload = Map<String, dynamic>.from(data);
          } else {
            // unexpected type
            _addDebugLog('Unsupported new_order payload type: ${data.runtimeType}');
            return;
          }

          // 2) Normalize items: payload['items'] might be a List or a JSON string
          dynamic rawItems = payload['items'];
          List<dynamic> itemsList = [];
          if (rawItems == null) {
            itemsList = [];
          } else if (rawItems is String) {
            // sometimes server sends stringified JSON
            try {
              final decoded = jsonDecode(rawItems);
              if (decoded is List) {
                itemsList = decoded;
              } else {
                _addDebugLog('items string decoded to non-list: ${decoded.runtimeType}');
                itemsList = [];
              }
            } catch (e) {
              _addDebugLog('Failed to decode items string: $e');
              itemsList = [];
            }
          } else if (rawItems is List) {
            itemsList = rawItems;
          } else {
            _addDebugLog('items field has unexpected type: ${rawItems.runtimeType}');
            itemsList = [];
          }

          // 3) Extract order map (payload may contain 'order' object or similar)
          final order = (payload['order'] as Map?)?.cast<String, dynamic>() ?? {};

          final createdAtUtc = DateTime.tryParse(order['createdAt']?.toString() ?? '') ?? DateTime.now();
          final ist = tz.getLocation('Asia/Kolkata');
          final createdAtIst = tz.TZDateTime.from(createdAtUtc, ist);

          String orderId = order['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();

          // 4) Build items entries (handle both 'menuItem' and 'drinkMenu' keys)
          // store items as List<Map<String, dynamic>> and include ids for deletion matching
          List<Map<String, dynamic>> itemEntries = [];

          for (var entry in itemsList) {
            if (entry is! Map) {
              _addDebugLog('Skipping non-map item entry: ${entry.runtimeType}');
              continue;
            }
            final Map<String, dynamic> entryMap = Map<String, dynamic>.from(entry);

            final orderItem = (entryMap['orderItem'] ?? entryMap['order_item'] ?? {}) as Map? ?? {};
            final menuItem = (entryMap['menuItem'] ?? entryMap['drinkMenu'] ?? entryMap['drink_item'] ?? {}) as Map? ?? {};

            final itemName = (menuItem['name'] ?? orderItem['desc'] ?? orderItem['description'] ?? 'Item Not Found').toString();
            final itemQuantity = orderItem['quantity']?.toString() ?? '1';
            final itemPrice = orderItem['price']?.toString() ?? '0';

            _addDebugLog('Extracted Item: name=$itemName, quantity=$itemQuantity, price=$itemPrice');

            // include various id shapes so deletion handler can match
            final orderItemId = orderItem['id']?.toString();
            final menuItemId = menuItem['id']?.toString();

            itemEntries.add({
              "item_name": itemName,
              "quantity": itemQuantity,
              "item_desc": orderItem['desc']?.toString() ?? '',
              "price": itemPrice,
              "status": _normalizeStatus(order['status'] ?? 'Pending'),
              // helpful ids for deletion matching
              "id": orderItemId ?? menuItemId ?? '', // prefer orderItem id
              "order_item_id": orderItemId ?? '',
              "menu_item_id": menuItemId ?? '',
              // keep original nested maps for maximum flexibility
              "orderItem": orderItem,
              "menuItem": menuItem,
            });

            
          }

          _addDebugLog('DEBUG: Item entries created: ${itemEntries.length}');
          if (itemEntries.isNotEmpty) {
            _addDebugLog('DEBUG: First item name: ${itemEntries.first["item_name"]}');
          }

          // 5) Build orderEntry with helpful top-level summary fields
          final orderEntry = {
            "id": orderId,
            "serverId": order['user']?['id']?.toString() ?? '',
            "table_number": order['restaurant_table_number']?.toString() ?? '',
            "amount": itemEntries.fold<int>(0, (sum, item) => sum + (int.tryParse((item['price'] ?? '0').toString()) ?? 0)).toString(),
            "restaurent_table_number": order['restaurant_table_number']?.toString() ?? '',
            "time": DateFormat('hh:mm a').format(createdAtIst),
            "server": order['user']?['name']?.toString() ?? 'Unknown',
            "section_name": order['section']?['name']?.toString() ?? 'Section Not Found',
            "status": _normalizeStatus(order['status'] ?? 'Pending'),
            "kotNumber": payload['kotNumber']?.toString() ?? order['kotNumber']?.toString() ?? orderId,
            // store items as a List<Map<String, dynamic>>
            "items": itemEntries,
            // create a helpful top-level summary for card UI:
            // if multiple items -> "FirstItem +N more"
            "item_name": itemEntries.isEmpty
                ? ''
                : (itemEntries.length == 1
                    ? itemEntries.first['item_name']
                    : '${itemEntries.first['item_name']} +${itemEntries.length - 1} more'),
            "quantity": itemEntries.isEmpty
                ? '0'
                : itemEntries.map((e) => int.tryParse((e['quantity'] ?? '1').toString()) ?? 1).fold<int>(0, (a, b) => a + b).toString(),
            "item_desc": itemEntries.isNotEmpty ? (itemEntries.first['item_desc'] ?? '') : '',
          };

          // 6) Insert/update orders list in state (defensive merging)
          final existingOrderIndex = orders.indexWhere((o) => o["id"] == orderId);

          if (mounted) {
            setState(() {
              if (existingOrderIndex >= 0) {
                // Defensive read of existing items (could be List, or a JSON string)
                final existing = orders[existingOrderIndex];
                List<Map<String, dynamic>> existingItems = [];

                final raw = existing['items'];
                if (raw is String) {
                  try {
                    final decoded = jsonDecode(raw);
                    if (decoded is List) {
                      existingItems = decoded.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)).toList();
                    }
                  } catch (e) {
                    _addDebugLog('Failed to decode existing items string: $e');
                  }
                } else if (raw is List) {
                  try {
                    existingItems = raw.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)).toList();
                  } catch (e) {
                    _addDebugLog('Existing items list has unexpected shape: $e');
                    existingItems = [];
                  }
                } else {
                  existingItems = [];
                }

                // merge new itemEntries
                existingItems.addAll(itemEntries);

                // update summary fields (keep same format as above)
                existing['items'] = existingItems;
                existing['item_name'] = existingItems.isEmpty
                    ? ''
                    : (existingItems.length == 1
                        ? existingItems.first['item_name']
                        : '${existingItems.first['item_name']} +${existingItems.length - 1} more');
                existing['quantity'] = existingItems.isEmpty
                    ? '0'
                    : existingItems.map((e) => int.tryParse((e['quantity'] ?? '1').toString()) ?? 1).fold<int>(0, (a, b) => a + b).toString();
                existing['amount'] = existingItems.fold<int>(0, (s, it) => s + (int.tryParse((it['price'] ?? '0').toString()) ?? 0)).toString();

                // write back to orders list (already mutated)
                orders[existingOrderIndex] = existing;
                _addDebugLog('Updated existing order id=$orderId with ${existingItems.length} items');
              } else {
                // new insertion already has correct 'items' and summary fields from orderEntry
                orders.insert(0, orderEntry);
                _addDebugLog('Inserted new order id=$orderId');
              }
            });
          } else {
            // widget not mounted fallback (simple insert)
            orders.insert(0, orderEntry);
            _addDebugLog('Inserted new order id=$orderId (widget not mounted)');
          }

          final kotNo = (orderEntry['kotNumber'] ?? orderEntry['id'] ?? '').toString();

          if (_printedKotNumbers.contains(kotNo)) {
            _addDebugLog('Skipping auto-print for KOT $kotNo - already printed');
          } else {
            Future.delayed(const Duration(seconds: 2), () {
              if (!_printedKotNumbers.contains(kotNo)) {
                _addDebugLog('Auto-printing order $kotNo after delay');
                _printedKotNumbers.add(kotNo);
                
                _printOrderNative(orderEntry).then((_) {
                  // ✅ AFTER SUCCESSFUL PRINT, UPDATE STATUS TO ACCEPTED
                  _addDebugLog('Auto-print successful for KOT $kotNo - updating status to Accepted');
                  
                  // Update local UI
                  if (mounted) {
                    setState(() {
                      final orderIndex = orders.indexWhere((o) => 
                        (o['kotNumber']?.toString() ?? o['id']?.toString()) == kotNo
                      );
                      if (orderIndex >= 0) {
                        orders[orderIndex]['status'] = 'Accepted';
                      }
                    });
                  }
                  
                  // Update backend
                  _acceptOrder(kotNo, orderEntry);
                  
                }).catchError((e) {
                  _addDebugLog('Auto-print error: $e');
                  _printedKotNumbers.remove(kotNo);
                });
              } else {
                _addDebugLog('Cancelled auto-print for KOT $kotNo - was printed elsewhere');
              }
            });
          }
        } catch (e, st) {
          _addDebugLog('Error handling new_order payload: $e');
          _addDebugLog('STACK: $st');
        }
      });



      socket!.on('order_deleted', (data) {
        _addDebugLog("🗑️ order_deleted event (raw): ${data.runtimeType} -> ${data.toString()}");

        try {
          String? deletedItemId;
          String? deletedOrderId;
          Map<String, dynamic>? payload;

          // Normalize payload - handle different data formats
          if (data is String) {
            try {
              final parsed = jsonDecode(data);
              if (parsed is Map) {
                payload = Map<String, dynamic>.from(parsed);
              } else if (parsed is String) {
                // Plain ID string
                deletedItemId = parsed.trim();
              }
            } catch (_) {
              // Not JSON - treat as item ID string
              deletedItemId = data.trim();
            }
          } else if (data is Map) {
            payload = Map<String, dynamic>.from(data);
          } else if (data is int) {
            deletedItemId = data.toString();
          }

          // Extract IDs from payload
          if (payload != null) {
            // Try multiple possible field names for item ID
            deletedItemId = _extractId(payload, [
              'itemId', 'item_id', 'orderItemId', 'order_item_id', 
              'deletedItemId', 'idToDelete', 'id'
            ]);

            // Try multiple possible field names for order ID
            deletedOrderId = _extractId(payload, [
              'orderId', 'order_id', 'order'
            ]);

            try {
              _handleDeleteEvent(payload);
            } catch (e) {
              _addDebugLog('Error calling _handleDeleteEvent: $e');
            }
          }

          // Validate extracted IDs
          if (deletedItemId?.trim().isEmpty ?? true) deletedItemId = null;
          if (deletedOrderId?.trim().isEmpty ?? true) deletedOrderId = null;

          _addDebugLog("Extracted - ItemID: $deletedItemId, OrderID: $deletedOrderId");

          // Determine what type of deletion this is:
          // 1. If only orderId is provided -> remove entire order
          // 2. If both orderId and itemId are provided -> remove specific item from specific order
          // 3. If only itemId is provided -> remove item from any order that contains it

          if (deletedOrderId != null && deletedItemId == null) {
            // Case 1: server sent only an orderId — do a safer removal check
            _addDebugLog('Received orderId-only delete request for $deletedOrderId — performing safer check before full removal');
            _maybeRemoveEntireOrder(deletedOrderId, payload);

          } else if (deletedOrderId != null && deletedItemId != null) {
            // Case 2: Remove specific item from specific order
            _addDebugLog('Removing itemId=$deletedItemId from orderId=$deletedOrderId');
            _removeItemFromOrderById(orderId: deletedOrderId, itemId: deletedItemId);
          } else if (deletedItemId != null) {
            // Case 3: Remove item from any order that contains it
            _addDebugLog('Removing itemId=$deletedItemId from all orders');
            _removeItemFromAllOrders(deletedItemId);
          } else {
            _addDebugLog('order_deleted event missing both itemId and orderId; ignoring');
          }

        } catch (e, st) {
          _addDebugLog('Error in order_deleted handler: $e');
          _addDebugLog('STACK: $st');
        }
      });

      


socket!.on('order_item_completed', (data) {
  _addDebugLog("✅ order_item_completed event received: $data");
  
  try {
    Map<String, dynamic> payload;
    if (data is String) {
      payload = jsonDecode(data) as Map<String, dynamic>;
    } else if (data is Map) {
      payload = Map<String, dynamic>.from(data);
    } else {
      _addDebugLog('Unsupported payload type: ${data.runtimeType}');
      return;
    }

    final completedOrderId = payload['orderId']?.toString() ?? '';
    final kotNumber = payload['kotNumber']?.toString() ?? '';
    final itemName = payload['itemName']?.toString() ?? '';
    final menuId = payload['menuId']?.toString() ?? '';
    
    if (completedOrderId.isEmpty) {
      _addDebugLog('No orderId in completion event');
      return;
    }

    _addDebugLog('🎯 Processing completion for Order.id=$completedOrderId, kotNumber=$kotNumber, itemName=$itemName, menuId=$menuId');

    if (mounted) {
      setState(() {
        bool itemFound = false;
        
        // ✅ Search through ALL orders
        for (int orderIdx = 0; orderIdx < orders.length; orderIdx++) {
          final order = orders[orderIdx];
          
          // Skip partial completion placeholders
          if (order['isPartialCompletion'] == true) continue;
          
          final items = _normalizeItems(order['items']);
          
          _addDebugLog('🔍 Checking order ${order['id']} (KOT: ${order['kotNumber']}) with ${items.length} items');
          
          // ✅ Check if ANY item in this order matches the completed Order.id
          bool hasMatchingItem = false;
          for (var item in items) {
            final itemOrderId = item['orderId']?.toString() ?? '';
            final itemId = item['id']?.toString() ?? '';
            final orderItemId = item['order_item_id']?.toString() ?? '';
            final nestedOrderId = item['orderItem']?['orderId']?.toString() ?? '';
            final nestedId = item['orderItem']?['id']?.toString() ?? '';
            
            if (itemOrderId == completedOrderId || 
                itemId == completedOrderId ||
                orderItemId == completedOrderId ||
                nestedOrderId == completedOrderId ||
                nestedId == completedOrderId) {
              hasMatchingItem = true;
              _addDebugLog('✅ MATCH FOUND in order ${order['id']}: item has matching ID');
              break;
            }
          }
          
          // Only process this order if it has a matching item
          if (!hasMatchingItem) {
            _addDebugLog('⏭️ Skipping order ${order['id']} - no matching items');
            continue;
          }
          
          _addDebugLog('📝 Processing order ${order['id']} - contains matching item');
          
          // ✅ Mark matching items as completed (DON'T REMOVE THEM)
          int completedCount = 0;
          int activeCount = 0;
          
          for (var item in items) {
            final itemOrderId = item['orderId']?.toString() ?? '';
            final itemId = item['id']?.toString() ?? '';
            final orderItemId = item['order_item_id']?.toString() ?? '';
            final nestedOrderId = item['orderItem']?['orderId']?.toString() ?? '';
            final nestedId = item['orderItem']?['id']?.toString() ?? '';
            
            bool matches = (itemOrderId == completedOrderId || 
                           itemId == completedOrderId ||
                           orderItemId == completedOrderId ||
                           nestedOrderId == completedOrderId ||
                           nestedId == completedOrderId);
            
            if (matches) {
              item['status'] = 'completed';
              if (item['orderItem'] is Map) {
                item['orderItem']['status'] = 'completed';
              }
              completedCount++;
              _addDebugLog('✅ Marked item as completed: ${item['item_name']}');
            }
            
            // Count active items
            final itemStatus = item['status']?.toString().toLowerCase() ?? 'pending';
            if (itemStatus != 'completed') {
              activeCount++;
            }
          }
          
          if (completedCount > 0) {
            itemFound = true;
            
            // ✅ CRITICAL: Update order status based on active items
            if (activeCount == 0) {
              // All items completed - mark entire order as Completed
              order['status'] = 'Completed';
              _addDebugLog('✅ All items completed - marked order ${order['kotNumber']} as Completed');
            } else {
              // Some items still active - keep as Accepted
              order['status'] = 'Accepted';
              _addDebugLog('✅ ${activeCount} items still active - keeping order ${order['kotNumber']} as Accepted');
            }
            
            // ✅ Keep ALL items (including completed ones) in the order
            order['items'] = items; // Don't remove anything
            
            // ✅ Recalculate totals based on ACTIVE items only
            int totalQty = 0;
            int totalAmount = 0;
            List<Map<String, dynamic>> activeItems = [];
            
            for (var it in items) {
              final itemStatus = it['status']?.toString().toLowerCase() ?? 'pending';
              if (itemStatus != 'completed') {
                activeItems.add(it);
                totalQty += int.tryParse((it['quantity'] ?? '1').toString()) ?? 1;
                totalAmount += int.tryParse((it['price'] ?? '0').toString()) ?? 0;
              }
            }
            
            // ✅ Update summary fields for card display (based on ACTIVE items)
            if (activeItems.isEmpty) {
              order['quantity'] = '0';
              order['amount'] = '0';
              order['item_name'] = 'Completed';
            } else {
              order['quantity'] = totalQty.toString();
              order['amount'] = totalAmount.toString();
              order['item_name'] = activeItems.length == 1
                  ? (activeItems.first['item_name'] ?? 'Item')
                  : '${activeItems.first['item_name'] ?? 'Item'} +${activeItems.length - 1} more';
            }
            
            _addDebugLog('✅ Updated order ${order['kotNumber']}: ${items.length} total items (${activeItems.length} active), status=${order['status']}');
          }
        }
        
        if (!itemFound) {
          _addDebugLog('⚠️ WARNING: No matching item found for Order.id=$completedOrderId');
        } else {
          _addDebugLog('✅ Successfully marked item(s) as completed for Order.id=$completedOrderId');
        }
      });
    }
  } catch (e, st) {
    _addDebugLog('❌ Error handling order_item_completed: $e');
    _addDebugLog('STACK: $st');
  }
});

      socket!.on('order_shifted', (data) {
        try {
          final payload = Map<String, dynamic>.from(data);
          print('\n\n🔄 order_shifted payload: $payload\n\n');
          final String fromTableId = payload['fromTableId'].toString();
          final String toTableId = payload['toTableId'].toString();
          final String fromSectionName = payload['fromSectionName'].toString();
          final String toSectionName = payload['toSectionName'].toString();

          final List<dynamic> shiftedOrderIds = payload['orderIds'] ?? [];

          if (mounted) {
            setState(() {
              for (final rawId in shiftedOrderIds) {
                final orderId = rawId.toString();

                final index = orders.indexWhere(
                  (o) => o['id']?.toString() == orderId,
                );

                if (index == -1) continue;

                final order = orders[index];
                // ✅ UPDATE EXISTING ORDER (NOT CREATE NEW)
               
                order['restaurent_table_number'] = toTableId; 
                order['section_name'] = toSectionName;

                // Metadata for UI badge
                order['isShifted'] = true;
                order['shifted_from_table'] =
                    '$fromSectionName - Table $fromTableId';

                orders[index] = order;
              }
            });
          }

          // 🔔 Popup logic stays same
          if (mounted && shiftedOrderIds.isNotEmpty) {
            _shiftFromText = '$fromSectionName - Table $fromTableId';
            _shiftToText = '$toSectionName - Table $toTableId';
            _showKotShiftedPopup();
          }
        } catch (e, st) {
          _addDebugLog('❌ order_shifted error: $e');
          _addDebugLog('STACK: $st');
        }
      });

socket!.on('transfer_table', (data) {
  try {
    final payload = Map<String, dynamic>.from(data);

    final fromTable = payload['fromTable'];
    final toTable = payload['toTable'];

    if (fromTable == null || toTable == null) return;

    final String fromTableDbId    = fromTable['id']?.toString() ?? '';
    final String toTableDbId      = toTable['id']?.toString() ?? '';
    final String toDisplayNumber  = toTable['display_number']?.toString() ?? '';
    final String fromDisplayNumber = fromTable['display_number']?.toString() ?? '';

    // ✅ Read section_name from socket payload
    final String fromSectionName  = fromTable['section_name']?.toString() ?? '';

    // ✅ Build label matching the DB format
    final String shiftedFromLabel = fromSectionName.isNotEmpty
        ? '$fromSectionName Table $fromDisplayNumber'
        : 'Table $fromDisplayNumber';

    if (mounted) {
      setState(() {
        for (int i = 0; i < orders.length; i++) {
          final order = orders[i];
          final orderTableNum  = order['table_number']?.toString() ?? '';
          final orderDisplayNum = order['restaurent_table_number']?.toString() ?? '';

          final matchesDb      = orderTableNum == fromTableDbId && fromTableDbId.isNotEmpty;
          final matchesDisplay = orderDisplayNum == fromDisplayNumber && fromDisplayNumber.isNotEmpty;

          if (!matchesDb && !matchesDisplay) continue;

          orders[i] = {
            ...order,
            'table_number'            : toTableDbId,
            'restaurent_table_number' : toDisplayNumber,
            'isShifted'               : true,
            'shifted_from_table'      : shiftedFromLabel,  // ✅ "Garden Table 11"
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
  }
});

      socket!.on('order_accepted', (data) {
        _handleStatusEvent(data, 'Accepted');
      });

      socket!.on('order_completed', (data) {
        _handleStatusEvent(data, 'Completed');
      });

      socket!.on('disconnect', (_) => _addDebugLog('Socket disconnected'));
    } catch (e) {
      _addDebugLog('Socket connection error: $e');
    }
  }





// Add these two fields to the State class (near _isKotDialogOpen)
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
      onTap: _removeKotShiftOverlay,
      child: Material(
        color: Colors.black54,
        child: Center(
          child: GestureDetector(
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
                                'Orders Shifted',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${itemNames.length} item(s) moved',
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
                                child: Icon(Icons.restaurant, color: Colors.red[700], size: 24),
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
                                Text('Items Moved:',
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
                                          Icon(Icons.fastfood, size: 12, color: Colors.blue[700]),
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
                                child: Icon(Icons.restaurant, color: Colors.green[700], size: 24),
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


/// Print a "Delete Order" KOT. Simpler than full  — single heading "DELETE ORDER".
Future<void> _printDeleteKOT(Map<String, dynamic> orderData) async {
  if (selectedPrinter == null) {
    _addDebugLog('No printer selected — cannot print delete KOT for ${orderData['id']}');
    try {
      await _scanForPrinters();
    } catch (_) {}
    if (selectedPrinter == null) {
      // if (context.mounted) showTopNotification(context, 'Print skipped', 'No USB printer connected for Delete KOT');
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
    final tableNo = (orderData['table_number'] ?? '').toString();

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
   List<String> _chunks(String text, int width) {
      if (text.isEmpty) return [''];
      if (text.length <= width) return [text];
      
      List<String> result = [];
      String remaining = text.trim();
      
      while (remaining.length > width) {
        int splitIndex = width;
        
        // Try to find a space to break at (look backwards from width)
        int lastSpace = remaining.lastIndexOf(' ', width);
        
        // Only use the space if it's reasonably close to the edge (at least 60% of width)
        // This prevents breaking too early and wasting space
        if (lastSpace > (width * 0.6).floor() && lastSpace > 0) {
          splitIndex = lastSpace;
        } else {
          // No good space found - look for other break points like hyphens
          int lastHyphen = remaining.lastIndexOf('-', width);
          if (lastHyphen > (width * 0.6).floor() && lastHyphen > 0) {
            splitIndex = lastHyphen + 1; // Include the hyphen in the first part
          }
          // Otherwise keep splitIndex at width (force break)
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
    // Compose bytes
    List<int> bytes = [];
    bytes += generator.reset();
    bytes += [0x1B, 0x4D, 0x00]; // ESC M 0 - Select Font A (same as native)

    // Header: DELETE ORDER (using same styling pattern as native)
    bytes += generator.text('* DELETED ORDER *', styles: PosStyles(
      align: PosAlign.center,
      bold: true,
      height: PosTextSize.size2,
      width: PosTextSize.size2,
    ));

    // Date and time - same format as native
    bytes += generator.text(dateTimeFormatted, styles: PosStyles(
      align: PosAlign.center,
      bold: false,
      height: PosTextSize.size2,
      width: PosTextSize.size2,
    ));

    // KOT number - same format as native
    bytes += generator.text('KOT - $kotNo', styles: PosStyles(
      align: PosAlign.center,
      bold: false,
      height: PosTextSize.size2,
      width: PosTextSize.size2,
    ));

    // Table info (same logic as native)
    if (tableNo.isNotEmpty) {
      bytes += generator.text('Table No: $tableNo', styles: PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
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
            width: PosTextSize.size1,
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
            width: PosTextSize.size1,
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
      if (context.mounted) 
      showTopNotification(context, 'Printed', 'Delete KOT $kotNo printed.');
    } catch (e) {
      _addDebugLog('Error sending delete KOT to printer: $e');
      if (context.mounted) 
      showTopNotification(context, 'Print Error', 'Failed to print Delete KOT: $e');
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

    if (data is String) {
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

    if (payload != null) {
      kotNumber = payload['kotNumber']?.toString() ??
                  payload['kot']?.toString() ??
                  payload['kot_no']?.toString() ??
                  kotNumber;
      final rawIds = payload['orderIds'] ?? payload['orderIds'] ?? payload['orderIds'];
      if (rawIds is List) {
        orderIds = rawIds.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
      } else if (rawIds is String) {
        orderIds = [rawIds];
      } else if (payload['orderIds'] == null && payload['orderId'] != null) {
        orderIds = [payload['orderId'].toString()];
      }
    }

    if ((kotNumber == null || kotNumber.isEmpty) && payload == null && data is! String) {
      try {
        final asJson = jsonDecode(data.toString());
        if (asJson is Map) {
          payload = Map<String, dynamic>.from(asJson);
          kotNumber = kotNumber ?? payload['kotNumber']?.toString();
        }
      } catch (_) {}
    }

    // ✅ FIX: Wrap in setState and force UI update
    if (mounted) {
      setState(() {
        int matched = 0;

        if (kotNumber != null && kotNumber.toString().trim().isNotEmpty) {
          final k = kotNumber.toString().trim();
          for (int i = 0; i < orders.length; i++) {
            final orderKot = (orders[i]['kotNumber'] ?? orders[i]['id'] ?? '').toString();
            if (orderKot == k) {
              orders[i]['status'] = newStatus;
              matched++;
              _addDebugLog("✅ Updated order ${orders[i]['id']} (KOT: $k) to status: $newStatus");
            }
          }
        }

        if (matched == 0 && orderIds.isNotEmpty) {
          for (final oid in orderIds) {
            for (int i = 0; i < orders.length; i++) {
              final currentId = (orders[i]['id'] ?? '').toString();
              if (_orderIdMatches(currentId, oid)) {
                orders[i]['status'] = newStatus;
                matched++;
                _addDebugLog("✅ Updated order ${orders[i]['id']} (ID: $oid) to status: $newStatus");
              }
            }
          }
        }

        if (matched == 0 && orderIds.isNotEmpty) {
          for (final oid in orderIds) {
            for (int i = 0; i < orders.length; i++) {
              final items = _normalizeItems(orders[i]['items']);
              if (_hasItemWithId(items, oid)) {
                orders[i]['status'] = newStatus;
                matched++;
                _addDebugLog("✅ Updated order ${orders[i]['id']} (contains item ID: $oid) to status: $newStatus");
              }
            }
          }
        }

        _addDebugLog("Applied status '$newStatus' to $matched local order(s) for kot='$kotNumber' orderIds=$orderIds");
      });
    } else {
      _addDebugLog("⚠️ Widget not mounted - skipping status update");
    }

    if (context.mounted) {
      final displayKot = kotNumber ?? (orderIds.isNotEmpty ? orderIds.first : 'unknown');
      // Removed notification to reduce UI clutter
    }
  } catch (e, st) {
    _addDebugLog("Error handling socket status event ($newStatus): $e");
    _addDebugLog('STACK: $st');
  }
}



void _maybeRemoveEntireOrder(String orderIdToRemove, Map<String, dynamic>? payload) {
  _addDebugLog('Attempting safe remove check for order: $orderIdToRemove');

  // Try to find a top-level order matching this id
  final orderIndex = orders.indexWhere((o) => _orderIdMatches(o['id']?.toString(), orderIdToRemove));
  if (orderIndex >= 0) {
    final order = orders[orderIndex];
    final items = _normalizeItems(order['items']);
    final itemCount = items.length;
    _addDebugLog('Order $orderIdToRemove found (top-level) with $itemCount item(s)');

    // Force flag handling
    final forceRemove = payload != null && (payload['force'] == true || payload['force']?.toString() == 'true');
    if (forceRemove || itemCount <= 1) {
      _addDebugLog('Removing whole order $orderIdToRemove (force=$forceRemove or itemCount<=1)');
      _removeEntireOrder(orderIdToRemove);
      return;
    }

    // Order exists and has >1 items: try removing nested item(s) within this order
    _addDebugLog('Order $orderIdToRemove has multiple items; trying nested-item removal inside this order before refusing full deletion.');

    // Try to match nested items inside this specific order.
    // We'll reuse _itemMatchesId to check each item for a match with orderIdToRemove.
    for (var it in items) {
      if (it is! Map<String, dynamic>) continue;

      // If item matches by any rule (id/orderItem.id/orderItem.orderId/menuItem.id/etc.)
      if (_itemMatchesId(it, orderIdToRemove)) {
        // Prefer order_item id if available, else try nested orderItem.id, menuItem.id, fallback to provided id
        String candidateItemId = '';
        try {
          if ((it['order_item_id']?.toString().trim().isNotEmpty ?? false)) {
            candidateItemId = it['order_item_id'].toString().trim();
          }
        } catch (_) {}
        if (candidateItemId.isEmpty) {
          try {
            if (it['orderItem'] is Map && (it['orderItem']['id'] != null)) {
              candidateItemId = it['orderItem']['id'].toString().trim();
            }
          } catch (_) {}
        }
        if (candidateItemId.isEmpty) {
          try {
            if (it['id'] != null) candidateItemId = it['id'].toString().trim();
          } catch (_) {}
        }
        if (candidateItemId.isEmpty) {
          try {
            if (it['menu_item_id'] != null) candidateItemId = it['menu_item_id'].toString().trim();
          } catch (_) {}
        }
        if (candidateItemId.isEmpty) {
          try {
            if (it['menuItem'] is Map && it['menuItem']['id'] != null) candidateItemId = it['menuItem']['id'].toString().trim();
          } catch (_) {}
        }
        if (candidateItemId.isEmpty) {
          candidateItemId = orderIdToRemove; // final fallback
        }

        _addDebugLog('Nested match inside same order: removing itemId=$candidateItemId from orderId=${order["id"]} (matched by $orderIdToRemove)');
        _removeItemFromOrderById(orderId: order['id']?.toString() ?? '', itemId: candidateItemId, notify: true);
        return;
      }
    }

    // No nested match inside the top-level order; do not delete whole order
    _addDebugLog('No nested item matched inside top-level order $orderIdToRemove. Refusing to remove whole order (no force flag).');
    return;
  }

  // No top-level order matched. Try to find a nested item inside any order that matches this id:
  _addDebugLog('Top-level order $orderIdToRemove not found — attempting nested item match across orders.');
  final found = _findAndRemoveItemByNestedId(orderIdToRemove);

  if (found) {
    _addDebugLog('Successfully removed matching nested item(s) for id $orderIdToRemove');
    return;
  }

  // Nothing matched; keep safe and log
  _addDebugLog('Safer-guard: nothing matched for id $orderIdToRemove (no top-level order, no nested item). Not removing any order.');
}



// Replace/insert this improved nested-finder that chooses the best item id to delete
bool _findAndRemoveItemByNestedId(String idToMatch) {
  if (idToMatch.trim().isEmpty) return false;
  final target = idToMatch.trim();

  for (int oi = 0; oi < orders.length; oi++) {
    final order = orders[oi];
    final parentOrderId = order['id']?.toString() ?? '';
    final rawItems = order['items'];
    final items = _normalizeItems(rawItems);

    for (var it in items) {
      if (it is! Map<String, dynamic>) continue;

      // If this item matches the incoming id by any rule, remove it
      if (_itemMatchesId(it, target)) {
        // Prefer explicit orderItem id when removing an item from its parent
        String candidateItemId = '';

        // Try multiple extraction strategies in order of most-likely to be the correct id
        try {
          if (it['order_item_id'] != null && it['order_item_id'].toString().trim().isNotEmpty) {
            candidateItemId = it['order_item_id'].toString().trim();
            _addDebugLog('Selected candidateItemId from order_item_id: $candidateItemId');
          }
        } catch (_) {}
        if (candidateItemId.isEmpty) {
          try {
            if (it['orderItem'] is Map && (it['orderItem']['id'] != null)) {
              candidateItemId = it['orderItem']['id'].toString().trim();
              _addDebugLog('Selected candidateItemId from orderItem.id: $candidateItemId');
            }
          } catch (_) {}
        }
        if (candidateItemId.isEmpty) {
          try {
            if (it['id'] != null) {
              candidateItemId = it['id'].toString().trim();
              _addDebugLog('Selected candidateItemId from item.id: $candidateItemId');
            }
          } catch (_) {}
        }
        if (candidateItemId.isEmpty) {
          try {
            if (it['menu_item_id'] != null) {
              candidateItemId = it['menu_item_id'].toString().trim();
              _addDebugLog('Selected candidateItemId from menu_item_id: $candidateItemId');
            }
          } catch (_) {}
        }
        if (candidateItemId.isEmpty) {
          try {
            if (it['menuItem'] is Map && it['menuItem']['id'] != null) {
              candidateItemId = it['menuItem']['id'].toString().trim();
              _addDebugLog('Selected candidateItemId from menuItem.id: $candidateItemId');
            }
          } catch (_) {}
        }

        // final fallback: use the incoming id if nothing else found
        if (candidateItemId.isEmpty) {
          candidateItemId = target;
          _addDebugLog('No specific candidate id found inside item — falling back to target id: $candidateItemId');
        }

        _addDebugLog('Nested match: removing itemId=$candidateItemId from parent orderId=$parentOrderId (matched by $target)');
        // call removal function which updates orders list
        _removeItemFromOrderById(orderId: parentOrderId, itemId: candidateItemId, notify: true);
        return true;
      }
    }
  }

  // nothing found
  _addDebugLog('No nested item matched id $target in any current order');
  // Optionally dump a sample of orders for debugging:
  if (kDebugMode) {
    for (int i = 0; i < orders.length; i++) {
      _addDebugLog('DEBUG ORD ${i} id=${orders[i]['id']} items=${orders[i]['items']}');
    }
  }

  return false;
}

// Replace/insert this enhanced item matcher
bool _itemMatchesId(Map<String, dynamic> item, String targetId) {
  try {
    if (targetId.trim().isEmpty) return false;
    final t = targetId.trim();

    // Helper to compare loose equality (string or numeric)
    bool equalLoose(dynamic a, String b) {
      if (a == null) return false;
      final as = a.toString().trim();
      if (as == b) return true;
      // numeric compare if possible
      final ai = int.tryParse(as);
      final bi = int.tryParse(b);
      if (ai != null && bi != null) return ai == bi;
      return false;
    }

    // First check obvious flattened keys
    final keysToCheck = [
      'id', 'item_id', 'itemId', 'order_item_id', 'orderItemId', 'menu_item_id', 'menuItemId', 'menu_item', 'menuItem'
    ];
    for (final k in keysToCheck) {
      try {
        if (item.containsKey(k) && equalLoose(item[k], t)) {
          _addDebugLog('Match by key "$k" -> ${item[k]} == $t');
          return true;
        }
      } catch (_) {}
    }

    // Check nested maps commonly used
    if (item['orderItem'] is Map) {
      final om = item['orderItem'] as Map;
      if (equalLoose(om['id'], t)) {
        _addDebugLog('Match by orderItem.id -> ${om['id']} == $t');
        return true;
      }
      if (equalLoose(om['orderId'], t) || equalLoose(om['order_id'], t)) {
        _addDebugLog('Match by orderItem.orderId -> ${om['orderId'] ?? om['order_id']} == $t');
        return true;
      }
      if (equalLoose(om['menuId'], t) || equalLoose(om['menu_id'], t)) {
        _addDebugLog('Match by orderItem.menuId -> ${om['menuId'] ?? om['menu_id']} == $t');
        return true;
      }
    }

    if (item['menuItem'] is Map) {
      final mm = item['menuItem'] as Map;
      if (equalLoose(mm['id'], t)) {
        _addDebugLog('Match by menuItem.id -> ${mm['id']} == $t');
        return true;
      }
      if ((mm['name']?.toString() ?? '').trim() == t) {
        _addDebugLog('Match by menuItem.name -> ${mm['name']} == $t (string match)');
        return true;
      }
    }

    // Drink-specific nested shapes
    if (item['drinkMenu'] is Map) {
      final dm = item['drinkMenu'] as Map;
      if (equalLoose(dm['id'], t)) {
        _addDebugLog('Match by drinkMenu.id -> ${dm['id']} == $t');
        return true;
      }
    }

    // Some servers embed ids in weird places; do a shallow search of nested values
    bool shallowSearch(Map m) {
      for (final entry in m.entries) {
        final v = entry.value;
        if (v == null) continue;
        if (v is String || v is num) {
          if (equalLoose(v, t)) {
            _addDebugLog('Shallow nested match by key "${entry.key}" -> $v == $t');
            return true;
          }
        }
      }
      return false;
    }

    // try shallow search on nested maps
    for (final key in ['orderItem', 'menuItem', 'order_item', 'menu_item', 'drinkMenu', 'drink_item']) {
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


String? _extractId(Map<String, dynamic> payload, List<String> fieldNames) {
  for (String field in fieldNames) {
    final value = payload[field]?.toString().trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

// Fixed remove entire order method - this removes the whole order card
void _removeEntireOrder(String orderIdToRemove) {
  final initialCount = orders.length;
  
  _addDebugLog('Attempting to remove entire order with ID: $orderIdToRemove');
  _addDebugLog('Current orders count: ${orders.length}');
  
  // Debug: Print all order IDs to see what we have
  for (int i = 0; i < orders.length && i < 10; i++) { // Limit debug output
    final orderId = orders[i]['id']?.toString();
    _addDebugLog('Order $i: ID = "$orderId"');
  }
  
  if (mounted) {
    setState(() {
      orders.removeWhere((order) {
        final currentOrderId = order['id']?.toString();
        final matches = _orderIdMatches(currentOrderId, orderIdToRemove);
        if (matches) {
          _addDebugLog('Found matching order to remove: $currentOrderId');
        }
        return matches;
      });
    });
  } else {
    orders.removeWhere((order) {
      final currentOrderId = order['id']?.toString();
      final matches = _orderIdMatches(currentOrderId, orderIdToRemove);
      if (matches) {
        _addDebugLog('Found matching order to remove: $currentOrderId');
      }
      return matches;
    });
  }
  
  final removedCount = initialCount - orders.length;
  _addDebugLog('Removed $removedCount order(s) with ID $orderIdToRemove');
  _addDebugLog('Orders count after removal: ${orders.length}');
  
  if (removedCount > 0 && context.mounted) {
    // showTopNotification(context, 'Order Removed', 'Order #$orderIdToRemove has been deleted');
  } else if (removedCount == 0) {
    _addDebugLog('Order $orderIdToRemove not found in current orders list');
  }
}

// Helper method to match order IDs with different formats
bool _orderIdMatches(String? currentId, String targetId) {
  if (currentId == null || targetId.isEmpty) return false;
  
  // Direct string comparison
  if (currentId == targetId) return true;
  
  // Try numeric comparison (handle int vs string)
  try {
    final currentNum = int.tryParse(currentId);
    final targetNum = int.tryParse(targetId);
    if (currentNum != null && targetNum != null) {
      return currentNum == targetNum;
    }
  } catch (e) {
    // Ignore parsing errors
  }
  
  // Try with trimmed whitespace
  if (currentId.trim() == targetId.trim()) return true;
  
  return false;
}

// Remove item from all orders (when order ID not specified) - this removes individual items
void _removeItemFromAllOrders(String itemId) {
  bool itemFound = false;
  List<String> affectedOrders = [];

  for (int orderIndex = 0; orderIndex < orders.length; orderIndex++) {
    final order = orders[orderIndex];
    final orderId = order['id']?.toString() ?? '';
    
    if (orderId.isEmpty) continue;

    // Check if this order contains the item to delete
    final items = _normalizeItems(order['items']);
    final hasMatchingItem = _hasItemWithId(items, itemId);

    if (hasMatchingItem) {
      itemFound = true;
      affectedOrders.add(orderId);
      
      // Remove the item from this order
      _removeItemFromOrderById(
        orderId: orderId, 
        itemId: itemId, 
        notify: false // Don't show notification for each order
      );
    }
  }

  if (itemFound && context.mounted) {
    final orderText = affectedOrders.length == 1 
        ? 'Order #${affectedOrders.first}'
        : '${affectedOrders.length} orders';
    showTopNotification(
      context, 
      'Item Removed', 
      'Item removed from $orderText'
    );
  } else {
    _addDebugLog('Item with ID $itemId not found in any order');
  }
}

// Check if items list contains an item with the specified ID
bool _hasItemWithId(List<Map<String, dynamic>> items, String targetId) {
  for (var item in items) {
    if (_itemMatchesId(item, targetId)) {
      return true;
    }
  }
  return false;
}


// Remove specific item from specific order - this modifies the order but keeps the card
Future<void> _removeItemFromOrderById({
  required String orderId,
  required String itemId,
  bool notify = true,
}) async {
  final orderIndex = orders.indexWhere((order) => _orderIdMatches(order['id']?.toString(), orderId));
  
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
  
  // Remove matching items using the enhanced matching logic
  currentItems.removeWhere((item) => _itemMatchesId(item, itemId));
  
  final removedCount = initialItemCount - currentItems.length;

  if (removedCount == 0) {
    _addDebugLog('No matching item with ID=$itemId found in order $orderId');
    return;
  }

  // Recalculate order totals
  int totalQty = 0;
  int totalAmount = 0;
  
  for (var item in currentItems) {
    try {
      final qty = int.tryParse((item['quantity'] ?? item['qty'] ?? '1').toString()) ?? 1;
      totalQty += qty;
      
      final price = int.tryParse((item['price'] ?? '0').toString()) ?? 0;
      totalAmount += price;
    } catch (e) {
      totalQty += 1; // Default quantity
      _addDebugLog('Error calculating totals for item: $e');
    }
  }

  // Update item name summary
  final itemNameSummary = currentItems.isEmpty
      ? ''
      : (currentItems.length == 1
          ? (currentItems.first['item_name'] ?? currentItems.first['name'] ?? 'Unnamed Item')
          : '${currentItems.first['item_name'] ?? currentItems.first['name'] ?? 'Item'} +${currentItems.length - 1} more');

  // Update UI - Important: Only remove the order card if NO items are left
  if (mounted) {
    setState(() {
      if (currentItems.isEmpty) {
        // Remove entire order card if no items left
        orders.removeAt(orderIndex);
        _addDebugLog('Removed order card $orderId - no items remaining');
      } else {
        // Update order with remaining items - keep the card
        order['items'] = currentItems;
        order['quantity'] = totalQty.toString();
        order['item_name'] = itemNameSummary;
        order['amount'] = totalAmount.toString();
        orders[orderIndex] = order;
        _addDebugLog('Updated order card $orderId - ${currentItems.length} items remaining');
      }
    });
  } else {
    // Fallback for unmounted widget
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

  _addDebugLog('Removed $removedCount item(s) with ID=$itemId from order $orderId. Remaining items: ${currentItems.length}');

  // Show notification
  if (context.mounted && notify) {
    if (currentItems.isEmpty) {
      // showTopNotification(context, 'Order Removed', 'Order #$orderId deleted (no items left)');
    } else {
      // showTopNotification(context, 'Item Removed', 'Item removed from Order #$orderId');
    }
  }
}


  void _addDebugLog(String message) {
    if (kDebugMode) {
      print(message);
    }
    // optionally keep in-memory log list for UI
    debugLogs.add('${DateTime.now().toIso8601String()} - $message');
    if (_logScrollController.hasClients) {
      try {
        _logScrollController.jumpTo(_logScrollController.position.maxScrollExtent);
      } catch (_) {}
    }
  }





Future<Uint8List> _renderTextAsBitmap(String text, {
  double fontSize = 24,
  String fontFamily = 'Arial', // or 'Calibri' if embedded
  bool bold = false,
  int paperWidthPx = 576, // 80mm at 203dpi
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  final textStyle = ui.TextStyle(
    fontFamily: fontFamily,
    fontSize: fontSize,
    fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    color: const Color(0xFF000000),
  );

  final paragraphStyle = ui.ParagraphStyle(
    textAlign: TextAlign.left,
  );

  final builder = ui.ParagraphBuilder(paragraphStyle)
    ..pushStyle(textStyle)
    ..addText(text);

  final paragraph = builder.build();
  paragraph.layout(ui.ParagraphConstraints(width: paperWidthPx.toDouble()));

  canvas.drawColor(const Color(0xFFFFFFFF), BlendMode.src);
  canvas.drawParagraph(paragraph, Offset.zero);

  final height = paragraph.height.ceil();
  final picture = recorder.endRecording();
  final image = await picture.toImage(paperWidthPx, height > 0 ? height : 40);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);

  return byteData!.buffer.asUint8List();
}

// Convert RGBA bitmap to ESC/POS raster format
List<int> _bitmapToEscPos(Uint8List rgbaBytes, int width, int height) {
  List<int> bytes = [];

  // GS v 0 command for raster graphics
  // Each byte = 8 horizontal pixels, MSB first
  final bytesPerRow = (width + 7) ~/ 8;

  bytes.addAll([0x1D, 0x76, 0x30, 0x00]); // GS v 0, normal size
  bytes.addAll([bytesPerRow & 0xFF, (bytesPerRow >> 8) & 0xFF]); // width in bytes (little-endian)
  bytes.addAll([height & 0xFF, (height >> 8) & 0xFF]);           // height in pixels (little-endian)

  for (int y = 0; y < height; y++) {
    for (int xByte = 0; xByte < bytesPerRow; xByte++) {
      int byteVal = 0;
      for (int bit = 0; bit < 8; bit++) {
        final x = xByte * 8 + bit;
        if (x < width) {
          final pixelIndex = (y * width + x) * 4; // RGBA
          final r = rgbaBytes[pixelIndex];
          final g = rgbaBytes[pixelIndex + 1];
          final b = rgbaBytes[pixelIndex + 2];
          // Convert to greyscale; dark pixel = printed dot
          final luminance = (0.299 * r + 0.587 * g + 0.114 * b).round();
          if (luminance < 128) {
            byteVal |= (0x80 >> bit); // MSB first
          }
        }
      }
      bytes.add(byteVal);
    }
  }

  return bytes;
}








Future<void> _printOrderNative(Map<String, dynamic> orderData) async {
  if (selectedPrinter == null) {
    _addDebugLog('No printer — cannot print order ${orderData['id']}');
    if (context.mounted) {
      showTopNotification(context, 'Printer Missing', 'Please connect USB printer and tap Scan');
    }
    return;
  }

  if (mounted) setState(() => isPrinting = true);

  try {
    final vendor  = _intFromDynamic(selectedPrinter!.vendorId);
    final product = _intFromDynamic(selectedPrinter!.productId);

    final sectionName = (orderData['section_name'] ?? '').toString().trim();
    final kotNumber   = (orderData['kotNumber'] ?? orderData['id']).toString();
    final tableNo     = (orderData['restaurent_table_number'] ?? orderData['table_number'] ?? '').toString().trim();
    final server      = (orderData['server'] ?? '').toString().trim();
    final now         = DateTime.now();
    final dtFormatted = '${DateFormat('dd/MM/yy').format(now)} ${DateFormat('HH:mm').format(now)}';

    // ── Collect items ──────────────────────────────────────────────────
    List<Map<String, String>> items = [];
    if (orderData['items'] is List) {
      for (final raw in (orderData['items'] as List)) {
        if (raw is! Map) continue;
        final it = Map<String, dynamic>.from(raw);
        final name = (it['item_name'] ?? it['name'] ?? it['menuItem']?['name'] ?? '').toString();
        final qty  = (it['quantity']  ?? it['qty']  ?? it['orderItem']?['quantity'] ?? '1').toString();
        final note = (it['item_desc'] ?? it['description'] ?? it['orderItem']?['desc'] ?? '').toString();

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

        String categoryName = '';
        try {
          if (it['menuItem'] is Map) {
            final mm = Map<String, dynamic>.from(it['menuItem']);
            categoryName = (mm['categoryName'] ?? mm['category_name'] ?? '').toString();
          }
        } catch (_) {}

        final nameLow  = name.toLowerCase();
        final catTrim  = categoryName.trim();
        final isIBread = catTrim.toLowerCase() == 'indian breads' || nameLow.contains('bakhri');

        items.add({
          'name':          name,
          'qty':           qty,
          'note':          note,
          'kotCategory':   kotCategory.trim().isEmpty ? 'Other' : kotCategory.trim(),
          'isIndianBread': isIBread ? '1' : '0',
        });
      }
    }
    if (items.isEmpty) {
      items.add({
        'name':          orderData['item_name']?.toString() ?? 'Item',
        'qty':           orderData['quantity']?.toString()  ?? '1',
        'note':          orderData['item_desc']?.toString() ?? '',
        'kotCategory':   'Other',
        'isIndianBread': '0',
      });
    }

    // ── Grouping ───────────────────────────────────────────────────────
    final indianItems    = items.where((i) => i['isIndianBread'] == '1').toList();
    final nonIndianItems = items.where((i) => i['isIndianBread'] != '1').toList();
    final orderOnlyIndian = indianItems.isNotEmpty && nonIndianItems.isEmpty;
    final hasIndianMain   = items.any((i) {
      final c = (i['kotCategory'] ?? '').toLowerCase();
      return c == 'veg-indian' || c == 'nonveg-indian';
    });

    final Map<String, List<Map<String, String>>> grouped = {};
    if (orderOnlyIndian) {
      grouped['Indian Breads'] = indianItems.map((e) => Map<String, String>.from(e)).toList();
    } else {
      for (final it in nonIndianItems) {
        final cat = it['kotCategory'] ?? 'Other';
        grouped.putIfAbsent(cat, () => []);
        grouped[cat]!.add(Map<String, String>.from(it));
      }
      if (indianItems.isNotEmpty) {
        if (hasIndianMain) {
          final tk = grouped.keys.firstWhere(
            (k) { final kk = k.toLowerCase(); return kk == 'veg-indian' || kk == 'nonveg-indian'; },
            orElse: () => 'Veg-Indian',
          );
          grouped.putIfAbsent(tk, () => []);
          for (final ib in indianItems) grouped[tk]!.add(Map<String, String>.from(ib));
        } else {
          for (final ib in indianItems) {
            final oc  = ib['kotCategory'] ?? '';
            final key = (oc.isNotEmpty && oc.toLowerCase() != 'other') ? oc : 'Indian Breads';
            grouped.putIfAbsent(key, () => []);
            grouped[key]!.add(Map<String, String>.from(ib));
          }
        }
      }
    }

    // ── Word-wrap (Font A, 48 cpl on 80mm) ────────────────────────────
    // Columns: Name=30, Note=12, Qty=6
    const int NC = 30, OC = 12, QC = 6;

    List<String> wrap(String text, int cols) {
      if (text.length <= cols) return [text];
      final result = <String>[];
      String rem = text.trim();
      while (rem.length > cols) {
        int split = cols;
        final sp = rem.lastIndexOf(' ', cols);
        if (sp > (cols * 0.55).floor()) split = sp;
        final chunk = rem.substring(0, split).trim();
        if (chunk.isNotEmpty) result.add(chunk);
        rem = rem.substring(split).trim();
      }
      if (rem.isNotEmpty) result.add(rem);
      return result.isEmpty ? [text] : result;
    }

    // ── ESC/POS raw byte helpers ───────────────────────────────────────
    // Encodes a Latin-1 string safely (ESC/POS printers expect Latin-1, not UTF-8)
    List<int> str(String s) => s.codeUnits.map((c) => c > 255 ? 0x3F : c).toList();

    // Full line: set attrs → text → LF
    List<int> line(
      String text, {
      bool   bold     = false,
      int    size     = 0x00,  // GS ! n: 0x00=normal,0x10=dblW,0x01=dblH,0x11=dblW+dblH
      int    align    = 0,     // 0=L,1=C,2=R
      int    lineSpacing = 40, // ESC 3 n  (n/180 inch between lines)
    }) {
      return [
        0x1B, 0x33, lineSpacing, // ESC 3 n — line spacing
        0x1B, 0x61, align,       // ESC a   — alignment
        0x1B, 0x45, bold ? 1 : 0,// ESC E   — bold
        0x1D, 0x21, size,        // GS  !   — char size
        ...str(text),
        0x0A,                    // LF
      ];
    }

    // ── INITIALISE ONCE (before category loop) ──────────────────────────
    final initBytes = <int>[];
    initBytes.addAll([0x1B, 0x40]);        // ESC @   — full hardware reset
    initBytes.addAll([0x1B, 0x4D, 0x00]); // ESC M 0 — Font A
    initBytes.addAll([0x1B, 0x20, 0x00]); // ESC SP 0 — no extra char spacing

    // ── PRINT HEADER ONCE (not per-category) ──────────────────────────
    final headerBytes = <int>[];
    headerBytes.addAll(initBytes);
    
    // Loop through grouped orders and print each category
    for (final entry in grouped.entries) {
      final catName  = entry.key;
      final catItems = entry.value;
      if (catItems.isEmpty) continue;

      // ── Build header for this category ────────────────────────────────
      final catHeaderBytes = <int>[];
      catHeaderBytes.addAll([0x1B, 0x40]);        // ESC @   — reset
      catHeaderBytes.addAll([0x1B, 0x4D, 0x00]); // ESC M 0 — Font A
      catHeaderBytes.addAll([0x1B, 0x20, 0x00]); // ESC SP 0

      // Category title (centered, bold, double size)
      catHeaderBytes.addAll(line(catName.toUpperCase(),
          bold: true, size: 0x11, align: 1, lineSpacing: 50));
      catHeaderBytes.addAll([0x1D, 0x21, 0x00]); // reset size

      // Date and Time (centered)
      catHeaderBytes.addAll(line(dtFormatted, align: 1, lineSpacing: 30));

      // KOT Number (centered)
      catHeaderBytes.addAll(line('KOT $kotNumber', align: 1, lineSpacing: 30));

      // Table No. (centered)
      final tablePart = tableNo.isNotEmpty && sectionName.isNotEmpty
          ? 'Table No.: $sectionName-$tableNo'
          : tableNo.isNotEmpty ? 'Table No.: $tableNo' : 'Table No.: N/A';
      catHeaderBytes.addAll(line(tablePart, align: 1, lineSpacing: 30));

      // Separator line 1
      catHeaderBytes.addAll(line('_' * 38, align: 1, lineSpacing: 25));

      // Captain (left aligned)
      if (server.isNotEmpty) {
        catHeaderBytes.addAll(line('Captain: ${server.toUpperCase()}', align: 0, lineSpacing: 30));
      }

      // Separator line 2
      catHeaderBytes.addAll(line('_' * 38, align: 1, lineSpacing: 25));

      // Column header: Item, Note, Qty
      final colHdr = 'Item'.padRight(20) + 'Note'.padRight(12) + 'Qty'.padLeft(6);
      catHeaderBytes.addAll(line(colHdr, bold: true, lineSpacing: 30));

      // Separator line 3
      catHeaderBytes.addAll(line('_' * 38, align: 1, lineSpacing: 25));

      // Send category header
      try {
        await UsbPrinter.printRawBytes(
          vendorId:      vendor,
          productId:     product,
          bytes:         Uint8List.fromList(catHeaderBytes),
          timeoutMillis: 5000,
        );
        _addDebugLog('Printed category header: $catName for order ${orderData['id']}');
      } catch (e) {
        _addDebugLog('Print header error: $e');
        if (context.mounted) {
          showTopNotification(context, 'Print Error', 'Failed to print header: $e');
        }
      }

      // ── Per-category items ────────────────────────────────────────────
      final out = <int>[];
      out.addAll([0x1B, 0x40]);        // ESC @   — reset
      out.addAll([0x1B, 0x4D, 0x00]); // ESC M 0 — Font A
      out.addAll([0x1B, 0x20, 0x00]); // ESC SP 0

      // Column widths (adjusted to match header)
      const int NC = 20, OC = 12, QC = 6;

      List<String> wrap(String text, int cols) {
        if (text.length <= cols) return [text];
        final result = <String>[];
        String rem = text.trim();
        while (rem.length > cols) {
          int split = cols;
          final sp = rem.lastIndexOf(' ', cols);
          if (sp > (cols * 0.55).floor()) split = sp;
          final chunk = rem.substring(0, split).trim();
          if (chunk.isNotEmpty) result.add(chunk);
          rem = rem.substring(split).trim();
        }
        if (rem.isNotEmpty) result.add(rem);
        return result.isEmpty ? [text] : result;
      }

      // ── ITEMS ────────────────────────────────────────────────────────
      for (final it in catItems) {
        final name    = it['name']!.trim();
        final rawNote = it['note']!.trim();
        final qty     = it['qty']!.trim();

        // Duplicate-note suppression
        String note = rawNote;
        if (rawNote.isNotEmpty) {
          final nl = name.toLowerCase();
          final dl = rawNote.toLowerCase();
          bool dup = nl == dl;
          if (!dup && (nl.contains(dl) || dl.contains(nl))) {
            final shorter = nl.length < dl.length ? nl : dl;
            final longer  = nl.length < dl.length ? dl : nl;
            dup = shorter.length >= longer.length * 0.7;
          }
          note = dup ? '' : '($rawNote)';
        }

        final nameChunks = wrap(name, NC);
        final noteChunks = note.isEmpty ? [''] : wrap(note, OC);
        final maxL = nameChunks.length > noteChunks.length
            ? nameChunks.length : noteChunks.length;

        for (int l = 0; l < maxL; l++) {
          final np = (l < nameChunks.length ? nameChunks[l] : '').padRight(NC);
          final no = (l < noteChunks.length ? noteChunks[l] : '').padRight(OC);
          final qp = (l == 0 ? qty : '').padLeft(QC);
          out.addAll(line('$np$no$qp', bold: l == 0, lineSpacing: 30));
        }
      }

      // ── FINAL SEPARATOR & TOTAL QTY ──────────────────────────────────
      out.addAll(line('_' * 38, align: 1, lineSpacing: 25));
      final totalQty = catItems.fold<int>(
          0, (s, it) => s + (int.tryParse(it['qty'] ?? '0') ?? 0));
      out.addAll(line('Total Qty: $totalQty', bold: true, align: 2, lineSpacing: 30));

      // ── RESET + FEED + CUT ────────────────────────────────────────────
      out.addAll([0x1B, 0x61, 0x00]);            // left align
      out.addAll([0x1D, 0x21, 0x00]);            // normal size
      out.addAll([0x1B, 0x45, 0x00]);            // bold off
      out.addAll([0x1B, 0x33, 30]);              // restore default line spacing
      out.addAll([0x0A, 0x0A, 0x0A, 0x0A]);     // 4 blank lines before cut
      out.addAll([0x1D, 0x56, 0x00]);            // GS V 0 — full cut

      // ── SEND ITEMS ────────────────────────────────────────────────────
      try {
        await UsbPrinter.printRawBytes(
          vendorId:      vendor,
          productId:     product,
          bytes:         Uint8List.fromList(out),
          timeoutMillis: 5000,
        );
        _addDebugLog('Printed items for "$catName" KOT for order ${orderData['id']}');
      } catch (e) {
        _addDebugLog('Print error "$catName": $e');
        if (context.mounted) {
          showTopNotification(context, 'Print Error', 'Failed to print $catName items: $e');
        }
      }
    }

    if (context.mounted) {
      showTopNotification(context, 'Printed',
          'KOT $kotNumber printed (${grouped.length} category/ies).');
    }
  } catch (e, st) {
    _addDebugLog('_printOrderNative error: $e\n$st');
    if (context.mounted) showTopNotification(context, 'Print Error', e.toString());
  } finally {
    if (mounted) setState(() => isPrinting = false);
  }
}









@override
void dispose() {
  _kotShiftOverlay?.remove();
  _kotShiftOverlay = null;
  try {
    searchController.removeListener(_searchListener);
  } catch (e) {
    _addDebugLog('Error removing search listener: $e');
  }
  searchController.dispose();
  if (socket != null) {
    try { socket!.disconnect(); } catch (e) { debugPrint('socket disconnect error: $e'); }
    try { socket!.close(); } catch (e) { debugPrint('socket close error: $e'); }
  }
  super.dispose();
}






  // Fetch orders from API
Future<void> fetchOrders() async {
  Timer? timeoutTimer;
  timeoutTimer = Timer(const Duration(seconds: 6), () {
    if (isLoading) {
      setState(() {
        isLoading = false;
        hasErrorOccurred = true;
      });
    }
  });

  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwtToken');

    if (token == null) {
      _addDebugLog('No token found. User might not be logged in.');
      if (timeoutTimer.isActive) timeoutTimer.cancel();
      setState(() {
        isLoading = false;
        hasErrorOccurred = true;
      });
      return;
    }

    final decodedToken = JwtDecoder.decode(token);
    final userId = decodedToken['id'];
    userRole = decodedToken['role'] ?? '';
    _addDebugLog('User role: $userRole');

    final response = await http.get(
      Uri.parse('${dotenv.env['API_URL']}/orders'),
    );

    if (timeoutTimer.isActive) timeoutTimer.cancel();

    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(response.body);
      print("Raw API response data: $data\n\n");
      final ist = tz.getLocation('Asia/Kolkata');
      _addDebugLog('Fetched orders: ${data.length}');
      print("Raw orders data: $data\n\n");
      if (mounted) {
        setState(() {
          orders = data.map<Map<String, dynamic>>((order) {
            final user = order['user'];
            final menu = order['menu'];
            final section = order['section'];
            final table = order['table'];
            final createdAtUtc = DateTime.parse(order['createdAt']);
            final createdAtIst = tz.TZDateTime.from(createdAtUtc, ist);

            final shiftedFromRaw = order['shifted_from_table']?.toString() ?? '';
            final shiftedFrom = (shiftedFromRaw == 'null' || shiftedFromRaw.trim().isEmpty) 
                ? '' 
                : shiftedFromRaw.trim();
            final isShifted = shiftedFrom.isNotEmpty;

            print("\ntable info for order $table\n");

            
            final rawDisplayNumber = order['restaurent_table_number']?.toString() ?? '';

            final displayNumber = table == null
                ? rawDisplayNumber
                : (table['is_split'] == true
                    ? order['table_display_name']?.toString() ??
                        table['display_number']?.toString() ??
                        rawDisplayNumber
                    : rawDisplayNumber.isNotEmpty
                        ? rawDisplayNumber
                        : table['display_number']?.toString() ?? '');

            // ✅ FIX: Transform API order into socket-compatible format with items array
            final itemName = menu != null 
                ? menu['name']?.toString() ?? order['item_desc']?.toString() ?? '' 
                : order['item_desc']?.toString() ?? '';
            
            final quantity = order['quantity']?.toString() ?? '1';
            final amount = order['amount']?.toString() ?? '0';
            final itemDesc = order['item_desc']?.toString() ?? '';
            final kotCategory = menu?['kotCategory']?.toString() ?? 'Other';

            // ✅ FIX: Create items array matching socket structure
            List<Map<String, dynamic>> itemsArray = [
              {
                "item_name": itemName,
                "quantity": quantity,
                "item_desc": itemDesc,
                "price": amount,
                "status": _normalizeStatus(order['status'] ?? 'Pending'),
                "id": order['id']?.toString() ?? '',
                "orderId": order['id']?.toString() ?? '', // ✅ ADD: Include orderId for completion matching
                "order_item_id": order['id']?.toString() ?? '',
                "menu_item_id": order['menuId']?.toString() ?? '',
                "orderItem": {
                  "id": order['id']?.toString() ?? '',
                  "orderId": order['id']?.toString() ?? '', // ✅ ADD: Include orderId in nested object
                  "quantity": quantity,
                  "price": amount,
                  "desc": itemDesc,
                },
                "menuItem": menu != null ? {
                  "id": menu['id']?.toString() ?? '',
                  "name": menu['name']?.toString() ?? '',
                  "kotCategory": kotCategory,
                } : null,
              }
            ];

            return {
              "id": order['id'].toString(),
              "serverId": order['userId']?.toString() ?? '',
              "table_number": (order['table_number'] ?? '').toString(),
              "amount": amount,
              "quantity": quantity,
              "item_desc": itemDesc,
              "restaurent_table_number": displayNumber,  // ✅ now uses the DB-persisted value
              "server": user != null ? (user['name']?.toString() ?? 'Unknown') : "Unknown",
              "time": DateFormat('hh:mm a').format(createdAtIst),
              "section_name": section != null
                  ? section['name']?.toString() ?? "Section Not Found"
                  : "Section Not Found",
              "item_name": itemName,
              "kotNumber": order['kotNumber']?.toString() ?? order['id']?.toString(),
              "status": _normalizeStatus(order['status'] ?? 'Pending'),
              "isShifted": shiftedFrom.isNotEmpty,          // ✅ driven by DB field
              "shifted_from_table": shiftedFrom,            // ✅ now populated from DB after backend fix
              "items": itemsArray,
            };
          }).toList();
          isLoading = false;
          hasErrorOccurred = false;
        });
      }
    } else {
      setState(() {
        isLoading = false;
        hasErrorOccurred = true;
      });
    }
  } catch (e) {
    if (timeoutTimer?.isActive ?? false) timeoutTimer?.cancel();
    debugPrint("Exception in fetchOrders: $e");
    if (mounted) {
      setState(() {
        isLoading = false;
        hasErrorOccurred = true;
      });
    }
  }
}


  // Send table notification
  Future<void> sendTableNotification({
    required String userId,
    required String tableNumber,
  }) async {
    try {
      final url = Uri.parse('${dotenv.env['API_URL']}/notify-user/');
      final body = {
        'userId': userId,
        'title': 'Order Ready for table ${tableNumber}',
        'message': 'Pick your order'
      };

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        _addDebugLog('✅ Notification sent successfully');
      } else {
        final error = jsonDecode(response.body);
        _addDebugLog('❌ Failed to send notification: ${error['message']}');
      }
    } catch (e) {
      _addDebugLog('❌ Error sending table notification: $e');
    }
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
                'Orders',
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
        body: isLoading
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



    // ----------------- Printer Status Indicator -----------------
Widget _buildPrinterStatusIndicator() {
  final bool isConnected = selectedPrinter != null;
  
  return GestureDetector(
    onTap: () {
      if (!isConnected && !isScanning) {
        _scanForPrinters();
        fetchOrders();
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
          if (!isConnected || isConnected) ...[
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
              color: const Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Please check your connection or try again.",
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              if (mounted) {
                setState(() {
                  isLoading = true;
                  hasErrorOccurred = false;
                });
                fetchOrders(); // Retry fetch
              }
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
              backgroundColor: const Color(0xFF2563EB),
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
          // if (userRole == 'Admin') _buildAddItemButton(context),
          const SizedBox(height: 12),
          ..._buildOrderCards(), // same as before
        ],
      ),
    );
  }




Widget _buildDesktopLayout() {
  List<Map<String, dynamic>> filteredOrders = orders.where((order) {
    // ✅ FIXED: Same filtering logic as mobile
    bool matchesCategory;
    if (selectedCategory == "All") {
      matchesCategory = order["status"] != "Completed";
    } else if (selectedCategory == "Completed") {
      matchesCategory = order["status"] == "Completed";
    } else {
      matchesCategory = order["status"] == selectedCategory;
    }
    
    final searchText = searchController.text.trim();
    bool matchesSearch = searchText.isEmpty ||
        (order["id"]?.toString().contains(searchText) ?? false) ||
        (order["kotNumber"]?.toString().contains(searchText) ?? false) ||
        (order["server"]?.toString().toLowerCase().contains(searchText.toLowerCase()) ?? false);
    return matchesCategory && matchesSearch;
  }).toList();
  
  final groupedOrders = _groupOrdersByKotNumber(filteredOrders);
  final consolidatedOrders = _createConsolidatedOrders(groupedOrders);

  return Padding(
    padding: const EdgeInsets.all(24),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          _buildTopItemGroupsRow(context),
          const SizedBox(height: 12),
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
    if (!mounted) return;
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
                    color: isSelected ? const Color(0xFFFCFAF8) : const Color(0xFFEDEBE9),
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

// Replace existing _acceptOrder with this version that only sends kotNumber to backend
Future<void> _acceptOrder(String kotNumber, [Map<String, dynamic>? order]) async {
  final url = Uri.parse('${dotenv.env['API_URL']}/orders/accept'); // use a generic accept endpoint or keep original path if needed
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


  Widget _buildSearchBar({bool dense = false}) {
    return SizedBox(
      height: dense ? 48 : MediaQuery.of(context).size.width * 0.14,
      child: TextField(
        controller: searchController,
        decoration: InputDecoration(
          hintText: "Search orders...",
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: const Color(0xFFFCFAF8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(
              color: Color.fromARGB(255, 141, 140, 140),
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






// Updated _reprintKOT method - exactly same logic as _printOrderNative
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

    // ---------- Print Main Header ONCE (before category loop) ----------
    List<int> headerBytes = [];
    headerBytes += generator.reset();
    headerBytes += [0x1B, 0x4D, 0x00]; // ESC M 0 - Select Font A

    // Main header: REPRINT KOT (only once)
    headerBytes += generator.text('REPRINT KOT', styles: PosStyles(
      align: PosAlign.center,
      bold: true,
      height: PosTextSize.size2,
      width: PosTextSize.size2,
    ));

    headerBytes += generator.text(dateTimeFormatted, styles: PosStyles(
      align: PosAlign.center,
      bold: false,
      height: PosTextSize.size1,
      width: PosTextSize.size1,
    ));

    headerBytes += generator.text('KOT $kotNo', styles: PosStyles(
      align: PosAlign.center,
      bold: false,
      height: PosTextSize.size1,
      width: PosTextSize.size1,
    ));

    // Table line
    String tablePart;
    if (tableNo.isNotEmpty && sectionName.isNotEmpty) {
      tablePart = 'Table No.: ${sectionName}-${tableNo}';
    } else if (tableNo.isNotEmpty) {
      tablePart = 'Table No.: $tableNo';
    } else {
      tablePart = 'Table No.: N/A';
    }
    headerBytes += generator.text(tablePart, styles: PosStyles(
      align: PosAlign.center,
      bold: true,
      height: PosTextSize.size1,
      width: PosTextSize.size1,
    ));

    // Separator line 1
    headerBytes += generator.text('_' * 38, styles: PosStyles(
      align: PosAlign.center,
    ));

    // Server info
    if (server.isNotEmpty) {
      headerBytes += generator.text('Captain: ${server.toUpperCase()}', styles: PosStyles(
        align: PosAlign.left,
        bold: false,
      ));
    }

    // Separator line 2
    headerBytes += generator.text('_' * 38, styles: PosStyles(
      align: PosAlign.center,
    ));

    // Send main header once
    try {
      await UsbPrinter.printRawBytes(
        vendorId: vendor,
        productId: product,
        bytes: Uint8List.fromList(headerBytes),
        timeoutMillis: 5000,
      );
      _addDebugLog('Printed REPRINT KOT header for order ${orderData['id']}');
    } catch (e) {
      _addDebugLog('Print header error: $e');
      if (context.mounted) {
        showTopNotification(context, 'Reprint Error', 'Failed to print KOT header: $e');
      }
    }

    // ---------- Iterate groups and print category items ----------
    for (final entry in grouped.entries) {
      final category = entry.key;
      final catItems = entry.value;

      if (catItems.isEmpty) continue;

      List<int> catBytes = [];
      catBytes += generator.reset();
      catBytes += [0x1B, 0x4D, 0x00]; // ESC M 0 - Select Font A

      // Category name header
      catBytes += generator.text(category.toUpperCase(), styles: PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size1,
        width: PosTextSize.size1,
      ));

      // Column headers
      String headerLine = 'Item'.padRight(20) + 'Note'.padRight(12) + 'Qty'.padLeft(6);
      catBytes += generator.text(headerLine, styles: PosStyles(
        align: PosAlign.left,
        bold: true,
      ));

      // Separator after columns
      catBytes += generator.text('_' * 38, styles: PosStyles(
        align: PosAlign.center,
      ));

      // Print items in this group
      for (int idx = 0; idx < catItems.length; idx++) {
        final it = catItems[idx];
        final name = (it['name'] ?? '').toString().trim();
        final rawNote = (it['note'] ?? '').toString().trim();
        final qty = (it['qty'] ?? '1').toString().trim();

        // Duplicate filtering
        String note = rawNote;
        if (rawNote.isNotEmpty && name.isNotEmpty) {
          final nameLower = name.toLowerCase().trim();
          final noteLower = rawNote.toLowerCase().trim();
          
          if (nameLower == noteLower) {
            note = '';
          } else if (nameLower.contains(noteLower) || noteLower.contains(nameLower)) {
            final shorter = nameLower.length < noteLower.length ? nameLower : noteLower;
            final longer = nameLower.length >= noteLower.length ? nameLower : noteLower;
            if (shorter.length >= longer.length * 0.7) {
              note = '';
            }
          }
        }

        if (note.isNotEmpty) {
          note = '($note)';
        }

        // Format: Item (padded to 20) | Note (padded to 12) | Qty (padded to 6, right-aligned)
        final nameField = name.length > 20 ? name.substring(0, 17) + '...' : name.padRight(20);
        final noteField = note.length > 12 ? note.substring(0, 9) + '...' : note.padRight(12);
        final qtyField = qty.padLeft(6);
        
        catBytes += generator.text('$nameField$noteField$qtyField', styles: PosStyles(
          align: PosAlign.left,
          bold: false,
        ));
      }

      // Final separator
      catBytes += generator.text('_' * 38, styles: PosStyles(
        align: PosAlign.center,
      ));

      // Total qty (right-aligned)
      final totalQty = catItems.fold<int>(0, (acc, it) => acc + (int.tryParse(it['qty'] ?? '0') ?? 0));
      catBytes += generator.text('Total Qty: $totalQty', styles: PosStyles(
        align: PosAlign.right,
        bold: true,
      ));

      // Spacing and cut
      catBytes += generator.feed(1);
      try {
        catBytes += generator.cut();
      } catch (_) {
        catBytes += generator.feed(5);
      }

      // Send category items to printer
      try {
        final result = await UsbPrinter.printRawBytes(
          vendorId: vendor,
          productId: product,
          bytes: Uint8List.fromList(catBytes),
          timeoutMillis: 5000,
        );
        _addDebugLog('Reprint KOT items printed for category="$category" (result=$result) for order ${orderData['id']}');
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



// New widget to display items with individual complete buttons
Widget _buildOrderItemsWithCompleteButtons(
  List<Map<String, dynamic>> items,
  Map<String, dynamic> parentOrder,
  Function(VoidCallback) setDialogState,
) {
  // Directly use `items` list in UI.
  return Column(
    children: [
      for (var item in items)
        _buildItemCardWithCompleteButton(
          item,
          parentOrder,
          items,
          setDialogState,
        )
    ],
  );
}


void _createCompletedOrderCard(Map<String, dynamic> completedItem, Map<String, dynamic> parentOrder) {
  // Extract item details
  String itemName = '';
  String quantity = '';
  String itemDesc = '';
  
  if (completedItem.containsKey('item_name')) {
    itemName = completedItem['item_name']?.toString() ?? '';
  }
  
  if (itemName.isEmpty || itemName == 'null') {
    itemName = completedItem['item_desc']?.toString() ??
        completedItem['orderItem']?['item_desc']?.toString() ??
        completedItem['menu']?['name']?.toString() ??
        completedItem['drink']?['name']?.toString() ??
        '';
  }
  
  if (itemName.isEmpty) {
    itemName = completedItem['orderItem']?['name']?.toString() ??
        completedItem['menuItem']?['name']?.toString() ??
        'Unnamed Item';
  }
  
  quantity = completedItem['quantity']?.toString() ??
      completedItem['orderItem']?['quantity']?.toString() ??
      completedItem['qty']?.toString() ??
      '1';
  
  itemDesc = completedItem['item_desc']?.toString() ??
      completedItem['orderItem']?['item_desc']?.toString() ??
      '';
  
  final itemPrice = completedItem['price']?.toString() ?? '0';
  
  // Generate a unique ID for the completed order card
  final completedOrderId = '${parentOrder['id']}_completed_${DateTime.now().millisecondsSinceEpoch}';
  
  // Create a new completed order card
  final completedOrder = {
    'id': completedOrderId,
    'kotNumber': parentOrder['kotNumber']?.toString() ?? completedOrderId,
    'serverId': parentOrder['serverId']?.toString() ?? '',
    'table_number': parentOrder['table_number']?.toString() ?? '',
    'amount': itemPrice,
    'quantity': quantity,
    'item_desc': itemDesc,
    'restaurent_table_number': parentOrder['table_number']?.toString() ?? '',
    'server': parentOrder['server']?.toString() ?? 'Unknown',
    'time': DateFormat('hh:mm a').format(DateTime.now()),
    'section_name': parentOrder['section_name']?.toString() ?? 'Section Not Found',
    'item_name': itemName,
    'status': 'Completed',
    'items': [
      {
        'item_name': itemName,
        'quantity': quantity,
        'item_desc': itemDesc,
        'price': itemPrice,
        'status': 'Completed',
      }
    ],
    'isPartialCompletion': true, // Flag to identify this as a partial completion
  };
  
  // Add the completed order to the orders list
  setState(() {
    orders.insert(0, completedOrder);
  });
  
  _addDebugLog('Created new completed order card: $completedOrderId for item: $itemName');
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
  String orderIdToComplete = '';

  debugPrint("\n\n🔍 DEBUG item: $item\n\n");

  // --- Extract item name ---
  if (item.containsKey('item_name')) {
    itemName = item['item_name']?.toString() ?? '';
  }

  if (itemName.isEmpty || itemName == 'null') {
    itemName = item['item_desc']?.toString() ??
        item['orderItem']?['item_desc']?.toString() ??
        item['menu']?['name']?.toString() ??
        item['drink']?['name']?.toString() ??
        '';
  }

  if (itemName.isEmpty) {
    itemName = item['orderItem']?['name']?.toString() ??
        item['menuItem']?['name']?.toString() ??
        'Unnamed Item';
  }

  // --- Extract quantity ---
  quantity = item['quantity']?.toString() ??
      item['orderItem']?['quantity']?.toString() ??
      item['qty']?.toString() ??
      '1';

  // --- Extract description ---
  itemDesc = item['item_desc']?.toString() ??
      item['orderItem']?['item_desc']?.toString() ??
      '';

  // ✅ Extract the Order.id
  orderIdToComplete = item['orderId']?.toString() ?? '';
  
  if (orderIdToComplete.isEmpty) {
    orderIdToComplete = item['orderItem']?['orderId']?.toString() ?? 
                        item['orderId']?.toString() ?? '';
  }

  if (orderIdToComplete.isEmpty) {
    try {
      final originalOrders = parentOrder['originalOrders'];
      if (originalOrders is List && originalOrders.isNotEmpty) {
        for (var orig in originalOrders) {
          if (orig is Map) {
            final origName = orig['item_name']?.toString() ?? '';
            if (origName == itemName) {
              orderIdToComplete = orig['id']?.toString() ?? '';
              break;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error extracting orderId: $e');
    }
  }

  debugPrint("✅ Order ID to complete: '$orderIdToComplete' for item: $itemName");

  // --- Duplicate note detection ---
  bool isDuplicateNote = false;
  if (itemDesc.isNotEmpty) {
    final nameLower = itemName.toLowerCase().trim();
    final descLower = itemDesc.toLowerCase().trim();

    if (nameLower == descLower) {
      isDuplicateNote = true;
    } else if (nameLower.contains(descLower) || descLower.contains(nameLower)) {
      final shorter = nameLower.length < descLower.length ? nameLower : descLower;
      final longer = nameLower.length >= descLower.length ? nameLower : descLower;
      if (shorter.length >= longer.length * 0.7) {
        isDuplicateNote = true;
      }
    }
  }
  
  // ✅ FIX: Check ITEM-LEVEL status, not parent order status
  String itemStatus = (item['status'] ??
        item['orderItem']?['status'] ??
        'pending')
    .toString()
    .trim()
    .toLowerCase();

  String orderStatus = (parentOrder['status'] ?? 'pending')
    .toString()
    .trim()
    .toLowerCase();

  // ✅ FIX: Show Done button if order is accepted AND this specific item is NOT completed
  final canComplete = orderStatus == 'accepted' && itemStatus != 'completed';

  debugPrint("🔍 Item: $itemName | Item Status: '$itemStatus' | Order Status: '$orderStatus' | Can Complete: $canComplete");

  // --- UI Card ---
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
                  if (itemDesc.isNotEmpty && !isDuplicateNote) ...[
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

            // Buttons Row
            Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                // Print button
                SizedBox(
                  width: 100,
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final itemForPrint = Map<String, dynamic>.from(parentOrder);
                      itemForPrint['items'] = [item];
                      itemForPrint['item_name'] = itemName;
                      itemForPrint['quantity'] = quantity;
                      itemForPrint['item_desc'] = itemDesc;

                      await _reprintKOT(itemForPrint);     
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
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                
                // ✅ FIX: Done button visibility based on item-level status
                if (canComplete)
                  SizedBox(
                    width: 100,
                    height: 40,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        debugPrint("=== COMPLETE ITEM DEBUG ===");
                        debugPrint("Order ID (final): $orderIdToComplete");
                        debugPrint("Item Name: $itemName");

                        try {
                          final url = Uri.parse(
                            '${dotenv.env['API_URL']}/orders/item/$orderIdToComplete/complete',
                          );

                          debugPrint("Request URL: $url");

                          final response = await http.put(
                            url,
                            headers: {'Content-Type': 'application/json'},
                          );

                          debugPrint("Response Status: ${response.statusCode}");
                          debugPrint("Response Body: ${response.body}");

                          if (response.statusCode == 200) {
                            final isLastItem = allItems.length <= 1;
                            
                            if (isLastItem) {
                              debugPrint("🚪 All items completed - marking entire order as completed");
                              
                              // ✅ Update main orders list
                              setState(() {
                                final orderIndex = orders.indexWhere((o) => 
                                  o['kotNumber']?.toString() == parentOrder['kotNumber']?.toString() ||
                                  o['id']?.toString() == parentOrder['id']?.toString()
                                );
                                
                                if (orderIndex >= 0) {
                                  orders[orderIndex]['status'] = 'Completed';
                                  orders[orderIndex]['items'] = [];
                                  orders[orderIndex]['quantity'] = '0';
                                  orders[orderIndex]['amount'] = '0';
                                  orders[orderIndex]['item_name'] = '';
                                  debugPrint("✅ Order ${orders[orderIndex]['kotNumber']} marked as Completed");
                                }
                              });

                              // Close dialog
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (context.mounted && Navigator.canPop(context)) {
                                  Navigator.pop(context);
                                }
                              });

                              // Show notification
                              Future.delayed(const Duration(milliseconds: 100), () {
                                if (context.mounted) {
                                  showTopNotification(
                                    context,
                                    'Order Completed',
                                    'All items in order ${parentOrder['kotNumber'] ?? parentOrder['id']} are complete',
                                  );
                                }
                              });

                              return;
                            } else {
                              // ✅ CRITICAL FIX: Only mark THIS SPECIFIC ITEM as completed
                              // Not all items in the list!
                              
                              // First update main state
                              setState(() {
                                final orderIndex = orders.indexWhere((o) => 
                                  o['kotNumber']?.toString() == parentOrder['kotNumber']?.toString() ||
                                  o['id']?.toString() == parentOrder['id']?.toString()
                                );
                                
                                if (orderIndex >= 0) {
                                  final orderItems = _normalizeItems(orders[orderIndex]['items']);
                                  
                                  // ✅ FIX: Only mark the SPECIFIC item that matches THIS orderIdToComplete
                                  for (var it in orderItems) {
                                    final ids = [
                                      it['orderId']?.toString(),
                                      it['id']?.toString(),
                                      it['orderItem']?['orderId']?.toString(),
                                      it['orderItem']?['id']?.toString(),
                                    ];
                                    
                                    // ✅ CRITICAL: Only mark THIS item, not others
                                    if (ids.contains(orderIdToComplete)) {
                                      it['status'] = 'completed';
                                      if (it['orderItem'] is Map) {
                                        it['orderItem']['status'] = 'completed';
                                      }
                                      debugPrint("✅ Marked item ${it['item_name']} as completed");
                                      break; // ✅ IMPORTANT: Stop after marking ONE item
                                    }
                                  }
                                  
                                  // Remove only the completed item
                                  orderItems.removeWhere((it) {
                                    final ids = [
                                      it['orderId']?.toString(),
                                      it['id']?.toString(),
                                      it['orderItem']?['orderId']?.toString(),
                                      it['orderItem']?['id']?.toString(),
                                    ];
                                    return ids.contains(orderIdToComplete);
                                  });
                                  
                                  orders[orderIndex]['items'] = orderItems;
                                  
                                  // Recalculate totals
                                  int totalQty = 0;
                                  int totalAmount = 0;
                                  for (var it in orderItems) {
                                    totalQty += int.tryParse((it['quantity'] ?? '1').toString()) ?? 1;
                                    totalAmount += int.tryParse((it['price'] ?? '0').toString()) ?? 0;
                                  }
                                  
                                  orders[orderIndex]['quantity'] = totalQty.toString();
                                  orders[orderIndex]['amount'] = totalAmount.toString();
                                  
                                  if (orderItems.isNotEmpty) {
                                    orders[orderIndex]['item_name'] = orderItems.length == 1
                                        ? (orderItems.first['item_name'] ?? 'Item')
                                        : '${orderItems.first['item_name'] ?? 'Item'} +${orderItems.length - 1} more';
                                  }
                                }
                              });
                              
                              // Then update dialog state
                              setDialogState(() {
                                // ✅ CRITICAL FIX: Only mark THIS SPECIFIC ITEM as completed
                                for (var it in allItems) {
                                  final ids = [
                                    it['orderId']?.toString(),
                                    it['id']?.toString(),
                                    it['orderItem']?['orderId']?.toString(),
                                    it['orderItem']?['id']?.toString(),
                                  ];
                                  
                                  // ✅ CRITICAL: Only mark THIS item, not others
                                  if (ids.contains(orderIdToComplete)) {
                                    it['status'] = 'completed';
                                    if (it['orderItem'] is Map) {
                                      it['orderItem']['status'] = 'completed';
                                    }
                                    debugPrint("✅ Dialog: Marked item ${it['item_name']} as completed");
                                    break; // ✅ IMPORTANT: Stop after marking ONE item
                                  }
                                }
                                
                                // Remove only the completed item from allItems
                                allItems.removeWhere((it) {
                                  final ids = [
                                    it['orderId']?.toString(),
                                    it['id']?.toString(),
                                    it['orderItem']?['orderId']?.toString(),
                                    it['orderItem']?['id']?.toString(),
                                  ];
                                  return ids.contains(orderIdToComplete);
                                });
                                
                                debugPrint("✅ Remaining items in dialog: ${allItems.length}");
                              });

                              // Show notification
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (context.mounted) {
                                  showTopNotification(
                                    context,
                                    'Item Completed',
                                    '$itemName marked as complete',
                                  );
                                }
                              });
                            }
                          } else {
                            // Handle error response
                            try {
                              final errorData = jsonDecode(response.body);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (context.mounted) {
                                  showTopNotification(
                                    context,
                                    'Error',
                                    errorData['message'] ?? 'Failed to complete item',
                                  );
                                }
                              });
                            } catch (_) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (context.mounted) {
                                  showTopNotification(
                                    context,
                                    'Error',
                                    'Failed to complete item (HTTP ${response.statusCode})',
                                  );
                                }
                              });
                            }
                          }
                        } catch (e, st) {
                          debugPrint("❌ Exception: $e");
                          debugPrint("Stack trace: $st");
                          
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (context.mounted) {
                              showTopNotification(
                                context,
                                'Error',
                                'Failed to complete item: ${e.toString().split('\n').first}',
                              );
                            }
                          });
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
                  )
              ],
            ),
          ],
        ),
      ],
    ),
  );
}




Future<void> safePop(BuildContext context) async {
  if (!Navigator.canPop(context)) return;

  Navigator.pop(context);

  // Wait until the pop animation fully finishes
  await Future.delayed(const Duration(milliseconds: 50));
}



// Replace the existing _showOrderDetails method with this improved version

void _showOrderDetails(BuildContext context, Map<String, dynamic> order) {
  _addDebugLog("\n\n Showing order details: ${order['items'].toString()}\n\n");
  _addDebugLog("\n\n Showing order : ${order}\n\n");

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          // ✅ FIX: Get ALL orders with matching kotNumber from main orders list
          final kotNumber = order['kotNumber']?.toString() ?? order['id']?.toString() ?? '';
          
          // ✅ FIX: Find ALL orders with this KOT number (not just first match)
          final matchingOrders = orders.where((o) {
            final oKot = o['kotNumber']?.toString() ?? o['id']?.toString();
            final status = o['status']?.toString().toLowerCase();
            return oKot == kotNumber && status != 'completed';
          }).toList();
          
          // ✅ FIX: Collect items from ALL matching orders
          List<Map<String, dynamic>> dialogItems = [];
          Map<String, dynamic> currentOrder = order; // Use passed order as fallback
          
          if (matchingOrders.isNotEmpty) {
            // Use the first matching order for display metadata
            currentOrder = matchingOrders.first;
            
            // ✅ FIX: Aggregate items from all orders with this KOT number
            for (var matchedOrder in matchingOrders) {
              final orderItems = _normalizeItems(matchedOrder['items'])
                  .where((item) =>
                      item['status']?.toString().toLowerCase() != 'completed')
                  .toList();

              if (orderItems.isNotEmpty) {
                dialogItems.addAll(orderItems);
                _addDebugLog('Added ${orderItems.length} active items from order ${matchedOrder['id']}');
              }
            }

          } else {
            // Fallback: use items from passed order
            dialogItems = _normalizeItems(order['items']);
          }
          
          _addDebugLog('Total items for KOT $kotNumber: ${dialogItems.length}');
          
          // Ensure single items have status
          if (dialogItems.length == 1) {
            dialogItems[0]['status'] ??= currentOrder['status'];
          }

          // ✅ Auto-close dialog if no items and completed
          if (dialogItems.isEmpty && currentOrder['status'] == 'Completed') {
            _addDebugLog("No items remaining in order $kotNumber — auto-closing dialog");
            
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (Navigator.canPop(dialogContext)) {
                Navigator.of(dialogContext).pop();
              }
            });
            
            return SizedBox(
              height: 200,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      currentOrder['status'] == 'Completed' 
                          ? 'Order Completed!' 
                          : 'No items',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

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
                  _buildDetailRow("Order ID", '#${currentOrder["kotNumber"] ?? currentOrder["id"]}'),
                  _buildDetailRow("Section", currentOrder["section_name"]?.toString() ?? "N/A"),
                  _buildDetailRow("Table", currentOrder["restaurent_table_number"]?.toString() ?? "N/A"),
                  _buildDetailRow("Server", currentOrder["server"]?.toString() ?? "N/A"),
                  _buildDetailRow("Time", currentOrder["time"]?.toString() ?? "N/A"),
                  _buildDetailRow("Status", currentOrder["status"]?.toString() ?? "N/A"),
                  const SizedBox(height: 16),

                  // Common Accept Button (only if status is Pending)
                  if (currentOrder["status"] == "Pending")
                    Center(
                      child: SizedBox(
                        width: 240,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final kotNo = currentOrder['kotNumber']?.toString() ?? currentOrder['id']?.toString() ?? '';
                            
                            if (!_printedKotNumbers.contains(kotNo)) {
                              _addDebugLog('Manual accept - printing KOT $kotNo');
                              _printedKotNumbers.add(kotNo);
                              await _printOrderNative(currentOrder).catchError((e) {
                                _addDebugLog('Manual print error: $e');
                                _printedKotNumbers.remove(kotNo);
                              });
                            }
                            
                            await _acceptOrder(kotNo, currentOrder);

                            if (context.mounted) {
                              setDialogState(() {
                                currentOrder["status"] = "Accepted";
                              });
                              _updateOrderStatus(currentOrder, "Accepted");
                              showTopNotification(context, 'Accepted', 'Order #$kotNo accepted');
                            }
                          },
                          icon: const Icon(Icons.access_time, color: Colors.white),
                          label: Text(
                            "Accept All Order",
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

                  if (currentOrder["status"] == "Pending")
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
                      dialogItems, // ✅ FIX: Use aggregated items from all matching orders
                      currentOrder,
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
                          Navigator.pop(dialogContext);
                          await Future.delayed(Duration.zero);

                          try {
                            // ✅ FIX: Create reprint data with all items
                            final orderForReprint = Map<String, dynamic>.from(currentOrder);
                            orderForReprint['items'] = dialogItems; // ✅ Use all aggregated items
                            await _reprintKOT(orderForReprint);

                            if (context.mounted) {
                              showTopNotification(
                                context,
                                'Reprint KOT',
                                'KOT #${currentOrder["kotNumber"] ?? currentOrder["id"]} reprinted successfully',
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
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 16),
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

List<Widget> _buildOrderCards() {
  List<Map<String, dynamic>> filteredOrders = orders.where((order) {
    final orderStatus = order['status']?.toString() ?? 'Pending';
    
    // ✅ FIX: For Completed tab, allow orders with empty items
    // (they were completed and items removed, OR all items marked as completed)
    if (selectedCategory == "Completed") {
      return orderStatus == "Completed";
    }
    
    // ✅ For non-Completed tabs, filter out orders with no active items
    final items = _normalizeItems(order['items']);
    
    // Count active (non-completed) items
    final activeItems = items.where((item) {
      final itemStatus = item['status']?.toString().toLowerCase() ?? 'pending';
      return itemStatus != 'completed';
    }).toList();
    
    // // 🔥 HARD REMOVE: no active items AND not in Completed status → hide card
    // if (activeItems.isEmpty && orderStatus != "Completed") {
    //   return false;
    // }

    // // 🔥 HARD REMOVE: quantity zero for non-completed orders
    // if (orderStatus != "Completed") {
    //   final qty = int.tryParse(order['quantity']?.toString() ?? '0') ?? 0;
    //   if (qty <= 0) return false;
    // }

    // 🔥 HARD REMOVE: no active items AND not in Completed status → hide card
    if (activeItems.isEmpty && orderStatus != "Completed") {
      return false;
    }

    // 🔥 HARD REMOVE: quantity zero for non-completed orders
    // ✅ FIX: Never filter out completed orders by quantity
    if (orderStatus != "Completed" && selectedCategory != "Completed") {
      final qty = int.tryParse(order['quantity']?.toString() ?? '0') ?? 0;
      if (qty <= 0) return false;
    }

    // -------------------------
    // Category filtering
    // -------------------------
    bool matchesCategory;
    if (selectedCategory == "All") {
      matchesCategory = orderStatus != "Completed";
    } else if (selectedCategory == "Completed") {
      matchesCategory = orderStatus == "Completed";
    } else {
      matchesCategory = orderStatus == selectedCategory;
    }

    // -------------------------
    // Search filtering
    // -------------------------
    final searchText = searchController.text.trim().toLowerCase();
    bool matchesSearch = searchText.isEmpty ||
        (order["id"]?.toString().contains(searchText) ?? false) ||
        (order["kotNumber"]?.toString().contains(searchText) ?? false) ||
        (order["server"]?.toString().toLowerCase().contains(searchText) ?? false);

    return matchesCategory && matchesSearch;
  }).toList();

  // 🧠 Group + consolidate orders
  final groupedOrders = _groupOrdersByKotNumber(filteredOrders);
  final consolidatedOrders = _createConsolidatedOrders(groupedOrders);

  // ✅ For Completed tab, keep all completed orders even if they have no items
  final visibleOrders = selectedCategory == "Completed"
      ? consolidatedOrders // Show all completed orders
      : consolidatedOrders.where((order) {
          // For other tabs, require active items
          final items = _normalizeItems(order['items']);
          final activeItems = items.where((item) {
            final itemStatus = item['status']?.toString().toLowerCase() ?? 'pending';
            return itemStatus != 'completed';
          }).toList();
          return activeItems.isNotEmpty;
        }).toList();

  return visibleOrders.map((order) => _buildOrderCard(order)).toList();
}


// Add this method to group orders by kotNumber
Map<String, List<Map<String, dynamic>>> _groupOrdersByKotNumber(
    List<Map<String, dynamic>> orders) {
  Map<String, List<Map<String, dynamic>>> grouped = {};

  for (var order in orders) {
    if (order['skipConsolidation'] == true ||
        order['isShifted'] == true) {
      // ✅ FIX: Use the real kotNumber as key, not the DB id
      // This ensures displayKotNumber in _buildOrderCard shows the correct KOT
      final key = order['kotNumber']?.toString() ?? order['id'].toString();
      grouped[key] = [order];
      continue;
    }

    final kotNumber = order['kotNumber']?.toString() ?? 'unknown';
    grouped.putIfAbsent(kotNumber, () => []);
    grouped[kotNumber]!.add(order);
  }

  return grouped;
}
// Add this method to merge grouped orders into consolidated cards

List<Map<String, dynamic>> _createConsolidatedOrders(Map<String, List<Map<String, dynamic>>> groupedOrders) {
  List<Map<String, dynamic>> consolidatedOrders = [];
  
  for (var entry in groupedOrders.entries) {
  final kotNumber = entry.key;
  final ordersInGroup = entry.value;

  if (ordersInGroup.isEmpty) continue;

  // // ✅ FIX: Skip KOT if all orders are completed
  // final hasActiveOrders = ordersInGroup.any((order) {
  //   final status = order['status']?.toString() ?? 'Pending';
  //   return status != 'Completed';
  // });

  // if (!hasActiveOrders) {
  //   _addDebugLog('Skipping KOT $kotNumber because all orders are completed');
  //   continue;
  // }

  // Use the first order as the base template
  final baseOrder = Map<String, dynamic>.from(ordersInGroup.first);
    
    // Collect all items from all orders in this KOT group
    List<Map<String, dynamic>> allItems = [];
    int totalAmount = 0;
    int totalQuantity = 0;
    Set<String> allStatuses = {};
    
    for (var order in ordersInGroup) {
      // ✅ CRITICAL FIX: Store the parent order ID for each item
      final parentOrderId = order['id']?.toString() ?? '';
      
      _addDebugLog('Processing order $parentOrderId in KOT group $kotNumber');
      
      // Add items from this order
      final orderItems = _normalizeItems(order['items']);
      if (orderItems.isNotEmpty) {
        // ✅ Inject orderId into each item if missing
        for (var item in orderItems) {
          // Check if item already has a valid orderId
          final existingOrderId = item['orderId']?.toString() ?? '';
          final existingId = item['id']?.toString() ?? '';
          
          if (existingOrderId.isEmpty && existingId.isEmpty) {
            // Item doesn't have order ID - inject the parent order ID
            item['orderId'] = parentOrderId;
            item['id'] = parentOrderId; // Also set as 'id' for compatibility
            _addDebugLog('  → Injected orderId=$parentOrderId into item: ${item['item_name']}');
          } else {
            _addDebugLog('  → Item already has orderId=$existingOrderId or id=$existingId');
          }
        }
        allItems.addAll(orderItems);
      } else {
        // Fallback: create item from top-level order data
        final fallbackItem = {
          'item_name': order['item_name']?.toString() ?? 'Unknown Item',
          'quantity': order['quantity']?.toString() ?? '1',
          'price': order['amount']?.toString() ?? '0',
          'item_desc': order['item_desc']?.toString() ?? '',
          'status': order['status']?.toString() ?? 'Pending',
          'orderId': parentOrderId, // ✅ Include parent order ID
          'id': parentOrderId, // ✅ Also set as 'id'
        };
        allItems.add(fallbackItem);
        _addDebugLog('  → Created fallback item with orderId=$parentOrderId');
      }
      
      // Accumulate totals
      totalAmount += int.tryParse(order['amount']?.toString() ?? '0') ?? 0;
      totalQuantity += int.tryParse(order['quantity']?.toString() ?? '0') ?? 0;
      
      // Track all statuses in this KOT group
      final status = order['status']?.toString() ?? 'Pending';
      allStatuses.add(status);
    }
    
    // Determine the consolidated status (most advanced status wins)
    String consolidatedStatus = 'Pending';
    if (allStatuses.contains('Completed')) {
      consolidatedStatus = 'Completed';
    } else if (allStatuses.contains('Accepted')) {
      consolidatedStatus = 'Accepted';
    }
    
    // Create consolidated item name summary
    String itemNameSummary = '';
    if (allItems.isNotEmpty) {
      if (allItems.length == 1) {
        itemNameSummary = allItems.first['item_name'] ?? 'Unknown Item';
      } else {
        itemNameSummary = '${allItems.first['item_name'] ?? 'Item'} +${allItems.length - 1} more';
      }
    }
    
    _addDebugLog('Created consolidated order for KOT $kotNumber with ${allItems.length} items');
    
    // Create the consolidated order
    final consolidatedOrder = {
      ...baseOrder,
      'id': kotNumber, // Use kotNumber as the ID for the consolidated order
      'kotNumber': kotNumber,
      'items': allItems,
      'amount': totalAmount.toString(),
      'quantity': totalQuantity.toString(),
      'item_name': itemNameSummary,
      'status': consolidatedStatus,
      'orderCount': ordersInGroup.length, // Track how many original orders are in this group
      'originalOrders': ordersInGroup, // Keep reference to original orders for detailed view
    };
    
    consolidatedOrders.add(consolidatedOrder);
  }
  
  return consolidatedOrders;
}


List<Map<String, dynamic>> _normalizeItems(dynamic raw) {
  try {
    if (raw == null) return <Map<String, dynamic>>[];
    if (raw is List) {
      // cast each element to Map<String, dynamic> where possible
      return raw.map<Map<String, dynamic>>((e) {
        if (e is Map<String, dynamic>) return e;
        if (e is Map) return Map<String, dynamic>.from(e);
        // if element is a JSON string, try decode
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
      // try decode stringified JSON list
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map<Map<String, dynamic>>((e) {
          if (e is Map<String, dynamic>) return e;
          if (e is Map) return Map<String, dynamic>.from(e);
          return <String, dynamic>{};
        }).toList();
      }
      return <Map<String, dynamic>>[];
    }
  } catch (e) {
    _addDebugLog('Error normalizing items: $e');
  }
  return <Map<String, dynamic>>[];
}


Widget _buildOrderCard(Map<String, dynamic> order) {
  final isLargeScreen = MediaQuery.of(context).size.width > 800;
  final statusColor = _getStatusColor(order["status"]?.toString() ?? '');
  final isShifted = order['isShifted'] == true;
  final shiftedFrom = order['shifted_from_table']?.toString() ?? '';
  final isCompleted = order['status']?.toString() == 'Completed';
  
  // ✅ Format KOT number with _SHIFTED suffix for shifted orders
  final kotNumber = order["kotNumber"] ?? order["id"];
  final displayKotNumber = isShifted ? "${kotNumber}_SHIFTED" : kotNumber;

  // --- Normalize items robustly (List, or JSON string) ---
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

  // ✅ For completed orders, show ALL items (including completed ones)
  // For other orders, show only ACTIVE items
  List<dynamic> displayItemsList;
  if (isCompleted) {
    // Show all items for completed orders
    displayItemsList = itemsList;
  } else {
    // Show only active items for ongoing orders
    displayItemsList = itemsList.where((it) {
      if (it is! Map) return true;
      final itemStatus = it['status']?.toString().toLowerCase() ?? 'pending';
      return itemStatus != 'completed';
    }).toList();
  }

  // If no structured items, try to build a fallback single-item view
  if (displayItemsList.isEmpty && !isCompleted) {
    final topName = (order['item_name'] ?? order['name'] ?? '').toString().trim();
    final topQty = (order['quantity'] ?? order['qty'] ?? '').toString().trim();
    final topDesc = (order['item_desc'] ?? order['description'] ?? '').toString().trim();

    if (topName.isNotEmpty && topName != 'Completed') {
      displayItemsList = [
        {
          'item_name': topName,
          'quantity': topQty.isNotEmpty ? topQty : '1',
          'item_desc': topDesc,
        }
      ];
    }
  }

  // --- Limit to 3 items for display ---
  final displayItems = displayItemsList.take(3).toList();
  final hasMoreItems = displayItemsList.length > 3;

  // Build widgets for display items
  List<Widget> itemWidgets = [];
  
  // ✅ Special handling for completed orders with no items
  if (isCompleted && displayItems.isEmpty) {
    itemWidgets.add(
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          children: [
            Icon(Icons.check_circle, size: 14, color: Colors.green[700]),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Order Completed',
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.green[700],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  } else {
    // Normal item display
    for (var it in displayItems) {
      String name = '';
      String note = '';
      String qty = '';

      if (it is Map) {
        name = (it['item_name'] ?? it['name'] ?? '').toString().trim();
        note = (it['item_desc'] ?? it['description'] ?? '').toString().trim();
        qty = (it['quantity'] ?? it['qty'] ?? '').toString().trim();

        // Nested shapes
        if (name.isEmpty && it['menuItem'] is Map) {
          name = (it['menuItem']['name'] ?? '').toString().trim();
        }
        if (note.isEmpty && it['orderItem'] is Map) {
          note = (it['orderItem']['desc'] ?? it['orderItem']['description'] ?? '').toString().trim();
        }
        if (qty.isEmpty && it['orderItem'] is Map) {
          qty = (it['orderItem']['quantity'] ?? '').toString().trim();
        }
      } else {
        name = it?.toString() ?? '';
        qty = '1';
      }

      if (name.isEmpty) name = 'Unnamed Item';
      if (qty.isEmpty) qty = '1';

      // Check if note/description is the same as the name
      bool isDuplicateNote = false;
      if (note.isNotEmpty) {
        final nameLower = name.toLowerCase().trim();
        final noteLower = note.toLowerCase().trim();
        
        if (nameLower == noteLower) {
          isDuplicateNote = true;
        } else if (nameLower.contains(noteLower) || noteLower.contains(nameLower)) {
          final shorter = nameLower.length < noteLower.length ? nameLower : noteLower;
          final longer = nameLower.length >= noteLower.length ? nameLower : noteLower;
          if (shorter.length >= longer.length * 0.7) {
            isDuplicateNote = true;
          }
        }
      }

      final displayName = (note.isNotEmpty && !isDuplicateNote) ? '$name ($note)' : name;

      // ✅ Show completed items with strikethrough
      final itemStatus = (it is Map ? it['status']?.toString().toLowerCase() : null) ?? 'pending';
      final isItemCompleted = itemStatus == 'completed';

      itemWidgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isItemCompleted ? Icons.check_circle : Icons.fastfood,
                size: 14,
                color: isItemCompleted ? Colors.green[700] : null,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  displayName,
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    decoration: isItemCompleted ? TextDecoration.lineThrough : null,
                    color: isItemCompleted ? Colors.grey : null,
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
                  decoration: isItemCompleted ? TextDecoration.lineThrough : null,
                  color: isItemCompleted ? Colors.grey : null,
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  // --- Add "View all" link if more than 3 items ---
  if (hasMoreItems) {
    itemWidgets.add(
      InkWell(
        onTap: () => _showOrderDetails(context, order),
        child: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            "+${displayItemsList.length - 3} more",
            style: GoogleFonts.poppins(
              fontSize: 10,
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
            // Top KOT Number
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
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // ✅ For completed orders, show amount as strikethrough
                if (!isCompleted || (order["amount"]?.toString() ?? '0') != '0')
                  Text(
                    "₹ ${order["amount"] ?? ''}",
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      color: isCompleted ? Colors.grey : Colors.green[700],
                      decoration: isCompleted ? TextDecoration.lineThrough : null,
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 4),

            // Server & Time
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  order["server"]?.toString() ?? "Unknown",
                  style: GoogleFonts.poppins(fontSize: 11),
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

            // Show status above item if large screen
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
                    fontSize: 9,
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],

            // Items list
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: itemWidgets,
            ),

            // For mobile: Show status at bottom
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
                      fontSize: 9,
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






// Updated _getTopItemGroups method to count individual items separately
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

        // Extract item name from various possible fields
        String itemName = '';
        if (item.containsKey('item_name')) {
          itemName = item['item_name']?.toString() ?? '';
        } else if (item['menuItem'] is Map) {
          itemName = (item['menuItem']['name'] ?? '').toString();
        } else if (item.containsKey('name')) {
          itemName = item['name']?.toString() ?? '';
        }

        if (itemName.isEmpty) itemName = 'Unnamed Item';

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
      final itemName = order["item_name"]?.toString() ?? "Unnamed";
      
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

  Widget _buildTopItemGroupsRow(BuildContext context) {
    final topItems = _getTopItemGroups(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        children: topItems.map((item) {
          final icon = _getIconForItem(item['name']?.toString() ?? '');
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
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
                    fontSize: 10.5,
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
        return const Color.fromRGBO(255, 200, 1, 1);
      case "Accepted":
        return const Color.fromARGB(255, 60, 99, 207);
      case "Completed":
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}



