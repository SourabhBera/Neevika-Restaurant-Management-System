import 'package:Neevika/screens/Food/menu/MenuScreen.dart';
import 'package:Neevika/utils/print_service_stub.dart'
    if (dart.library.html) 'package:Neevika/utils/print_service_web.dart'
    as print_service;
import 'package:Neevika/widgets/sidebar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:dotted_line/dotted_line.dart';
import 'package:Neevika/screens/Tables/GenerateBillScreen.dart'; // Make sure to add dotted_line package in pubspec.yaml
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

class ViewTableScreen extends StatefulWidget {
  const ViewTableScreen({super.key});

  @override
  State<ViewTableScreen> createState() => _ViewTableScreenState();
}

class _ViewTableScreenState extends State<ViewTableScreen> {
  final GlobalKey<ScaffoldMessengerState> rootScaffoldKey =
      GlobalKey<ScaffoldMessengerState>();

  late IO.Socket socket;
  bool isLoading = true;
  bool hasErrorOccurred = false;
  List<dynamic> sections = [];
  Map<String, dynamic> tableData = {};
  int totalAmount = 0;
  String userRole = '';
  String userName = '';
  String userId = '';
  String token = '';
  int _selectedSectionIndex = 0;
  String _tableFilter = 'all';
  final ScrollController _sectionScrollController = ScrollController();
  DateTime? _lastUpdateTime;
  static const _updateDebounceMs = 300;

  // Add this helper method at the top of your _ViewTableScreenState class
  double _roundAmount(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble().roundToDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      return parsed?.roundToDouble() ?? 0.0;
    }
    return 0.0;
  }

  // Replace the calculateTaxedAmount method with this rounded version:
  double calculateTaxedAmount(Map<String, dynamic> item, String type) {
    final quantity =
        (item['quantity'] is num)
            ? (item['quantity'] as num).toInt()
            : int.tryParse(item['quantity']?.toString() ?? '') ?? 1;

    // Use amount_per_item if available (already taxed)
    if (item['amount_per_item'] != null) {
      final perItem =
          (item['amount_per_item'] is num)
              ? (item['amount_per_item'] as num).toDouble()
              : double.tryParse(item['amount_per_item']?.toString() ?? '') ??
                  0.0;
      if (perItem > 0) return (perItem * quantity).roundToDouble();
    }

    if (type == 'food') {
      if (item['menu']?['price'] is num) {
        final basePrice = (item['menu']['price'] as num).toDouble();
        return (basePrice * quantity * 1.05).roundToDouble();
      }
      // amount is already the taxed total — use directly
      if (item['amount'] is num) {
        return ((item['amount'] as num).toDouble()).roundToDouble();
      }
      return 0.0;
    } else if (type == 'drink') {
      if (item['drink']?['price'] is num) {
        final basePrice = (item['drink']['price'] as num).toDouble();
        final applyVAT =
            item['drink']?['applyVAT'] == true ||
            item['drink']?['applyVat'] == true ||
            item['applyVat'] == true ||
            item['applyVAT'] == true ||
            item['is_custom'] == true;
        return applyVAT
            ? (basePrice * quantity * 1.10).roundToDouble()
            : (basePrice * quantity * 1.05).roundToDouble();
      }
      // amount is already the taxed total — use directly
      if (item['amount'] is num) {
        return ((item['amount'] as num).toDouble()).roundToDouble();
      }
      return 0.0;
    }

    return ((item['amount'] ?? 0) as num).toDouble().roundToDouble();
  }

  double calculateAmountPerItem(Map<String, dynamic> item, String type) {
    final quantity =
        (item['quantity'] is num)
            ? (item['quantity'] as num).toInt()
            : int.tryParse(item['quantity']?.toString() ?? '') ?? 1;

    if (quantity == 0) return 0.0;

    // amount_per_item is already taxed — use directly
    if (item['amount_per_item'] != null) {
      final perItem =
          (item['amount_per_item'] is num)
              ? (item['amount_per_item'] as num).toDouble()
              : double.tryParse(item['amount_per_item']?.toString() ?? '') ??
                  0.0;
      if (perItem > 0) return perItem;
    }

    if (type == 'food') {
      if (item['menu']?['price'] is num) {
        final basePrice = (item['menu']['price'] as num).toDouble();
        return basePrice * 1.05;
      }
      // amount is already taxed total — derive per-item
      if (item['amount'] is num && quantity > 0) {
        return (item['amount'] as num).toDouble() / quantity;
      }
      return 0.0;
    } else if (type == 'drink') {
      if (item['drink']?['price'] is num) {
        final basePrice = (item['drink']['price'] as num).toDouble();
        final applyVAT =
            item['drink']?['applyVAT'] == true ||
            item['drink']?['applyVat'] == true ||
            item['applyVat'] == true ||
            item['applyVAT'] == true ||
            item['is_custom'] == true;
        return applyVAT ? basePrice * 1.10 : basePrice * 1.05;
      }
      // amount is already taxed total — derive per-item
      if (item['amount'] is num && quantity > 0) {
        return (item['amount'] as num).toDouble() / quantity;
      }
      return 0.0;
    }

    return 0.0;
  }

  Future<void> fetchSections() async {
    setState(() {
      isLoading = true;
      hasErrorOccurred = false;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      token = prefs.getString('jwtToken')!;

      if (token == null) {
        print('No token found. User might not be logged in.');
        return;
      }

      final decodedToken = JwtDecoder.decode(token);
      userId = decodedToken['id'].toString();
      userRole = decodedToken['role'];
      print(userRole);
      debugPrint("UserId: $userId");
      final response = await http.get(
        Uri.parse('${dotenv.env['API_URL']}/sections/'),
      );

      if (response.statusCode == 200) {
        // Wait only 0.5 seconds on success
        await Future.delayed(const Duration(milliseconds: 500));
        // debugPrint("Test: ${json.decode(response.body)}");
        setState(() {
          sections = json.decode(response.body);
          isLoading = false;
          _normalizeSectionAmounts(); // ← ADD THIS
        });

        fetchUserName();
      } else {
        // Wait 5 seconds on error
        await Future.delayed(const Duration(seconds: 5));
        setState(() {
          hasErrorOccurred = true;
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error: $e');
      // Wait 5 seconds on exception
      await Future.delayed(const Duration(seconds: 5));
      setState(() {
        hasErrorOccurred = true;
        isLoading = false;
      });
    }
  }

  Future<void> fetchUserName() async {
    try {
      final response = await http.get(
        Uri.parse('${dotenv.env['API_URL']}/auth/user_details/$userId'),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        // Wait only 0.5 seconds on success

        await Future.delayed(const Duration(milliseconds: 500));
        setState(() {
          final userDetails = json.decode(response.body);
          String fullName = userDetails['name'] ?? '';

          // Split the full name by space and take the first part (first name)
          userName = fullName.split(' ')[0];

          isLoading = false;
        });
      } else {
        // Wait 5 seconds on error
        await Future.delayed(const Duration(seconds: 5));
        setState(() {
          hasErrorOccurred = true;
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error: $e');
      // Wait 5 seconds on exception
      await Future.delayed(const Duration(seconds: 5));
      setState(() {
        hasErrorOccurred = true;
        isLoading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  // ✅ OPTIMIZATION: Single initialization method
  Future<void> _initializeScreen() async {
    await _loadUserData();
    connectSocket();
    await fetchSections();
  }

  // ✅ OPTIMIZATION: Load user data once
  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwtToken');
      if (token == null) return;

      final decodedToken = JwtDecoder.decode(token);
      setState(() {
        userId = decodedToken['id'].toString();
        userRole = decodedToken['role'];
      });
    } catch (e) {
      debugPrint('Error loading user data: $e');
    }
  }

  // ✅ OPTIMIZATION: Consolidated amount calculation with rounding
  double _calculateItemAmount(Map<String, dynamic> item, String type) {
    final quantity = _parseQuantity(item['quantity']);
    if (quantity == 0) return 0.0;

    // Get stored amount_per_item if available (already includes tax)
    if (item['amount_per_item'] != null) {
      final amountPerItem = _parseDouble(item['amount_per_item']);
      if (amountPerItem > 0) return (amountPerItem * quantity).roundToDouble();
    }

    // Use base price from menu/drink if available (apply tax)
    if (type == 'food' && item['menu']?['price'] != null) {
      final basePrice = _parseDouble(item['menu']['price']);
      return double.parse(
        (basePrice * quantity * 1.05).toStringAsFixed(2),
      ).roundToDouble();
    } else if (type == 'drink' && item['drink']?['price'] != null) {
      final basePrice = _parseDouble(item['drink']['price']);
      final applyVAT =
          item['drink']?['applyVAT'] == true ||
          item['drink']?['applyVat'] == true ||
          item['applyVat'] == true ||
          item['applyVAT'] == true ||
          item['is_custom'] == true;
      final taxRate = applyVAT ? 1.10 : 1.05;
      return double.parse(
        (basePrice * quantity * taxRate).toStringAsFixed(2),
      ).roundToDouble();
    }

    // Last resort: use stored amount directly (treat as already-taxed total)
    if (item['amount'] != null) {
      final storedAmount = _parseDouble(item['amount']);
      if (storedAmount > 0) return storedAmount.roundToDouble();
    }

    return 0.0;
  }

  // ✅ HELPER: Safe number parsing
  int _parseQuantity(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 1;
    return 1;
  }

  double _parseDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  // ✅ GLOBAL UNROUNDED RECALCULATOR — trusts stored amounts after normalization
  void _recomputeTableAmounts(Map<String, dynamic> table) {
    table['orderAmounts'] ??= {
      'pendingAmount': 0.0,
      'ongoingAmount': 0.0,
      'completeAmount': 0.0,
      'pendingDrinksAmount': 0.0,
      'ongoingDrinksAmount': 0.0,
      'completeDrinksAmount': 0.0,
      'totalAmount': 0.0,
    };

    double sumOrders(List? listOrNull, String type) {
      if (listOrNull == null || listOrNull.isEmpty) return 0.0;
      double total = 0.0;
      for (final o in listOrNull) {
        if (o == null) continue;
        final qty = _parseQuantity(o['quantity']);
        if (qty == 0) continue;

        double itemAmount = 0.0;

        // ✅ PRIORITY 1: Use stored `amount` — always the correct taxed total
        // after _normalizeOrderAmount (refresh) or socket handlers (live)
        if (o['amount'] != null) {
          final stored = _parseDouble(o['amount']);
          if (stored > 0) {
            itemAmount = stored;
            total += double.parse(itemAmount.toStringAsFixed(2));
            continue;
          }
        }

        // ✅ PRIORITY 2: amount_per_item × qty
        if (o['amount_per_item'] != null) {
          final perItem = _parseDouble(o['amount_per_item']);
          if (perItem > 0) {
            itemAmount = perItem * qty;
            total += double.parse(itemAmount.toStringAsFixed(2));
            continue;
          }
        }

        // ✅ PRIORITY 3 (last resort): base price + tax
        // Only for brand-new items before normalization has run
        if (type == 'food' && o['menu']?['price'] != null) {
          itemAmount = _parseDouble(o['menu']['price']) * qty * 1.05;
          total += double.parse(itemAmount.toStringAsFixed(2));
          continue;
        }
        if (type == 'drink' && o['drink']?['price'] != null) {
          final basePrice = _parseDouble(o['drink']['price']);
          final applyVAT =
              o['drink']?['applyVAT'] == true ||
              o['drink']?['applyVat'] == true ||
              o['applyVat'] == true ||
              o['applyVAT'] == true ||
              (o['is_custom'] == true &&
                  (o['applyVAT']?.toString() == 'true' ||
                      o['applyVat']?.toString() == 'true'));
          itemAmount = basePrice * qty * (applyVAT ? 1.10 : 1.05);
          total += double.parse(itemAmount.toStringAsFixed(2));
          continue;
        }

        total += double.parse(itemAmount.toStringAsFixed(2));
      }
      return total;
    }

    final pFood = sumOrders(table['orders']?['pendingOrders'], 'food');
    final oFood = sumOrders(table['orders']?['ongoingOrders'], 'food');
    final cFood = sumOrders(table['orders']?['completeOrders'], 'food');
    final pDrink = sumOrders(
      table['drinksOrders']?['pendingDrinksOrders'],
      'drink',
    );
    final oDrink = sumOrders(
      table['drinksOrders']?['ongoingDrinksOrders'],
      'drink',
    );
    final cDrink = sumOrders(
      table['drinksOrders']?['completeDrinksOrders'],
      'drink',
    );

    table['orderAmounts']['pendingAmount'] = pFood.roundToDouble();
    table['orderAmounts']['ongoingAmount'] = oFood.roundToDouble();
    table['orderAmounts']['completeAmount'] = cFood.roundToDouble();
    table['orderAmounts']['pendingDrinksAmount'] = pDrink.roundToDouble();
    table['orderAmounts']['ongoingDrinksAmount'] = oDrink.roundToDouble();
    table['orderAmounts']['completeDrinksAmount'] = cDrink.roundToDouble();

    table['orderAmounts']['totalAmount'] =
        (pFood + oFood + cFood + pDrink + oDrink + cDrink).roundToDouble();
  }

  // ✅ OPTIMIZATION: Debounced state updates
  void _debouncedSetState(VoidCallback fn) {
    final now = DateTime.now();
    if (_lastUpdateTime != null &&
        now.difference(_lastUpdateTime!).inMilliseconds < _updateDebounceMs) {
      return; // Skip rapid updates
    }
    _lastUpdateTime = now;
    if (mounted) setState(fn);
  }

  // Helper method to update section summary after shift
  void _updateSectionSummaryAfterShift(Map<String, dynamic> section) {
    int activeCount = 0;
    double totalAmount = 0.0;

    for (final table in (section['tables'] as List)) {
      final tableTotal = _computeTableTotal(table);
      if (tableTotal > 0) {
        activeCount++;
        totalAmount += tableTotal;
      }
    }

    section['summary'] = {
      'activeTableCount': activeCount,
      'sectionTotalAmount': totalAmount.round(),
    };

    print(
      '📊 Updated section ${section['name']}: $activeCount active tables, ₹${totalAmount.round()} total',
    );
  }

  void _updateTableInState(
    int sectionId,
    int tableId,
    Map<String, dynamic> updates,
  ) {
    if (!mounted) return;

    setState(() {
      final sectionIndex = sections.indexWhere((s) => s['id'] == sectionId);
      if (sectionIndex == -1) return;

      final tables = sections[sectionIndex]['tables'] as List<dynamic>;
      final tableIndex = tables.indexWhere((t) => t['id'] == tableId);
      if (tableIndex == -1) return;

      // Apply updates to the table
      updates.forEach((key, value) {
        tables[tableIndex][key] = value;
      });
    });
  }

  void connectSocket() {
    socket = IO.io(
      dotenv.env['API_URL_1'], // your API base URL
      IO.OptionBuilder()
          .setTransports(['websocket']) // for Flutter Web & mobile
          .disableAutoConnect()
          .build(),
    );

    socket.connect();
    print("\n\n --------->>Socket Connected \n\n");

    socket.on('order_item_completed', (data) {
      print('🎯 Order completion received: $data');

      final orderId = data['orderId']?.toString();
      final orderType = data['orderType']?.toString();
      final newStatus = data['newStatus']?.toString() ?? 'completed';
      final sectionId =
          data['sectionId'] is int
              ? data['sectionId'] as int
              : int.tryParse(data['sectionId']?.toString() ?? '');
      final tableId = data['tableId'];

      final kotNumber = data['kotNumber']?.toString();
      final itemName = data['itemName']?.toString();
      final menuName = data['menuName']?.toString();
      final drinkName = data['drinkName']?.toString();

      if (orderId == null || orderType == null || sectionId == null) {
        print('⚠️ Missing required fields in order completion update');
        return;
      }

      setState(() {
        // Find the section
        final sectionIndex = sections.indexWhere((s) => s['id'] == sectionId);
        if (sectionIndex == -1) {
          print('⚠️ Section $sectionId not found for order completion');
          return;
        }

        // Find the table
        final section = sections[sectionIndex];
        final tableIndex = findTableIndexInSection(section, tableId);
        if (tableIndex == -1) {
          print('⚠️ Table $tableId not found in section $sectionId');
          return;
        }

        final tables = section['tables'] as List<dynamic>;
        final table = tables[tableIndex];

        final String? menuNameFromPayload = itemName ?? menuName ?? drinkName;

        print(
          '🔄 Processing completion: type=$orderType, orderId=$orderId, status=$newStatus',
        );

        // Update the order based on type
        if (orderType == 'food') {
          _updateFoodOrderStatusFixed(
            table,
            orderId,
            newStatus,
            0.0, // Amount will be recalculated from stored amount_per_item
            menuNameFromPayload,
            kotNumber,
          );
        } else if (orderType == 'drinks') {
          _updateDrinksOrderStatusFixed(
            table,
            orderId,
            newStatus,
            0.0, // Amount will be recalculated from stored amount_per_item
            menuNameFromPayload,
            kotNumber,
          );
        }
      });
    });

    // ✅ Listen for new section event
    socket.on('new_section', (data) {
      print('📢 New section added: $data');
      fetchSections(); // Refresh sections list
    });

    socket.on('section_updated', (data) {
      print('📢 Section updated: $data');
      setState(() {
        final sectionIndex = sections.indexWhere(
          (s) => s['id'] == data['sectionId'],
        );
        if (sectionIndex != -1) {
          sections[sectionIndex]['name'] = data['newName'];
        }
      });
    });

    socket.on('section_deleted', (data) {
      print('📢 Section deleted: $data');
      setState(() {
        sections.removeWhere((s) => s['id'] == data['sectionId']);
      });
    });

    // ---------- DEMERGE TABLE HANDLER (UPDATED) ----------

    socket.on('demerge_table', (data) {
      print('📢 Tables demerged: $data');

      final primaryTableId = data['primaryTableId'];
      final mergingTableId = data['mergingTableId'];
      final primaryStatus = data['primaryTableStatus']?.toString() ?? 'free';
      final mergingStatus = data['mergingTableStatus']?.toString() ?? 'free';
      final primaryTotal =
          (data['primaryTotalAmount'] as num?)?.toDouble() ?? 0.0;
      final mergingTotal =
          (data['mergingTotalAmount'] as num?)?.toDouble() ?? 0.0;

      // ✅ Full order payloads from backend — use them directly
      final primaryOrders = data['primaryOrders'] as Map?;
      final primaryDrinksOrders = data['primaryDrinksOrders'] as Map?;
      final mergingOrders = data['mergingOrders'] as Map?;
      final mergingDrinksOrders = data['mergingDrinksOrders'] as Map?;

      if (!mounted) return;

      setState(() {
        Map<String, dynamic>? primaryTable;
        Map<String, dynamic>? mergingTable;
        int? primarySectionIndex;

        for (int sIdx = 0; sIdx < sections.length; sIdx++) {
          final tables = sections[sIdx]['tables'] as List<dynamic>;
          for (var table in tables) {
            if (table['id'] == primaryTableId) {
              primaryTable = table;
              primarySectionIndex = sIdx;
            }
            if (table['id'] == mergingTableId) {
              mergingTable = table;
            }
          }
        }

        if (primaryTable == null || mergingTable == null) {
          print('❌ Tables not found for demerge — triggering fetchSections');
          fetchSections();
          return;
        }

        // ── PRIMARY TABLE ────────────────────────────────────────────────
        if (primaryOrders != null) {
          primaryTable['orders'] = {
            'pendingOrders': List<dynamic>.from(
              primaryOrders['pendingOrders'] ?? [],
            ),
            'ongoingOrders': List<dynamic>.from(
              primaryOrders['ongoingOrders'] ?? [],
            ),
            'completeOrders': List<dynamic>.from(
              primaryOrders['completeOrders'] ?? [],
            ),
          };
        }
        if (primaryDrinksOrders != null) {
          primaryTable['drinksOrders'] = {
            'pendingDrinksOrders': List<dynamic>.from(
              primaryDrinksOrders['pendingDrinksOrders'] ?? [],
            ),
            'ongoingDrinksOrders': List<dynamic>.from(
              primaryDrinksOrders['ongoingDrinksOrders'] ?? [],
            ),
            'completeDrinksOrders': List<dynamic>.from(
              primaryDrinksOrders['completeDrinksOrders'] ?? [],
            ),
          };
        }

        // Clean up merged_with on primary
        if (primaryTable['merged_with'] is List) {
          primaryTable['merged_with'] =
              (primaryTable['merged_with'] as List)
                  .where((id) => id != mergingTableId)
                  .toList();
          if ((primaryTable['merged_with'] as List).isEmpty) {
            primaryTable['merged_with'] = null;
          }
        } else {
          primaryTable['merged_with'] = null;
        }

        primaryTable['status'] = primaryStatus;
        if (primaryStatus == 'free') {
          primaryTable['seatingTime'] = null;
          primaryTable['food_bill_id'] = null;
          primaryTable['customer_id'] = null;
        } else {
          primaryTable['seatingTime'] ??= DateTime.now().toIso8601String();
        }

        // ── MERGING TABLE ────────────────────────────────────────────────
        if (mergingOrders != null) {
          mergingTable['orders'] = {
            'pendingOrders': List<dynamic>.from(
              mergingOrders['pendingOrders'] ?? [],
            ),
            'ongoingOrders': List<dynamic>.from(
              mergingOrders['ongoingOrders'] ?? [],
            ),
            'completeOrders': List<dynamic>.from(
              mergingOrders['completeOrders'] ?? [],
            ),
          };
        } else {
          // Backend sent no orders for merging table → it's truly empty
          mergingTable['orders'] = {
            'pendingOrders': [],
            'ongoingOrders': [],
            'completeOrders': [],
          };
        }
        if (mergingDrinksOrders != null) {
          mergingTable['drinksOrders'] = {
            'pendingDrinksOrders': List<dynamic>.from(
              mergingDrinksOrders['pendingDrinksOrders'] ?? [],
            ),
            'ongoingDrinksOrders': List<dynamic>.from(
              mergingDrinksOrders['ongoingDrinksOrders'] ?? [],
            ),
            'completeDrinksOrders': List<dynamic>.from(
              mergingDrinksOrders['completeDrinksOrders'] ?? [],
            ),
          };
        } else {
          mergingTable['drinksOrders'] = {
            'pendingDrinksOrders': [],
            'ongoingDrinksOrders': [],
            'completeDrinksOrders': [],
          };
        }

        mergingTable['merged_with'] = null;
        mergingTable['merged_at'] = null;
        mergingTable['status'] = mergingStatus;
        if (mergingStatus == 'free') {
          mergingTable['seatingTime'] = null;
        } else {
          mergingTable['seatingTime'] ??= DateTime.now().toIso8601String();
        }

        // ── RECOMPUTE AMOUNTS FROM AUTHORITATIVE ORDER DATA ──────────────
        _normalizeSectionAmounts(); // normalise tax on freshly-set orders
        _recomputeTableAmounts(primaryTable);
        _recomputeTableAmounts(mergingTable);

        // ── SECTION SUMMARY ──────────────────────────────────────────────
        if (primarySectionIndex != null) {
          _recomputeSectionSummaryInline(primarySectionIndex);
        }

        print('✅ Primary  → $primaryStatus  (₹$primaryTotal)');
        print('✅ Merging  → $mergingStatus  (₹$mergingTotal)');
        print('✅ Demerge UI update complete — no fetchSections needed');
      });
    });

    socket.on('table_status_changed', (data) {
      print('📢 Table status changed: $data');
      setState(() {
        final newStatus = data['newStatus']?.toString() ?? '';
        final tableId = data['tableId'];

        for (var section in sections) {
          final tables = section['tables'] as List<dynamic>;
          final tableIndex = tables.indexWhere((t) => t['id'] == tableId);

          if (tableIndex != -1) {
            tables[tableIndex]['status'] = newStatus;
            tables[tableIndex]['seatingTime'] = data['seatingTime'];
            tables[tableIndex]['merged_with'] = data['merged_with'];

            // ✅ If table is being freed, reset ALL state fully
            if (newStatus == 'free') {
              tables[tableIndex]['seatingTime'] = null;
              tables[tableIndex]['food_bill_id'] = null;
              tables[tableIndex]['customer_id'] = null;
              tables[tableIndex]['merged_with'] = null;
              tables[tableIndex]['merged_at'] = null;

              // ✅ Clear all orders
              tables[tableIndex]['orders'] = {
                'pendingOrders': [],
                'ongoingOrders': [],
                'completeOrders': [],
              };
              tables[tableIndex]['drinksOrders'] = {
                'pendingDrinksOrders': [],
                'ongoingDrinksOrders': [],
                'completeDrinksOrders': [],
              };

              // ✅ Reset all amounts
              tables[tableIndex]['orderAmounts'] = {
                'pendingAmount': 0,
                'ongoingAmount': 0,
                'completeAmount': 0,
                'pendingDrinksAmount': 0,
                'ongoingDrinksAmount': 0,
                'completeDrinksAmount': 0,
                'totalAmount': 0,
              };

              print('✅ Fully reset table $tableId to free state');
            }

            // ✅ Recompute section summary after any status change
            final sectionIndex = sections.indexOf(section);
            if (sectionIndex != -1) {
              _recomputeSectionSummaryInline(sectionIndex);
            }

            break;
          }
        }
      });
    });

    socket.on('table_created', (data) {
      print('📢 Table created: $data');
      fetchSections(); // Refresh to get new table
    });

    socket.on('table_capacity_updated', (data) {
      print('📢 Table capacity updated: $data');
      setState(() {
        for (var section in sections) {
          final tables = section['tables'] as List<dynamic>;
          final tableIndex = tables.indexWhere(
            (t) => t['id'] == data['tableId'],
          );
          if (tableIndex != -1) {
            tables[tableIndex]['seatingCapacity'] = data['newCapacity'];
            break;
          }
        }
      });
    });

    // FIXED order_shifted socket handler
    // Replace the existing handler in your code with this corrected version

    socket.on('order_shifted', (data) {
      print('📢 Orders shifted (authoritative): $data');

      final int? fromTableId = int.tryParse(
        data['fromTableId']?.toString() ?? '',
      );
      final int? toTableId = int.tryParse(data['toTableId']?.toString() ?? '');
      final String orderType = (data['orderType'] ?? 'food').toString();
      final String? fromSectionName = data['fromSectionName']?.toString();
      final String? toSectionName = data['toSectionName']?.toString();

      final List shiftedDetails = data['shiftedOrderDetails'] ?? [];
      final List orderIds = (data['orderIds'] as List?) ?? [];

      if (fromTableId == null || toTableId == null) {
        print('❌ Invalid table IDs');
        return;
      }

      if (shiftedDetails.isEmpty && orderIds.isEmpty) {
        print('❌ No orders to shift');
        return;
      }

      if (!mounted) return;

      setState(() {
        Map<String, dynamic>? fromTable;
        Map<String, dynamic>? toTable;
        int? fromSectionIndex;
        int? toSectionIndex;

        for (int sIdx = 0; sIdx < sections.length; sIdx++) {
          final section = sections[sIdx];
          final sName = section['name']?.toString() ?? '';

          for (final table in section['tables']) {
            final tableDisplayNum = table['display_number'];
            final tableParsed =
                tableDisplayNum is int
                    ? tableDisplayNum
                    : int.tryParse(tableDisplayNum?.toString() ?? '');

            // ✅ FIX: Match by display_number + section name
            if (fromSectionName != null &&
                sName == fromSectionName &&
                tableParsed == fromTableId) {
              fromTable = table;
              fromSectionIndex = sIdx;
            }
            if (toSectionName != null &&
                sName == toSectionName &&
                tableParsed == toTableId) {
              toTable = table;
              toSectionIndex = sIdx;
            }
          }
        }

        // ✅ FALLBACK: if section name matching fails, try DB id match
        // (same-section shifts where display_number == DB id coincidentally)
        if (fromTable == null || toTable == null) {
          for (int sIdx = 0; sIdx < sections.length; sIdx++) {
            final section = sections[sIdx];
            for (final table in section['tables']) {
              if (fromTable == null && table['id'] == fromTableId) {
                fromTable = table;
                fromSectionIndex = sIdx;
              }
              if (toTable == null && table['id'] == toTableId) {
                toTable = table;
                toSectionIndex = sIdx;
              }
            }
          }
        }

        if (fromTable == null || toTable == null) {
          print(
            '❌ Tables not found - fromTable: ${fromTable != null}, toTable: ${toTable != null}',
          );
          return;
        }

        print(
          '✅ Found tables - From: ${fromTable['id']} (section $fromSectionIndex), To: ${toTable['id']} (section $toSectionIndex)',
        );

        // Extract order IDs from shiftedDetails and orderIds
        final idsToShift = <int>{};
        for (final detail in shiftedDetails) {
          if (detail is Map && detail['id'] != null) {
            final id =
                detail['id'] is int
                    ? detail['id']
                    : int.tryParse(detail['id'].toString());
            if (id != null) idsToShift.add(id);
          }
        }

        for (final id in orderIds) {
          final parsedId = id is int ? id : int.tryParse(id.toString());
          if (parsedId != null) idsToShift.add(parsedId);
        }

        print('🎯 Order IDs to shift: $idsToShift');

        if (idsToShift.isEmpty) {
          print('❌ No valid order IDs found');
          return;
        }

        /// Initialize order structures if missing
        fromTable['orders'] ??= {
          'pendingOrders': [],
          'ongoingOrders': [],
          'completeOrders': [],
        };
        toTable['orders'] ??= {
          'pendingOrders': [],
          'ongoingOrders': [],
          'completeOrders': [],
        };
        fromTable['drinksOrders'] ??= {
          'pendingDrinksOrders': [],
          'ongoingDrinksOrders': [],
          'completeDrinksOrders': [],
        };
        toTable['drinksOrders'] ??= {
          'pendingDrinksOrders': [],
          'ongoingDrinksOrders': [],
          'completeDrinksOrders': [],
        };

        /// 🍽 MOVE FOOD ORDERS or 🥤 MOVE DRINK ORDERS
        if (orderType == 'food') {
          print('🍽 Shifting FOOD orders');

          for (final status in [
            'pendingOrders',
            'ongoingOrders',
            'completeOrders',
          ]) {
            final fromList = fromTable['orders'][status] as List;
            final toList = toTable['orders'][status] as List;

            // Find orders to move
            final movedOrders = <dynamic>[];
            for (final order in List.from(fromList)) {
              if (order == null) continue;
              final orderId = order['id'];
              if (orderId != null && idsToShift.contains(orderId)) {
                movedOrders.add(order);
                print(
                  '  ✅ Moving food order $orderId from $status (${order['item_desc']})',
                );
              }
            }

            // Add to destination
            if (movedOrders.isNotEmpty) {
              toList.addAll(movedOrders);
              print(
                '  📥 Added ${movedOrders.length} orders to destination $status',
              );
            }

            // Remove from source
            final removedCount = fromList.length;
            fromList.removeWhere(
              (o) =>
                  o != null && o['id'] != null && idsToShift.contains(o['id']),
            );
            print(
              '  📤 Removed ${removedCount - fromList.length} orders from source $status',
            );
          }
        } else if (orderType == 'drinks') {
          print('🥤 Shifting DRINK orders');

          for (final status in [
            'pendingDrinksOrders',
            'ongoingDrinksOrders',
            'completeDrinksOrders',
          ]) {
            final fromList = fromTable['drinksOrders'][status] as List;
            final toList = toTable['drinksOrders'][status] as List;

            // Find orders to move
            final movedOrders = <dynamic>[];
            for (final order in List.from(fromList)) {
              if (order == null) continue;
              final orderId = order['id'];
              if (orderId != null && idsToShift.contains(orderId)) {
                movedOrders.add(order);
                print('  ✅ Moving drink order $orderId from $status');
              }
            }

            // Add to destination
            if (movedOrders.isNotEmpty) {
              toList.addAll(movedOrders);
              print(
                '  📥 Added ${movedOrders.length} drinks to destination $status',
              );
            }

            // Remove from source
            final removedCount = fromList.length;
            fromList.removeWhere(
              (o) =>
                  o != null && o['id'] != null && idsToShift.contains(o['id']),
            );
            print(
              '  📤 Removed ${removedCount - fromList.length} drinks from source $status',
            );
          }
        }

        // Recompute amounts for both tables
        _recomputeTableAmounts(fromTable);
        _recomputeTableAmounts(toTable);

        /// 🪑 UPDATE TABLE STATUS

        // Update destination table
        final toTotal = toTable['orderAmounts']['totalAmount'] ?? 0;
        if (toTotal > 0) {
          toTable['status'] = 'occupied';
          toTable['seatingTime'] ??= DateTime.now().toIso8601String();
          print('✅ Set toTable ${toTable['id']} to occupied (₹$toTotal)');
        }

        // Check if source table should be freed
        final fromTotal = fromTable['orderAmounts']['totalAmount'] ?? 0;
        if (fromTotal == 0 || fromTotal.roundToDouble() == 0.0) {
          fromTable['status'] = 'free';
          fromTable['seatingTime'] = null;
          fromTable['food_bill_id'] = null;
          fromTable['customer_id'] = null;
          print(
            '✅ Reset fromTable ${fromTable['id']} to free (no orders remaining)',
          );
        } else {
          print(
            'ℹ️ FromTable ${fromTable['id']} still occupied (₹$fromTotal remaining)',
          );
        }

        /// 🔄 UPDATE SECTION SUMMARIES
        if (fromSectionIndex != null) {
          final fromSection = sections[fromSectionIndex];
          _updateSectionSummaryAfterShift(fromSection);
        }

        if (toSectionIndex != null && toSectionIndex != fromSectionIndex) {
          final toSection = sections[toSectionIndex];
          _updateSectionSummaryAfterShift(toSection);
        }
      });

      print('✅ Order shift completed - UI updated on all devices');
    });

    // transfer_table handler (unchanged)
    // socket.on('transfer_table', (data) {
    //   print('📢 Tables transferred: $data');

    //   final fromTableId = data['fromTable']?['id'];
    //   final toTableId = data['toTable']?['id'];

    //   if (fromTableId == null || toTableId == null) {
    //     print('❌ Invalid socket payload');
    //     return;
    //   }

    //   setState(() {
    //     Map<String, dynamic>? fromTable;
    //     Map<String, dynamic>? toTable;

    //     // 🔍 Find tables across ALL sections
    //     for (final section in sections) {
    //       final tables = section['tables'] as List<dynamic>;

    //       for (final t in tables) {
    //         if (t['id'] == fromTableId) fromTable = t;
    //         if (t['id'] == toTableId) toTable = t;
    //       }
    //     }

    //     if (fromTable == null || toTable == null) {
    //       print('❌ Tables not found in UI state');
    //       return;
    //     }

    //     /// 🍽️ Move FOOD orders
    //     for (final key in [
    //       'pendingOrders',
    //       'ongoingOrders',
    //       'completeOrders',
    //     ]) {
    //       (toTable!['orders'][key] as List).addAll(fromTable!['orders'][key]);
    //       (fromTable['orders'][key] as List).clear();
    //     }

    //     /// 🥤 Move DRINK orders
    //     for (final key in [
    //       'pendingDrinksOrders',
    //       'ongoingDrinksOrders',
    //       'completeDrinksOrders',
    //     ]) {
    //       (toTable!['drinksOrders'][key] as List).addAll(
    //         fromTable!['drinksOrders'][key],
    //       );
    //       (fromTable['drinksOrders'][key] as List).clear();
    //     }

    //     /// 💰 Move amounts safely
    //     toTable['orderAmounts'] ??= {};
    //     fromTable['orderAmounts'] ??= {};

    //     for (final amountKey in [
    //       'pendingAmount',
    //       'ongoingAmount',
    //       'completeAmount',
    //       'pendingDrinksAmount',
    //       'ongoingDrinksAmount',
    //       'completeDrinksAmount',
    //     ]) {
    //       toTable['orderAmounts'][amountKey] =
    //           (toTable['orderAmounts'][amountKey] ?? 0) +
    //           (fromTable['orderAmounts'][amountKey] ?? 0);
    //     }

    //     toTable['orderAmounts']['totalAmount'] =
    //         (toTable['orderAmounts']['totalAmount'] ?? 0) +
    //         (fromTable['orderAmounts']['totalAmount'] ?? 0);

    //     /// 🔄 Reset FROM table
    //     fromTable['orderAmounts'] = {
    //       "pendingAmount": 0,
    //       "ongoingAmount": 0,
    //       "completeAmount": 0,
    //       "pendingDrinksAmount": 0,
    //       "ongoingDrinksAmount": 0,
    //       "completeDrinksAmount": 0,
    //       "totalAmount": 0,
    //     };

    //     fromTable['status'] = 'free';
    //     fromTable['food_bill_id'] = null;
    //     fromTable['customer_id'] = null;
    //     fromTable['seatingTime'] = null;

    //     /// ✅ Update TO table
    //     toTable['status'] = 'occupied';
    //     toTable['food_bill_id'] =
    //         data['food_bill_id'] ?? fromTable['food_bill_id'];
    //     toTable['customer_id'] =
    //         data['customer_id'] ?? fromTable['customer_id'];
    //     toTable['seatingTime'] =
    //         fromTable['seatingTime'] ?? DateTime.now().toIso8601String();
    //   });
    // });

    socket.on('transfer_table', (data) {
      print('📢 Tables transferred: $data');

      final fromTableId = data['fromTable']?['id'];
      final toTableId = data['toTable']?['id'];

      if (fromTableId == null || toTableId == null) {
        print('❌ Invalid socket payload');
        return;
      }

      setState(() {
        Map<String, dynamic>? fromTable;
        Map<String, dynamic>? toTable;
        int? fromSectionIndex; // ✅ Track section indices
        int? toSectionIndex;

        // 🔍 Find tables across ALL sections
        for (int sIdx = 0; sIdx < sections.length; sIdx++) {
          final section = sections[sIdx];
          final tables = section['tables'] as List<dynamic>;

          for (final t in tables) {
            if (t['id'] == fromTableId) {
              fromTable = t;
              fromSectionIndex = sIdx;
            }
            if (t['id'] == toTableId) {
              toTable = t;
              toSectionIndex = sIdx;
            }
          }
        }

        if (fromTable == null || toTable == null) {
          print('❌ Tables not found in UI state');
          return;
        }

        /// 🍽️ Move FOOD orders
        for (final key in [
          'pendingOrders',
          'ongoingOrders',
          'completeOrders',
        ]) {
          (toTable!['orders'][key] as List).addAll(fromTable!['orders'][key]);
          (fromTable['orders'][key] as List).clear();
        }

        /// 🥤 Move DRINK orders
        for (final key in [
          'pendingDrinksOrders',
          'ongoingDrinksOrders',
          'completeDrinksOrders',
        ]) {
          (toTable!['drinksOrders'][key] as List).addAll(
            fromTable!['drinksOrders'][key],
          );
          (fromTable['drinksOrders'][key] as List).clear();
        }

        /// 💰 Move amounts safely
        toTable['orderAmounts'] ??= {};
        fromTable['orderAmounts'] ??= {};

        for (final amountKey in [
          'pendingAmount',
          'ongoingAmount',
          'completeAmount',
          'pendingDrinksAmount',
          'ongoingDrinksAmount',
          'completeDrinksAmount',
        ]) {
          toTable['orderAmounts'][amountKey] =
              (toTable['orderAmounts'][amountKey] ?? 0) +
              (fromTable['orderAmounts'][amountKey] ?? 0);
        }

        toTable['orderAmounts']['totalAmount'] =
            (toTable['orderAmounts']['totalAmount'] ?? 0) +
            (fromTable['orderAmounts']['totalAmount'] ?? 0);

        /// 🔄 Reset FROM table
        fromTable['orderAmounts'] = {
          "pendingAmount": 0,
          "ongoingAmount": 0,
          "completeAmount": 0,
          "pendingDrinksAmount": 0,
          "ongoingDrinksAmount": 0,
          "completeDrinksAmount": 0,
          "totalAmount": 0,
        };

        fromTable['status'] = 'free';
        fromTable['food_bill_id'] = null;
        fromTable['customer_id'] = null;
        fromTable['seatingTime'] = null;

        /// ✅ Update TO table
        toTable['status'] = 'occupied';
        toTable['food_bill_id'] =
            data['food_bill_id'] ?? fromTable['food_bill_id'];
        toTable['customer_id'] =
            data['customer_id'] ?? fromTable['customer_id'];
        toTable['seatingTime'] =
            fromTable['seatingTime'] ?? DateTime.now().toIso8601String();

        // ✅ Recompute section summaries
        if (fromSectionIndex != null) {
          _recomputeSectionSummaryInline(fromSectionIndex!);
        }
        if (toSectionIndex != null && toSectionIndex != fromSectionIndex) {
          _recomputeSectionSummaryInline(toSectionIndex!);
        }
      });
    });

    socket.on('auto_split_table_created', (data) {
      print('📢 Auto-duplicate table created: $data');

      try {
        final newTable = data['newTable'];
        final parentTableId = data['parentTableId'];

        if (newTable == null) {
          print('⚠️ auto_split_table_created event missing newTable payload');
          return;
        }

        setState(() {
          final int? sectionIdFromNew =
              newTable['sectionId'] is int
                  ? newTable['sectionId'] as int
                  : int.tryParse(newTable['sectionId']?.toString() ?? '');

          if (sectionIdFromNew != null) {
            final secIndex = sections.indexWhere(
              (s) => s['id'] == sectionIdFromNew,
            );

            if (secIndex != -1) {
              // Insert duplicate next to parent if possible
              if (parentTableId != null) {
                final tables = sections[secIndex]['tables'] as List<dynamic>;
                final parentIndex = tables.indexWhere(
                  (t) => t['id'] == parentTableId,
                );

                if (parentIndex != -1) {
                  tables.insert(parentIndex + 1, newTable);
                  print(
                    '✅ Inserted duplicate table next to parent at index ${parentIndex + 1}',
                  );
                } else {
                  tables.add(newTable);
                  print('✅ Parent not found, added duplicate at end');
                }
              } else {
                sections[secIndex]['tables'].add(newTable);
                print('✅ Added duplicate table to section');
              }
            }
          }
        });
      } catch (e) {
        print('Error handling auto_split_table_created event: $e');
      }
    });

    // ✅ Listen for bill generation
    socket.on('bill_generated', (data) {
      print('📢 Bill generated: $data');

      try {
        final tableId = data['tableId'];
        final billId = data['billId'];

        if (tableId == null) return;

        setState(() {
          for (var section in sections) {
            final tables = section['tables'] as List<dynamic>;
            final tableIndex = tables.indexWhere((t) => t['id'] == tableId);

            if (tableIndex != -1) {
              tables[tableIndex]['status'] = 'settleUp';
              tables[tableIndex]['food_bill_id'] = billId;
              print('✅ Updated table $tableId to settleUp status');
              break;
            }
          }
        });
      } catch (e) {
        print('Error handling bill_generated event: $e');
      }
    });

    // ✅ Listen for table entering settle-up mode
    socket.on('table_settle_up', (data) {
      print('📢 Table entering settle-up: $data');

      try {
        final tableId = data['tableId'];

        if (tableId == null) return;

        setState(() {
          for (var section in sections) {
            final tables = section['tables'] as List<dynamic>;
            final tableIndex = tables.indexWhere((t) => t['id'] == tableId);

            if (tableIndex != -1) {
              tables[tableIndex]['status'] = 'settleUp';
              print('✅ Updated table $tableId to settleUp status');
              break;
            }
          }
        });
      } catch (e) {
        print('Error handling table_settle_up event: $e');
      }
    });

    // merge_table handler (unchanged)
    socket.on('merge_table', (data) {
      print('📢 Tables merged: $data');

      final primaryTableId = data['primaryTableId'];
      final mergingTableId = data['mergingTableId']; // ✅ Fixed field name
      final primaryStatus = data['primaryStatus'] ?? 'occupied';
      final mergingStatus = data['mergingStatus'] ?? 'merged';
      final orderCount = data['orderCount'] ?? 0;

      if (!mounted) return;

      setState(() {
        Map<String, dynamic>? primaryTable;
        Map<String, dynamic>? mergingTable;

        // Find both tables
        for (var section in sections) {
          final tables = section['tables'] as List<dynamic>;

          for (var table in tables) {
            if (table['id'] == primaryTableId) {
              primaryTable = table;
            }
            if (table['id'] == mergingTableId) {
              mergingTable = table;
            }
          }
        }

        if (primaryTable == null || mergingTable == null) {
          print('❌ Tables not found for merge');
          return;
        }

        print(
          '✅ Found tables to merge - Primary: $primaryTableId, Merging: $mergingTableId',
        );

        // Initialize order structures if missing
        primaryTable['orders'] ??= {
          'pendingOrders': [],
          'ongoingOrders': [],
          'completeOrders': [],
        };
        mergingTable['orders'] ??= {
          'pendingOrders': [],
          'ongoingOrders': [],
          'completeOrders': [],
        };
        primaryTable['drinksOrders'] ??= {
          'pendingDrinksOrders': [],
          'ongoingDrinksOrders': [],
          'completeDrinksOrders': [],
        };
        mergingTable['drinksOrders'] ??= {
          'pendingDrinksOrders': [],
          'ongoingDrinksOrders': [],
          'completeDrinksOrders': [],
        };

        // Move FOOD orders from merging table to primary table
        for (var key in ['pendingOrders', 'ongoingOrders', 'completeOrders']) {
          final mergingOrders = List.from(mergingTable['orders'][key] ?? []);
          (primaryTable['orders'][key] as List).addAll(mergingOrders);
          (mergingTable['orders'][key] as List).clear();
          print('  Moved ${mergingOrders.length} $key from merging to primary');
        }

        // Move DRINK orders from merging table to primary table
        for (var key in [
          'pendingDrinksOrders',
          'ongoingDrinksOrders',
          'completeDrinksOrders',
        ]) {
          final mergingDrinks = List.from(
            mergingTable['drinksOrders'][key] ?? [],
          );
          (primaryTable['drinksOrders'][key] as List).addAll(mergingDrinks);
          (mergingTable['drinksOrders'][key] as List).clear();
          print('  Moved ${mergingDrinks.length} $key from merging to primary');
        }

        // Update amounts
        primaryTable['orderAmounts'] ??= {
          'pendingAmount': 0,
          'ongoingAmount': 0,
          'completeAmount': 0,
          'pendingDrinksAmount': 0,
          'ongoingDrinksAmount': 0,
          'completeDrinksAmount': 0,
          'totalAmount': 0,
        };

        mergingTable['orderAmounts'] ??= {
          'pendingAmount': 0,
          'ongoingAmount': 0,
          'completeAmount': 0,
          'pendingDrinksAmount': 0,
          'ongoingDrinksAmount': 0,
          'completeDrinksAmount': 0,
          'totalAmount': 0,
        };

        // Add merging table amounts to primary table
        for (var amountKey in [
          'pendingAmount',
          'ongoingAmount',
          'completeAmount',
          'pendingDrinksAmount',
          'ongoingDrinksAmount',
          'completeDrinksAmount',
        ]) {
          final primaryAmt = primaryTable['orderAmounts'][amountKey] ?? 0;
          final mergingAmt = mergingTable['orderAmounts'][amountKey] ?? 0;
          primaryTable['orderAmounts'][amountKey] =
              (primaryAmt + mergingAmt).roundToDouble();
        }

        final primaryTotal = primaryTable['orderAmounts']['totalAmount'] ?? 0;
        final mergingTotal = mergingTable['orderAmounts']['totalAmount'] ?? 0;
        primaryTable['orderAmounts']['totalAmount'] =
            (primaryTotal + mergingTotal).roundToDouble();

        print(
          '  💰 Primary table total: ₹${primaryTable['orderAmounts']['totalAmount']}',
        );

        // Update primary table merged_with array
        final currentMergedWith = primaryTable['merged_with'];
        List<int> mergedWithList = [];

        if (currentMergedWith is List) {
          mergedWithList = List<int>.from(currentMergedWith);
        } else if (currentMergedWith != null) {
          mergedWithList = [currentMergedWith as int];
        }

        if (!mergedWithList.contains(mergingTableId)) {
          mergedWithList.add(mergingTableId);
        }

        primaryTable['merged_with'] = mergedWithList;
        primaryTable['status'] = primaryStatus;

        // Reset merging table
        mergingTable['status'] = mergingStatus;
        mergingTable['merged_with'] = [primaryTableId];
        mergingTable['merged_at'] = DateTime.now().toIso8601String();
        mergingTable['orderAmounts'] = {
          "pendingAmount": 0,
          "ongoingAmount": 0,
          "completeAmount": 0,
          "pendingDrinksAmount": 0,
          "ongoingDrinksAmount": 0,
          "completeDrinksAmount": 0,
          "totalAmount": 0,
        };
        mergingTable['food_bill_id'] = null;
        mergingTable['customer_id'] = null;
        mergingTable['seatingTime'] = null;

        // Clear orders from merging table
        mergingTable['orders'] = {
          'pendingOrders': [],
          'ongoingOrders': [],
          'completeOrders': [],
        };
        mergingTable['drinksOrders'] = {
          'pendingDrinksOrders': [],
          'ongoingDrinksOrders': [],
          'completeDrinksOrders': [],
        };

        print(
          '✅ Merge completed: Primary=$primaryTableId (${primaryTable['status']}), Merging=$mergingTableId (${mergingTable['status']})',
        );
      });

      // ✅ No fetchSections() here - state is already updated!
    });

    // reserve_table handler (unchanged)
    socket.on('reserve_table', (data) {
      print('📢 Table reserved: $data');

      final reservedTableId = int.parse(data['TableId'].toString());
      final sectionId = int.parse(data['SectionId'].toString());
      final status = data['status'];

      setState(() {
        final sectionIndex = sections.indexWhere((s) => s['id'] == sectionId);
        if (sectionIndex == -1) {
          print("⚠️ Section $sectionId not found");
          return;
        }

        final tables = sections[sectionIndex]['tables'] as List<dynamic>;
        final tableIndex = tables.indexWhere((t) => t['id'] == reservedTableId);
        if (tableIndex == -1) {
          print("⚠️ Table $reservedTableId not found in section $sectionId");
          return;
        }

        tables[tableIndex]['status'] = status;
      });
    });

    // ---------- NEW food order handler (replace your existing one) ----------
    socket.on('new_foods_order', (data) {
      print('🆕 New food order received: $data');

      final order = data['order'];
      final sectionId =
          order != null
              ? (order['section'] != null
                  ? (order['section']['id'] is int
                      ? order['section']['id'] as int
                      : int.tryParse(order['section']['id']?.toString() ?? ''))
                  : null)
              : null;
      final tableNumberRaw =
          order != null
              ? order['actual_table_number'] ??
                  order['table_number'] ??
                  order['tableNo']
              : null;
      final items = data['items'] as List<dynamic>? ?? [];
      final kotNumber = data['kotNumber'];

      if (sectionId == null) {
        print('⚠️ Section id missing — aborting handler.');
        return;
      }

      final sectionIndex = sections.indexWhere((s) => s['id'] == sectionId);
      if (sectionIndex == -1) {
        print(
          '⚠️ Section $sectionId not found locally — calling fetchSections()',
        );
        fetchSections();
        return;
      }

      final section = sections[sectionIndex];
      final tableIndex = findTableIndexInSection(section, tableNumberRaw);
      if (tableIndex == -1) {
        print(
          '⚠️ Table $tableNumberRaw not found in section $sectionId locally.',
        );
        fetchSections();
        return;
      }

      setState(() {
        final table = (section['tables'] as List)[tableIndex];

        table['orders'] ??= {
          'pendingOrders': [],
          'ongoingOrders': [],
          'completeOrders': [],
        };
        table['orderAmounts'] ??= {
          'pendingAmount': 0,
          'ongoingAmount': 0,
          'completeAmount': 0,
          'pendingDrinksAmount': 0,
          'ongoingDrinksAmount': 0,
          'completeDrinksAmount': 0,
          'totalAmount': 0,
        };

        final bool wasTableFree =
            (table['status'] ?? 'free') == 'free' &&
            (table['orderAmounts']['totalAmount'] ?? 0) == 0;
        double totalAddedAmount = 0;

        int addedCount = 0;
        final pendingList = table['orders']['pendingOrders'] as List<dynamic>;

        for (var item in items) {
          final orderItem = item['orderItem'] ?? item['order_item'];
          final menuItem =
              item['menuItem'] ?? item['menu'] ?? item['menu_item'];

          if (orderItem == null) {
            print('⚠️ Skipping food item with missing orderItem: $item');
            continue;
          }

          final orderItemId = orderItem['id'];
          final qty =
              orderItem['quantity'] is int
                  ? orderItem['quantity'] as int
                  : int.tryParse(orderItem['quantity']?.toString() ?? '') ?? 1;

          final basePrice =
              (orderItem['price'] is num)
                  ? (orderItem['price'] as num).toDouble()
                  : double.tryParse(orderItem['price']?.toString() ?? '') ??
                      0.0;

          // ✅ Calculate WITH 5% GST and round
          final double exactItemGST = double.parse(
            (basePrice * 1.05).toStringAsFixed(2),
          );
          final pricePerItemWithGST = exactItemGST.roundToDouble();
          final double exactTotal = double.parse(
            (basePrice * qty * 1.05).toStringAsFixed(2),
          );
          final itemTotal = exactTotal.roundToDouble();

          // Check for duplicates...
          int existingIndex = -1;
          existingIndex = pendingList.indexWhere((o) {
            if (o == null) return false;
            if (o['id'] != null &&
                orderItemId != null &&
                o['id'] == orderItemId)
              return true;

            final existingMenuId =
                o['menu'] != null ? (o['menu']['id'] ?? null) : null;
            final incomingMenuId =
                menuItem != null
                    ? (menuItem['id'] ?? menuItem['menuId'] ?? null)
                    : null;
            if (existingMenuId != null && incomingMenuId != null) {
              if (existingMenuId == incomingMenuId) {
                final existingKot = o['kotNumber']?.toString();
                final incomingKot =
                    kotNumber?.toString() ?? data['kotNumber']?.toString();
                return existingKot == null ||
                    incomingKot == null ||
                    existingKot == incomingKot;
              }
            }

            final existingName =
                (o['menu'] != null
                        ? (o['menu']['name'] ?? '')
                        : (o['item_desc'] ?? ''))
                    .toString();
            final incomingName =
                (menuItem != null
                        ? (menuItem['name'] ?? menuItem['item_desc'] ?? '')
                        : (item['friendlyName'] ?? ''))
                    .toString();
            final existingKot = o['kotNumber']?.toString();
            final incomingKot =
                kotNumber?.toString() ?? data['kotNumber']?.toString();
            if (existingName.isNotEmpty &&
                incomingName.isNotEmpty &&
                existingName == incomingName) {
              return existingKot == null ||
                  incomingKot == null ||
                  existingKot == incomingKot;
            }
            return false;
          });

          if (existingIndex != -1) {
            final existing = pendingList[existingIndex];
            if (existing != null &&
                existing['id'] != null &&
                existing['id'] == orderItemId) {
              print(
                '⚠️ Duplicate order detected, skipping: Order ID $orderItemId',
              );
              continue;
            }
          }

          if (existingIndex != -1) {
            final existing = pendingList[existingIndex];
            final existingQty =
                existing['quantity'] is int
                    ? existing['quantity'] as int
                    : int.tryParse(existing['quantity']?.toString() ?? '') ?? 0;
            existing['quantity'] = existingQty + qty;
            existing['amount'] =
                (existing['amount'] is num
                    ? (existing['amount'] as num).toDouble()
                    : double.tryParse(existing['amount']?.toString() ?? '') ??
                        0.0) +
                itemTotal;

            existing['mergedOrderIds'] ??= [];
            if (orderItemId != null)
              existing['mergedOrderIds'].add(orderItemId);
            existing['kotNumbers'] ??= [];
            final kn = kotNumber ?? data['kotNumber'];
            if (kn != null) existing['kotNumbers'].add(kn);

            print('🔁 Merged into existing line');
          } else {
            final formattedOrder = {
              'id': orderItemId,
              'userId': orderItem['userId'] ?? orderItem['user_id'],
              'menuId':
                  menuItem != null
                      ? (menuItem['id'] ?? menuItem['menuId'])
                      : null,
              'item_desc':
                  menuItem != null
                      ? (menuItem['name'] ?? menuItem['item_desc'])
                      : (orderItem['item_desc'] ?? 'Unknown'),
              'quantity': qty,
              'status': 'pending',
              'amount': itemTotal, // ✅ Total with GST
              'amount_per_item': pricePerItemWithGST, // ✅ Per-item with GST
              'taxedAmount':
                  itemTotal, // ✅ STORE taxedAmount for API compatibility
              'taxedActualAmount': itemTotal, // ✅ STORE taxedActualAmount
              'table_number': table['id'],
              'section_number': sectionId,
              'restaurent_table_number':
                  table['table_number'] ??
                  table['restaurent_table_number'] ??
                  null,
              'is_custom': orderItem['is_custom'] ?? false,
              'note': orderItem['note'] ?? orderItem['item_desc'],
              'kotNumber': kotNumber,
              'kotNumbers': [if (kotNumber != null) kotNumber],
              'mergedOrderIds': [if (orderItemId != null) orderItemId],
              'menu': {
                'id': menuItem != null ? (menuItem['id'] ?? null) : null,
                'name':
                    menuItem != null
                        ? (menuItem['name'] ?? 'Unknown')
                        : (orderItem['name'] ?? 'Unknown'),
                'price': basePrice, // ✅ Store base price (before tax)
              },
              'createdAt': DateTime.now().toIso8601String(),
              'updatedAt': DateTime.now().toIso8601String(),
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            };

            pendingList.add(formattedOrder);
            print('✅ Added order: ${formattedOrder['item_desc']}');
          }

          totalAddedAmount += itemTotal;
          addedCount++;
        }

        if (addedCount > 0) {
          _recomputeTableAmounts(table);
          if ((table['status'] ?? 'free') == 'free' &&
              (table['orderAmounts']['totalAmount'] ?? 0) > 0) {
            table['status'] = 'occupied';
            table['seatingTime'] ??= DateTime.now().toIso8601String();
            print('✅ Table status set to occupied');
          }
        }

        _recomputeSectionSummaryInline(sectionIndex);
      });
    });

    // ---------- NEW drinks order handler (replace your existing one) ----------

    socket.on('new_drinks_order', (data) {
      print('🆕 New drinks order received: $data');

      final order = data['order'];
      final sectionId =
          order != null
              ? (order['section'] != null
                  ? (order['section']['id'] is int
                      ? order['section']['id'] as int
                      : int.tryParse(order['section']['id']?.toString() ?? ''))
                  : null)
              : null;

      final tableNumberRaw =
          order != null
              ? (order['actual_table_number'] ??
                  order['table_number'] ??
                  order['restaurent_table_number'] ??
                  order['tableNo'])
              : null;

      final items = (data['items'] as List<dynamic>?) ?? [];
      final kotNumber = data['kotNumber'];

      if (sectionId == null) {
        print('⚠️ Section id missing — aborting drinks handler.');
        return;
      }

      final sectionIndex = sections.indexWhere((s) => s['id'] == sectionId);
      if (sectionIndex == -1) {
        print(
          '⚠️ Section $sectionId not found locally — calling fetchSections()',
        );
        fetchSections();
        return;
      }

      final section = sections[sectionIndex];
      final tableIndex = findTableIndexInSection(section, tableNumberRaw);
      if (tableIndex == -1) {
        print('! Table $tableNumberRaw not found in section $sectionId');
        fetchSections();
        return;
      }

      setState(() {
        final tables = section['tables'] as List<dynamic>;
        final table = tables[tableIndex];

        table['drinksOrders'] ??= {
          'pendingDrinksOrders': [],
          'ongoingDrinksOrders': [],
          'completeDrinksOrders': [],
        };
        table['orderAmounts'] ??= {
          'pendingAmount': 0,
          'ongoingAmount': 0,
          'completeAmount': 0,
          'pendingDrinksAmount': 0,
          'ongoingDrinksAmount': 0,
          'completeDrinksAmount': 0,
          'totalAmount': 0,
        };

        final bool wasTableFree =
            (table['status'] ?? 'free') == 'free' &&
            (table['orderAmounts']['totalAmount'] ?? 0) == 0;
        double totalAddedAmount = 0;

        int addedCount = 0;
        final pendingList =
            table['drinksOrders']['pendingDrinksOrders'] as List<dynamic>;

        for (var item in items) {
          final orderItem = item['orderItem'] ?? item['order_item'];
          final menuItem =
              item['drinkMenu'] ??
              item['menuItem'] ??
              item['menu'] ??
              item['drink_menu'];

          if (orderItem == null) {
            print('⚠️ Skipping drinks item with missing orderItem: $item');
            continue;
          }

          final orderItemId = orderItem['id'];
          final qty =
              orderItem['quantity'] is int
                  ? orderItem['quantity'] as int
                  : int.tryParse(orderItem['quantity']?.toString() ?? '') ?? 1;

          final basePrice =
              (orderItem['price'] is num)
                  ? orderItem['price'] as num
                  : double.tryParse(orderItem['price']?.toString() ?? '') ??
                      0.0;

          final isCustom = orderItem['is_custom'] == true;
          final applyVAT = isCustom || (menuItem?['applyVAT'] == true);

          // ✅ Calculate with appropriate tax and round
          final double taxRate = applyVAT ? 1.10 : 1.05;
          final double exactItemTax = double.parse(
            (basePrice.toDouble() * taxRate).toStringAsFixed(2),
          );
          final double pricePerItemWithTax = exactItemTax.roundToDouble();

          final double exactTotal = double.parse(
            (basePrice.toDouble() * qty * taxRate).toStringAsFixed(2),
          );
          final itemTotal = exactTotal.roundToDouble();

          // Check for duplicates and add/merge logic...
          int existingIndex = pendingList.indexWhere((o) {
            if (o == null) return false;
            if (o['id'] != null &&
                orderItemId != null &&
                o['id'] == orderItemId)
              return true;

            final existingDrinkId =
                o['drink'] != null ? (o['drink']['id'] ?? null) : null;
            final incomingDrinkId =
                menuItem != null
                    ? (menuItem['id'] ?? menuItem['drinkId'] ?? null)
                    : null;
            if (existingDrinkId != null &&
                incomingDrinkId != null &&
                existingDrinkId == incomingDrinkId) {
              final existingKot = o['kotNumber']?.toString();
              final incomingKot =
                  kotNumber?.toString() ?? data['kotNumber']?.toString();
              return existingKot == null ||
                  incomingKot == null ||
                  existingKot == incomingKot;
            }

            final existingName =
                (o['drink'] != null
                        ? (o['drink']['name'] ?? '')
                        : (o['drinkName'] ?? ''))
                    .toString();
            final incomingName =
                (item['friendlyName'] ?? menuItem?['name'])?.toString() ?? '';
            final existingKot = o['kotNumber']?.toString();
            final incomingKot =
                kotNumber?.toString() ?? data['kotNumber']?.toString();
            if (existingName.isNotEmpty &&
                incomingName.isNotEmpty &&
                existingName == incomingName) {
              return existingKot == null ||
                  incomingKot == null ||
                  existingKot == incomingKot;
            }

            return false;
          });

          if (existingIndex != -1) {
            final existing = pendingList[existingIndex];
            if (existing != null &&
                existing['id'] != null &&
                existing['id'] == orderItemId) {
              print('⚠️ Duplicate drinks order detected, skipping.');
              continue;
            }
          }

          if (existingIndex != -1) {
            final existing = pendingList[existingIndex];
            final existingQty =
                existing['quantity'] is int
                    ? existing['quantity'] as int
                    : int.tryParse(existing['quantity']?.toString() ?? '') ?? 0;
            existing['quantity'] = existingQty + qty;
            existing['amount'] =
                (existing['amount'] is num
                    ? (existing['amount'] as num).toDouble()
                    : double.tryParse(existing['amount']?.toString() ?? '') ??
                        0.0) +
                itemTotal;

            existing['mergedOrderIds'] ??= [];
            if (orderItemId != null)
              existing['mergedOrderIds'].add(orderItemId);
            existing['kotNumbers'] ??= [];
            final kn = kotNumber ?? data['kotNumber'];
            if (kn != null) existing['kotNumbers'].add(kn);

            print('🔁 Merged drinks into existing line');
          } else {
            final drinkName =
                menuItem != null
                    ? (menuItem['name'] ??
                        menuItem['friendlyName'] ??
                        'Unknown')
                    : (item['friendlyName'] ?? 'Unknown');

            final formattedOrder = {
              'id': orderItemId,
              'quantity': qty,
              'amount': itemTotal, // ✅ Total with tax
              'amount_per_item': pricePerItemWithTax, // ✅ Per-item with tax
              'taxedAmount': itemTotal, // ✅ STORE for API compatibility
              'taxedActualAmount': itemTotal, // ✅ STORE for API compatibility
              'status': 'pending',
              'is_custom': isCustom,
              'note': orderItem['note'] ?? orderItem['item_desc'],
              'drink': {
                'id': menuItem != null ? (menuItem['id'] ?? null) : null,
                'name': drinkName,
                'price':
                    basePrice.toDouble(), // ✅ Store base price (before tax)
                'applyVAT': applyVAT, // ✅ Store tax info
                'kotCategory':
                    menuItem != null
                        ? (menuItem['categoryName'] ?? menuItem['kotCategory'])
                        : null,
              },
              'kotNumber': kotNumber ?? data['kotNumber'],
              'kotNumbers': [
                if ((kotNumber ?? data['kotNumber']) != null)
                  (kotNumber ?? data['kotNumber']),
              ],
              'mergedOrderIds': [if (orderItemId != null) orderItemId],
              'orderId': orderItem['orderId'] ?? orderItem['orderId'],
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            };

            pendingList.add(formattedOrder);
            print('✅ Added drinks order: $drinkName');
          }

          totalAddedAmount += itemTotal;
          addedCount++;
        }

        if (addedCount > 0) {
          _recomputeTableAmounts(table);
          if ((table['status'] ?? 'free') == 'free' &&
              (table['orderAmounts']['totalAmount'] ?? 0) > 0) {
            table['status'] = 'occupied';
            table['seatingTime'] ??= DateTime.now().toIso8601String();
            print('✅ Table status set to occupied');
          }
        }

        _recomputeSectionSummaryInline(sectionIndex);
      });
    });

    // NEW: Listen for split_table and insert the new split next to its parent
    socket.on('split_table', (data) {
      print('📢 Table split event: $data');

      try {
        final parentTable =
            data['parentTable']; // may be minimal summary or null
        final newTable = data['newTable']; // full table JSON from backend

        if (newTable == null) {
          print('⚠️ split_table event missing newTable payload');
          return;
        }

        setState(() {
          final int? parentId =
              parentTable != null ? (parentTable['id'] as int?) : null;
          final int? sectionIdFromNew =
              newTable['sectionId'] is int
                  ? newTable['sectionId'] as int
                  : int.tryParse(newTable['sectionId']?.toString() ?? '');

          // 1) Try to insert next to parent if parentId present
          if (parentId != null) {
            bool inserted = false;
            for (var s = 0; s < sections.length; s++) {
              final tables = sections[s]['tables'] as List<dynamic>;
              final parentIndex = tables.indexWhere((t) => t['id'] == parentId);
              if (parentIndex != -1) {
                // Insert right after parent
                tables.insert(parentIndex + 1, newTable);
                inserted = true;
                break;
              }
            }
            if (inserted) return;
          }

          // 2) If parent not found, try to add to section by newTable.sectionId
          if (sectionIdFromNew != null) {
            final secIndex = sections.indexWhere(
              (s) => s['id'] == sectionIdFromNew,
            );
            if (secIndex != -1) {
              sections[secIndex]['tables'].add(newTable);
              return;
            }
          }

          // 3) Fallback: add to first section if available
          if (sections.isNotEmpty) {
            sections[0]['tables'].add(newTable);
            return;
          }

          // 4) As absolute fallback, push into sections as a new section wrapper
          sections.add({
            'id': sectionIdFromNew ?? -1,
            'name': 'Unknown',
            'tables': [newTable],
          });
        });
      } catch (e) {
        print('Error handling split_table event: $e');
      }
    });

    // Listen for delete_table event and remove the table + its splits locally
    socket.on('delete_table', (data) {
      print('📢 Table delete event: $data');

      try {
        final int? tableId =
            data['tableId'] is int
                ? data['tableId'] as int
                : int.tryParse(data['tableId']?.toString() ?? '');
        final int? sectionId =
            data['sectionId'] is int
                ? data['sectionId'] as int
                : int.tryParse(data['sectionId']?.toString() ?? '');
        final int? parentTableId =
            data['parentTableId'] is int
                ? data['parentTableId'] as int
                : int.tryParse(data['parentTableId']?.toString() ?? '');

        final deletedTable = data['deletedTable'];
        final int? deletedTableIdFromObj =
            deletedTable != null
                ? (deletedTable['id'] is int
                    ? deletedTable['id'] as int
                    : int.tryParse(deletedTable['id']?.toString() ?? ''))
                : null;

        final int effectiveTableId = tableId ?? deletedTableIdFromObj ?? -1;

        if (effectiveTableId == -1) {
          print('⚠️ delete_table event missing tableId');
          return;
        }

        setState(() {
          bool removed = false;

          // Fast path: section provided
          if (sectionId != null) {
            final secIndex = sections.indexWhere((s) => s['id'] == sectionId);
            if (secIndex != -1) {
              final tables = sections[secIndex]['tables'] as List<dynamic>;

              tables.removeWhere((t) {
                final tid =
                    t['id'] is int
                        ? t['id'] as int
                        : int.tryParse(t['id']?.toString() ?? '');
                final pid =
                    t['parent_table_id'] is int
                        ? t['parent_table_id'] as int
                        : int.tryParse(t['parent_table_id']?.toString() ?? '');
                final match =
                    tid == effectiveTableId || pid == effectiveTableId;
                if (match) removed = true;
                return match;
              });

              if (removed) {
                print(
                  '✅ Removed duplicate table $effectiveTableId from section $sectionId',
                );
                return;
              }
            }
          }

          // Fallback: search all sections
          for (var s = 0; s < sections.length; s++) {
            final tables = sections[s]['tables'] as List<dynamic>;
            final prevLen = tables.length;

            tables.removeWhere((t) {
              final tid =
                  t['id'] is int
                      ? t['id'] as int
                      : int.tryParse(t['id']?.toString() ?? '');
              return tid == effectiveTableId;
            });

            if (tables.length != prevLen) {
              removed = true;

              // Also remove any splits referencing this table
              tables.removeWhere((t) {
                final pid =
                    t['parent_table_id'] is int
                        ? t['parent_table_id'] as int
                        : int.tryParse(t['parent_table_id']?.toString() ?? '');
                return pid == effectiveTableId;
              });

              print('✅ Removed table $effectiveTableId and its splits');
              break;
            }
          }

          if (!removed) {
            print('⚠️ Table $effectiveTableId not found for deletion');
          }
        });
      } catch (e) {
        print('Error handling delete_table event: $e');
      }
    });

    // Updated socket listener for update_order_status
    socket.on('update_order_status', (data) {
      print('📝 Order status update received: $data');

      final orderId = data['orderId']?.toString();
      final orderType = data['orderType']?.toString();
      final newStatus = data['newStatus']?.toString();
      final sectionId =
          data['sectionId'] is int
              ? data['sectionId'] as int
              : int.tryParse(data['sectionId']?.toString() ?? '');
      final tableId = data['tableId'];

      // ✅ FIX: Use stored amount_per_item instead of socket amount
      final amount = 0.0; // Don't use socket amount - we'll recalculate

      // Extract other data
      final kotNumber = data['kotNumber']?.toString();
      final menuName = data['menuName']?.toString();
      final drinkName = data['drinkName']?.toString();

      if (orderId == null ||
          orderType == null ||
          newStatus == null ||
          sectionId == null) {
        print('⚠️ Missing required fields in order status update');
        return;
      }

      setState(() {
        // Find the section
        final sectionIndex = sections.indexWhere((s) => s['id'] == sectionId);
        if (sectionIndex == -1) {
          print('⚠️ Section $sectionId not found for order status update');
          return;
        }

        // Find the table
        final section = sections[sectionIndex];
        final tableIndex = findTableIndexInSection(section, tableId);
        if (tableIndex == -1) {
          print('⚠️ Table $tableId not found in section $sectionId');
          return;
        }

        final tables = section['tables'] as List<dynamic>;
        final table = tables[tableIndex];

        final String? menuNameFromPayload = menuName ?? drinkName;

        // Update the order based on type with KOT number
        if (orderType == 'food') {
          _updateFoodOrderStatusFixed(
            table,
            orderId,
            newStatus,
            amount, // Pass 0 - function will use stored amount_per_item
            menuNameFromPayload,
            kotNumber,
          );
        } else if (orderType == 'drinks') {
          _updateDrinksOrderStatusFixed(
            table,
            orderId,
            newStatus,
            amount, // Pass 0 - function will use stored amount_per_item
            menuNameFromPayload,
            kotNumber,
          );
        }
      });
    });
  }

  // FIXED + DEBUG: Food order status update function with detailed incoming-data logging
  void _updateFoodOrderStatusFixed(
    Map<String, dynamic> table,
    String orderId,
    String newStatus,
    dynamic amount,
    String? menuNameFromPayload,
    String? kotNumber,
  ) {
    try {
      print('🔧 [_updateFoodOrderStatusFixed] START');
      print(
        '➡ orderId=$orderId | newStatus=$newStatus | kot=$kotNumber | menu=$menuNameFromPayload',
      );
      print('➡ Incoming amount: $amount (type: ${amount.runtimeType})');
      final orderIdStr = orderId.toString();

      final normalizedStatus = (newStatus ?? '').toString().toLowerCase();
      final kotStr = kotNumber?.toString().trim();
      final incomingName = (menuNameFromPayload ?? '').trim().toLowerCase();

      print(
        '➡ orderId=$orderIdStr | newStatus=$normalizedStatus | kot=$kotStr | menu=$incomingName',
      );

      // --- Normalize table structure ---
      table['orders'] ??= <String, dynamic>{};
      for (final key in ['pendingOrders', 'ongoingOrders', 'completeOrders']) {
        table['orders'][key] ??= <dynamic>[];
      }
      table['orderAmounts'] ??= {
        'pendingAmount': 0.0,
        'ongoingAmount': 0.0,
        'completeAmount': 0.0,
        'pendingDrinksAmount': 0.0,
        'ongoingDrinksAmount': 0.0,
        'completeDrinksAmount': 0.0,
        'totalAmount': 0.0,
      };

      // --- Map statuses ---
      final targetMap = {
        'pending': 'pendingOrders',
        'accepted': 'ongoingOrders',
        'ongoing': 'ongoingOrders',
        'in_progress': 'ongoingOrders',
        'complete': 'completeOrders', // ✅ Added
        'completed': 'completeOrders', // ✅ Added
      };

      final targetListKey = targetMap[normalizedStatus] ?? 'ongoingOrders';

      final displayStatus =
          (['complete', 'completed'].contains(normalizedStatus))
              ? 'completed'
              : ([
                'accepted',
                'ongoing',
                'in_progress',
              ].contains(normalizedStatus))
              ? 'accepted'
              : 'pending';

      print('🎯 Target list: $targetListKey, Display status: $displayStatus');

      // --- Matching logic mode ---
      final matchMode =
          (kotStr != null && kotStr.isNotEmpty) ? 'byKot' : 'byId';
      print('🔍 Match mode: $matchMode');

      // --- Process ---
      final List<Map<String, dynamic>> itemsToMove = [];
      double totalAmountToMove = 0.0;
      String? sourceListKey; // Track which list we found the item in

      for (final listKey in [
        'pendingOrders',
        'ongoingOrders',
        'completeOrders',
      ]) {
        final dynamic rawList = table['orders'][listKey];
        if (rawList is! List) {
          print(
            '⚠️ expected list at orders.$listKey but found ${rawList.runtimeType}, skipping.',
          );
          continue;
        }

        final orderList = rawList.cast<Map<String, dynamic>>();
        print('🔍 Scanning $listKey (${orderList.length} items)...');
        final toRemove = <int>[];

        for (int i = 0; i < orderList.length; i++) {
          final item = orderList[i];
          final itemId = item['id']?.toString() ?? '';
          final itemOrderId = item['orderId']?.toString() ?? '';
          final itemKot = item['kotNumber']?.toString();
          final itemName =
              (item['menu']?['name'] ?? item['item_desc'] ?? '')
                  .toString()
                  .trim()
                  .toLowerCase();

          bool match = false;

          if (matchMode == 'byKot' && kotStr != null && kotStr.isNotEmpty) {
            // ✅ Match by BOTH KOT number AND item name to prevent updating all items with same KOT
            if (itemKot != null && itemKot.toString().trim() == kotStr) {
              // Also check if the item name matches (if provided)
              if (incomingName.isNotEmpty) {
                if (itemName == incomingName) {
                  match = true;
                }
              } else {
                // If no name provided, fall back to KOT-only match (legacy support)
                match = true;
              }
            }
          } else {
            if (itemId == orderIdStr || itemOrderId == orderIdStr) {
              match = true;
            } else {
              final merged = item['mergedOrderIds'];
              if (merged is Iterable) {
                try {
                  if ((merged).any((m) => m?.toString() == orderIdStr)) {
                    match = true;
                  }
                } catch (_) {}
              }
            }
          }

          if (match) {
            print(
              '✅ Match found in $listKey → $itemName (id:$itemId, orderId:$itemOrderId, KOT:$itemKot)',
            );

            // ✅ Use stored amount_per_item
            double amt;
            final itemAmountPerItem = item['amount_per_item'];
            if (itemAmountPerItem is num && itemAmountPerItem != 0) {
              amt = itemAmountPerItem.toDouble();
            } else if (item['amount'] is num && item['quantity'] is num) {
              final qty = (item['quantity'] as num).toInt();
              if (qty > 0) {
                amt = (item['amount'] as num).toDouble() / qty;
              } else {
                amt = 0.0;
              }
            } else {
              amt = double.tryParse(itemAmountPerItem?.toString() ?? '') ?? 0.0;

              if (amt == 0.0 && item['menu'] is Map) {
                final menuPrice = item['menu']['price'];
                if (menuPrice is num) {
                  amt = (menuPrice as num).toDouble() * 1.05;
                }
              }
            }

            final movedItem = <String, dynamic>{}..addAll(item);
            movedItem['status'] = displayStatus;
            movedItem['timestamp'] = DateTime.now().millisecondsSinceEpoch;
            movedItem['amount_per_item'] = amt;

            final finalQty =
                (movedItem['quantity'] is num)
                    ? (movedItem['quantity'] as num).toInt()
                    : int.tryParse(movedItem['quantity']?.toString() ?? '') ??
                        1;
            movedItem['amount'] = amt * finalQty;

            totalAmountToMove += movedItem['amount'];
            itemsToMove.add(movedItem);
            toRemove.add(i);
            sourceListKey = listKey; // ✅ Remember source list
          }
        }

        // Remove matched items
        for (final idx in toRemove.reversed) {
          orderList.removeAt(idx);
        }

        if (toRemove.isNotEmpty) break; // Stop after finding in one list
      }

      if (itemsToMove.isEmpty) {
        print(
          '⚠️ No matching item found for mode=$matchMode kot=$kotStr orderId=$orderIdStr',
        );
        print('🔧 [_updateFoodOrderStatusFixed] END\n');
        return;
      }

      // --- Move to new list ---
      final targetListDynamic = table['orders'][targetListKey];
      if (targetListDynamic is! List) {
        table['orders'][targetListKey] = <dynamic>[];
      }
      final targetList = table['orders'][targetListKey] as List;
      targetList.addAll(itemsToMove);

      // --- Update amounts ---
      final amountKeyMap = {
        'pendingOrders': 'pendingAmount',
        'ongoingOrders': 'ongoingAmount',
        'completeOrders': 'completeAmount',
      };

      // ✅ Subtract from source
      if (sourceListKey != null) {
        final sourceAmountKey = amountKeyMap[sourceListKey];
        if (sourceAmountKey != null) {
          final prevSource = (table['orderAmounts'][sourceAmountKey] ?? 0.0);
          final prevSourceDouble =
              (prevSource is num)
                  ? prevSource.toDouble()
                  : double.tryParse(prevSource?.toString() ?? '') ?? 0.0;
          table['orderAmounts'][sourceAmountKey] =
              prevSourceDouble - totalAmountToMove;
          print(
            '📉 Deducted ₹${totalAmountToMove.toStringAsFixed(2)} from $sourceAmountKey',
          );
        }
      }

      // ✅ Add to target
      final targetAmountKey = amountKeyMap[targetListKey] ?? 'ongoingAmount';
      final prevTarget = (table['orderAmounts'][targetAmountKey] ?? 0.0);
      final prevTargetDouble =
          (prevTarget is num)
              ? prevTarget.toDouble()
              : double.tryParse(prevTarget?.toString() ?? '') ?? 0.0;
      table['orderAmounts'][targetAmountKey] =
          prevTargetDouble + totalAmountToMove;

      print(
        '✅ Moved ${itemsToMove.length} items → $targetListKey (+₹${totalAmountToMove.toStringAsFixed(2)})',
      );
      print('🔧 [_updateFoodOrderStatusFixed] END\n');
    } catch (e, st) {
      print('❌ Error in _updateFoodOrderStatusFixed: $e\n$st');
    }
  }

  // FIXED: Drinks order status update function with proper quantity splitting
  void _updateDrinksOrderStatusFixed(
    Map<String, dynamic> table,
    String orderId,
    String newStatus,
    dynamic amount,
    String? menuNameFromPayload,
    String? kotNumber,
  ) {
    try {
      print('🔧 [_updateDrinksOrderStatusFixed] START');
      print(
        '➡ orderId=$orderId | newStatus=$newStatus | kot=$kotNumber | menu=$menuNameFromPayload',
      );

      final orderIdStr = orderId.toString();
      final normalizedStatus = (newStatus ?? '').toString().toLowerCase();
      final kotStr = kotNumber?.toString().trim();
      final incomingName = (menuNameFromPayload ?? '').trim().toLowerCase();

      // --- Normalize table structure ---
      table['drinksOrders'] ??= <String, dynamic>{};
      for (final key in [
        'pendingDrinksOrders',
        'ongoingDrinksOrders',
        'completeDrinksOrders',
      ]) {
        table['drinksOrders'][key] ??= <dynamic>[];
      }
      table['orderAmounts'] ??= {
        'pendingAmount': 0.0,
        'ongoingAmount': 0.0,
        'completeAmount': 0.0,
        'pendingDrinksAmount': 0.0,
        'ongoingDrinksAmount': 0.0,
        'completeDrinksAmount': 0.0,
        'totalAmount': 0.0,
      };

      // --- Map statuses ---
      final targetMap = {
        'pending': 'pendingDrinksOrders',
        'accepted': 'ongoingDrinksOrders',
        'ongoing': 'ongoingDrinksOrders',
        'in_progress': 'ongoingDrinksOrders',
        'complete': 'completeDrinksOrders',
        'completed': 'completeDrinksOrders',
      };

      final targetListKey =
          targetMap[normalizedStatus] ?? 'ongoingDrinksOrders';

      final displayStatus =
          (['complete', 'completed'].contains(normalizedStatus))
              ? 'completed'
              : ([
                'accepted',
                'ongoing',
                'in_progress',
              ].contains(normalizedStatus))
              ? 'accepted'
              : 'pending';

      print('🎯 Target list: $targetListKey, Display status: $displayStatus');

      // --- Process ---
      final List<Map<String, dynamic>> itemsToMove = [];
      double totalAmountToMove = 0.0;
      String? sourceListKey;

      for (final listKey in [
        'pendingDrinksOrders',
        'ongoingDrinksOrders',
        'completeDrinksOrders',
      ]) {
        final dynamic rawList = table['drinksOrders'][listKey];
        if (rawList is! List) continue;

        final orderList = rawList.cast<Map<String, dynamic>>();
        print('🔍 Scanning $listKey (${orderList.length} items)...');
        final toRemove = <int>[];

        for (int i = 0; i < orderList.length; i++) {
          final item = orderList[i];
          final itemId = item['id']?.toString() ?? '';
          final itemOrderId = item['orderId']?.toString() ?? '';
          final itemKot = item['kotNumber']?.toString();
          final itemName =
              (item['drink']?['name'] ?? item['drinkName'] ?? '')
                  .toString()
                  .trim()
                  .toLowerCase();

          bool match = false;

          // ✅ FIXED: Better matching logic for drinks
          // 1. Try exact ID match first
          if (itemId == orderIdStr || itemOrderId == orderIdStr) {
            match = true;
            print('✅ Match by ID: $itemId == $orderIdStr');
          }

          // 2. Try KOT + name match (for consolidated orders)
          if (!match &&
              kotStr != null &&
              kotStr.isNotEmpty &&
              itemKot != null) {
            if (itemKot.toString().trim() == kotStr) {
              // Also check name if provided
              if (incomingName.isNotEmpty) {
                if (itemName == incomingName) {
                  match = true;
                  print(
                    '✅ Match by KOT + name: $itemKot == $kotStr, $itemName == $incomingName',
                  );
                }
              } else {
                match = true;
                print('✅ Match by KOT only: $itemKot == $kotStr');
              }
            }
          }

          // 3. Try mergedOrderIds
          if (!match) {
            final merged = item['mergedOrderIds'];
            if (merged is Iterable) {
              try {
                if (merged.any((m) => m?.toString() == orderIdStr)) {
                  match = true;
                  print('✅ Match by mergedOrderIds: contains $orderIdStr');
                }
              } catch (_) {}
            }
          }

          if (match) {
            print('✅ Match found in $listKey → $itemName (id:$itemId)');

            // ✅ Calculate amount per item with proper tax
            double amt;
            final itemAmountPerItem = item['amount_per_item'];
            if (itemAmountPerItem is num && itemAmountPerItem != 0) {
              amt = itemAmountPerItem.toDouble();
            } else if (item['amount'] is num && item['quantity'] is num) {
              final qty = (item['quantity'] as num).toInt();
              if (qty > 0) {
                amt = (item['amount'] as num).toDouble() / qty;
              } else {
                amt = 0.0;
              }
            } else {
              amt = double.tryParse(itemAmountPerItem?.toString() ?? '') ?? 0.0;

              // Fallback to drink price with tax
              if (amt == 0.0 && item['drink'] is Map) {
                final drinkPrice = item['drink']['price'];
                if (drinkPrice is num) {
                  final basePrice = (drinkPrice as num).toDouble();
                  final applyVAT =
                      item['drink']['applyVAT'] == true ||
                      item['is_custom'] == true;
                  amt = applyVAT ? (basePrice * 1.10) : (basePrice * 1.05);
                }
              }
            }

            final movedItem = <String, dynamic>{}..addAll(item);
            movedItem['status'] = displayStatus;
            movedItem['timestamp'] = DateTime.now().millisecondsSinceEpoch;
            movedItem['amount_per_item'] =
                double.parse(amt.toStringAsFixed(2)).roundToDouble();

            final finalQty =
                (movedItem['quantity'] is num)
                    ? (movedItem['quantity'] as num).toInt()
                    : int.tryParse(movedItem['quantity']?.toString() ?? '') ??
                        1;
            movedItem['amount'] = (amt * finalQty).roundToDouble();

            totalAmountToMove += movedItem['amount'];
            itemsToMove.add(movedItem);
            toRemove.add(i);
            sourceListKey = listKey;
          }
        }

        // Remove matched items
        for (final idx in toRemove.reversed) {
          orderList.removeAt(idx);
        }

        if (toRemove.isNotEmpty) break;
      }

      if (itemsToMove.isEmpty) {
        print(
          '⚠️ No matching drink item found for orderId=$orderIdStr, kot=$kotStr, name=$incomingName',
        );
        print('🔧 [_updateDrinksOrderStatusFixed] END\n');
        return;
      }

      // --- Move to new list ---
      final targetListDynamic = table['drinksOrders'][targetListKey];
      if (targetListDynamic is! List) {
        table['drinksOrders'][targetListKey] = <dynamic>[];
      }
      final targetList = table['drinksOrders'][targetListKey] as List;
      targetList.addAll(itemsToMove);

      // --- Update amounts ---
      final amountKeyMap = {
        'pendingDrinksOrders': 'pendingDrinksAmount',
        'ongoingDrinksOrders': 'ongoingDrinksAmount',
        'completeDrinksOrders': 'completeDrinksAmount',
      };

      // ✅ Subtract from source
      if (sourceListKey != null) {
        final sourceAmountKey = amountKeyMap[sourceListKey];
        if (sourceAmountKey != null) {
          final prevSource = (table['orderAmounts'][sourceAmountKey] ?? 0.0);
          final prevSourceDouble =
              (prevSource is num)
                  ? prevSource.toDouble()
                  : double.tryParse(prevSource?.toString() ?? '') ?? 0.0;
          table['orderAmounts'][sourceAmountKey] =
              (prevSourceDouble - totalAmountToMove).roundToDouble();
          print(
            '📉 Deducted ₹${totalAmountToMove.toStringAsFixed(2)} from $sourceAmountKey',
          );
        }
      }

      // ✅ Add to target
      final targetAmountKey =
          amountKeyMap[targetListKey] ?? 'ongoingDrinksAmount';
      final prevTarget = (table['orderAmounts'][targetAmountKey] ?? 0.0);
      final prevTargetDouble =
          (prevTarget is num)
              ? prevTarget.toDouble()
              : double.tryParse(prevTarget?.toString() ?? '') ?? 0.0;
      table['orderAmounts'][targetAmountKey] =
          (prevTargetDouble + totalAmountToMove).roundToDouble();

      print(
        '✅ Moved ${itemsToMove.length} drink item(s) → $targetListKey (+₹${totalAmountToMove.toStringAsFixed(2)})',
      );
      print('🔧 [_updateDrinksOrderStatusFixed] END\n');
    } catch (e, st) {
      print('❌ Error in _updateDrinksOrderStatusFixed: $e\n$st');
    }
  }

  void _printCheckKOT(
    BuildContext context,
    dynamic table,
    int index,
    String sectionName,
  ) {
    try {
      // Get ALL orders (pending, ongoing, and complete)
      final List<dynamic> allFoodItems = [
        ...(table['orders']?['pendingOrders'] ?? []),
        ...(table['orders']?['ongoingOrders'] ?? []),
        ...(table['orders']?['completeOrders'] ?? []),
      ];

      final List<dynamic> allDrinkItems = [
        ...(table['drinksOrders']?['pendingDrinksOrders'] ?? []),
        ...(table['drinksOrders']?['ongoingDrinksOrders'] ?? []),
        ...(table['drinksOrders']?['completeDrinksOrders'] ?? []),
      ];

      // Check if there are any items
      if (allFoodItems.isEmpty && allDrinkItems.isEmpty) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No items to print in Check KOT',
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Group items
      Map<String, Map<String, dynamic>> groupedFoodItems = _groupItems(
        allFoodItems,
        'food',
      );
      Map<String, Map<String, dynamic>> groupedDrinkItems = _groupItems(
        allDrinkItems,
        'drink',
      );

      // Build HTML
      String html = _buildCheckKOTHtml(
        groupedFoodItems,
        groupedDrinkItems,
        sectionName,
        index,
      );

      // Print
      print_service.triggerPrintWindow(html);
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Check KOT printed successfully!',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('Error in _printCheckKOT: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error printing Check KOT: $e',
            style: GoogleFonts.poppins(color: Colors.white),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Helper method to group items (reuse from GenerateBillPage logic)
  Map<String, Map<String, dynamic>> _groupItems(
    List<dynamic> items,
    String type,
  ) {
    Map<String, Map<String, dynamic>> groupedItems = {};

    for (var item in items) {
      String name;
      double price;
      int qty;

      if (type == 'food') {
        name =
            item['is_custom'] == true
                ? (item['note'] ?? item['item_desc'] ?? 'Custom Item')
                : (item['menu']?['name'] ?? item['item_desc']);
        price =
            double.tryParse(
              item['menu']?['price']?.toString() ??
                  item['actualAmount'].toString(),
            ) ??
            item['actualAmount'] ??
            item['amount_per_item'] ??
            0;
        qty = item['quantity'] ?? 0;
      } else {
        name =
            item['is_custom'] == true
                ? (item['note'] ?? item['item_desc'] ?? 'Custom Drink')
                : (item['drink']?['name'] ?? item['item_desc']);
        price =
            double.tryParse(
              item['drink']?['price']?.toString() ??
                  item['actualAmount'].toString(),
            ) ??
            item['actualAmount'] ??
            item['amount_per_item'] ??
            0;
        qty = item['quantity'] ?? 0;
      }

      if (groupedItems.containsKey(name)) {
        groupedItems[name]!['qty'] += qty;
        groupedItems[name]!['totalAmount'] = groupedItems[name]!['qty'] * price;
      } else {
        groupedItems[name] = {
          'name': name,
          'price': price,
          'qty': qty,
          'totalAmount': qty * price,
          'type': type,
        };
      }
    }

    return groupedItems;
  }

  String _buildCheckKOTHtml(
    Map<String, Map<String, dynamic>> groupedFoodItems,
    Map<String, Map<String, dynamic>> groupedDrinkItems,
    String sectionName,
    int tableIndex,
  ) {
    final foodRows =
        groupedFoodItems.values.map((item) {
          final name = item['name'];
          final qty = item['qty'];
          return '''
      <tr>
        <td style="padding: 4px 0;">$name</td>
        <td style="text-align:center; padding: 4px 0;">$qty</td>
      </tr>
    ''';
        }).join();

    final drinkRows =
        groupedDrinkItems.values.map((item) {
          final name = item['name'];
          final qty = item['qty'];
          return '''
      <tr>
        <td style="padding: 4px 0;">$name</td>
        <td style="text-align:center; padding: 4px 0;">$qty</td>
      </tr>
    ''';
        }).join();

    int totalItems =
        groupedFoodItems.values.fold(
          0,
          (sum, item) => sum + (item['qty'] as int),
        ) +
        groupedDrinkItems.values.fold(
          0,
          (sum, item) => sum + (item['qty'] as int),
        );

    String line = '_________________________________';

    return '''
  <div style="font-family: Calibri, Arial, sans-serif; width: 100%; font-size:22px;">
    <div style="text-align:center;">
      <strong style="font-size:30px;">5K Family Resto & Bar</strong><br>
      <span style="font-size:20px;">CHECK KOT</span><br>
    </div>

    <pre style="font-size:22px;text-align:center;margin:0;padding:0;line-height:1;">$line</pre>

    <table style="width:100%;font-size:21px;">
      <tr>
        <td>Date: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}</td>
        <td style="text-align:right;">Time: ${DateFormat('hh:mm a').format(DateTime.now())}</td>
      </tr>
      <tr>
        <td style="text-align:left;">Table: $sectionName-${tableIndex + 1}</td>
        <td style="text-align:right;"></td>
      </tr>
    </table>

    <pre style="font-size:22px;text-align:center;margin:0;padding:0;line-height:1;">$line</pre>

    <table style="width:100%;border-collapse:collapse;font-size:21px;">
      <tr><th style="text-align:left;">Item</th><th style="text-align:center;">Qty</th></tr>

      ${groupedFoodItems.isNotEmpty ? '''
        <tr><td colspan="2" style="font-weight:bold; padding-top: 8px;">Food & Beverages</td></tr>
        $foodRows
      ''' : ''}

      ${groupedDrinkItems.isNotEmpty ? '''
        <tr><td colspan="2" style="font-weight:bold; padding-top: 8px;">Drinks</td></tr>
        $drinkRows
      ''' : ''}
    </table>

    <pre style="font-size:22px;text-align:center;margin:0;padding:0;line-height:1;">$line</pre>

    <table style="width:100%;font-size:21px;">
      <tr style="font-weight:bold;font-size:23px;">
        <td>Total Items:</td>
        <td style="text-align:right; margin-right:5px">$totalItems</td>
      </tr>
    </table>
</div>
  ''';
  }

  void _normalizeSectionAmounts() {
    for (final section in sections) {
      for (final table in (section['tables'] as List? ?? [])) {
        if (table == null) continue;

        // ---- FOOD ----
        final orders = table['orders'] as Map? ?? {};
        for (final listKey in [
          'pendingOrders',
          'ongoingOrders',
          'completeOrders',
        ]) {
          final list = orders[listKey];
          if (list is! List) continue;
          for (final o in list) {
            if (o == null || o is! Map) continue;
            _normalizeOrderAmount(o, 'food');
          }
        }

        // ---- DRINKS ----
        final drinks = table['drinksOrders'] as Map? ?? {};
        for (final listKey in [
          'pendingDrinksOrders',
          'ongoingDrinksOrders',
          'completeDrinksOrders',
        ]) {
          final list = drinks[listKey];
          if (list is! List) continue;
          for (final o in list) {
            if (o == null || o is! Map) continue;
            _normalizeOrderAmount(o, 'drink');
          }
        }

        // Recompute totals from now-consistent amounts
        _recomputeTableAmounts(table);
      }
    }
  }

  void _normalizeOrderAmount(Map o, String type) {
    final qty = _parseQuantity(o['quantity']);
    if (qty == 0) return;

    if (o['taxedAmount'] is num && (o['taxedAmount'] as num) > 0) {
      o['amount'] = (o['taxedAmount'] as num).toDouble().roundToDouble();
      o['amount_per_item'] = ((o['amount'] as double) / qty).roundToDouble();
      return;
    }

    if (type == 'drink' && o['amount'] is num) {
      final base = (o['amount'] as num).toDouble();

      // ✅ RULE: applyVAT on the order itself is the source of truth.
      // - true  → always 10%
      // - false → always 5% (even if is_custom == true)
      // - null/absent → fall back to drink.applyVAT
      bool applyVAT;
      if (o['applyVAT'] == true) {
        applyVAT = true;
      } else if (o['applyVAT'] == false) {
        applyVAT = false; // explicit false wins over is_custom
      } else {
        // applyVAT not set on order — check drink sub-object
        applyVAT = o['drink']?['applyVAT'] == true;
      }

      final taxRate = applyVAT ? 1.10 : 1.05;
      final taxedPerItem = double.parse(
        ((base / qty) * taxRate).toStringAsFixed(2),
      );
      final taxedTotal = double.parse((taxedPerItem * qty).toStringAsFixed(2));
      o['amount'] = taxedTotal;
      o['amount_per_item'] = taxedPerItem;
      return;
    }

    if (type == 'food' && o['amount'] is num) {
      final base = (o['amount'] as num).toDouble();
      final taxedPerItem = double.parse(
        ((base / qty) * 1.05).toStringAsFixed(2),
      );
      final taxedTotal = double.parse((taxedPerItem * qty).toStringAsFixed(2));
      o['amount'] = taxedTotal;
      o['amount_per_item'] = taxedPerItem;
      return;
    }
  }

  // Same logic applied for drinks (handles mergedOrderIds too)
  void _updateDrinksOrderStatus(
    Map<String, dynamic> table,
    String orderId,
    String newStatus,
    dynamic amount, // incoming value might be num or string
    String? menuNameFromPayload,
  ) {
    final double parsedAmount = _parseAmount(amount);

    // derive an incoming drink label if provided or amount looks like text
    String? incomingMenuLabel;
    if (menuNameFromPayload != null &&
        menuNameFromPayload.toString().trim().isNotEmpty) {
      incomingMenuLabel = menuNameFromPayload.toString().trim();
    } else if (amount is String) {
      final cleaned = amount.replaceAll(RegExp(r'[\d\.\,\s₹\-]'), '');
      if (cleaned.isNotEmpty) incomingMenuLabel = amount.toString().trim();
    }

    final newStatusLower = (newStatus ?? '').toString().toLowerCase();

    // Normalize statuses -> target lists and display status
    final statusToDrinksKey = <String, String>{
      'pending': 'pendingDrinksOrders',
      'accepted': 'ongoingDrinksOrders',
      'ongoing': 'ongoingDrinksOrders',
      'in_progress': 'ongoingDrinksOrders',
      'complete': 'completeDrinksOrders',
      'completed': 'completeDrinksOrders',
    };

    String displayStatus;
    if (['ongoing', 'accepted', 'in_progress'].contains(newStatusLower)) {
      displayStatus = 'accepted';
    } else if (['complete', 'completed'].contains(newStatusLower)) {
      displayStatus = 'completed';
    } else if (newStatusLower == 'pending' || newStatusLower.isEmpty) {
      displayStatus = 'pending';
    } else {
      displayStatus = newStatusLower;
    }

    final String targetList =
        statusToDrinksKey[newStatusLower] ?? '${newStatusLower}DrinksOrders';

    // ensure structures
    table['drinksOrders'] ??= <String, dynamic>{};
    table['drinksOrders']['pendingDrinksOrders'] ??= <dynamic>[];
    table['drinksOrders']['ongoingDrinksOrders'] ??= <dynamic>[];
    table['drinksOrders']['completeDrinksOrders'] ??= <dynamic>[];

    table['orderAmounts'] ??= <String, dynamic>{};
    table['orderAmounts']['pendingAmount'] ??= 0;
    table['orderAmounts']['ongoingAmount'] ??= 0;
    table['orderAmounts']['completeAmount'] ??= 0;
    table['orderAmounts']['pendingDrinksAmount'] ??= 0;
    table['orderAmounts']['ongoingDrinksAmount'] ??= 0;
    table['orderAmounts']['completeDrinksAmount'] ??= 0;
    table['orderAmounts']['totalAmount'] ??= 0;

    Map<String, dynamic>? singleMovedOrder;
    String? fromStatusListKey;

    // search lists for direct id match OR mergedOrderIds contains orderId
    for (String statusKey in [
      'pendingDrinksOrders',
      'ongoingDrinksOrders',
      'completeDrinksOrders',
    ]) {
      final orderList = (table['drinksOrders'][statusKey] as List<dynamic>);
      int foundIndex = -1;

      bool matchedAsMerged = false;

      for (var i = 0; i < orderList.length; i++) {
        final order = orderList[i];
        if (order == null) continue;

        final listId = order['id'];
        final listParentId = order['orderId'];
        final listAlt =
            order['order_item_id'] ?? order['itemId'] ?? order['order_item'];

        // ✅ Get item name for comparison
        final listItemName =
            (order['drink']?['name'] ?? order['drinkName'] ?? '')
                .toString()
                .trim()
                .toLowerCase();

        // ✅ Try exact ID match first
        if (listId?.toString() == orderId ||
            listParentId?.toString() == orderId ||
            listAlt?.toString() == orderId) {
          foundIndex = i;
          matchedAsMerged = false;
          break;
        }

        // ✅ For merged orders, also check item name if available
        final merged = order['mergedOrderIds'];
        if (merged is List) {
          final has = merged.any((m) => m?.toString() == orderId);
          if (has) {
            // If we have an incoming name, verify it matches
            if (incomingMenuLabel != null && incomingMenuLabel.isNotEmpty) {
              if (listItemName == incomingMenuLabel.trim().toLowerCase()) {
                foundIndex = i;
                matchedAsMerged = true;
                break;
              }
            } else {
              // No name to verify, use ID match only
              foundIndex = i;
              matchedAsMerged = true;
              break;
            }
          }
        }
      }

      if (foundIndex != -1) {
        final existing = orderList[foundIndex] as Map<String, dynamic>?;
        final String amountKey = statusKey
            .replaceAll('DrinksOrders', 'DrinksAmount')
            .replaceAll('Orders', 'Amount');

        if (existing == null) {
          orderList.removeAt(foundIndex);
          fromStatusListKey = statusKey;
          table['orderAmounts'][amountKey] =
              (table['orderAmounts'][amountKey] ?? 0) - parsedAmount;
          table['orderAmounts']['totalAmount'] =
              (table['orderAmounts']['totalAmount'] ?? 0) - parsedAmount;
          singleMovedOrder = {
            'id': int.tryParse(orderId) ?? orderId,
            'order_item_id': int.tryParse(orderId) ?? orderId,
            'quantity': 1,
            'amount': parsedAmount,
            'status': displayStatus,
            'drink': {'name': incomingMenuLabel ?? 'Drink #$orderId'},
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          };
        } else if (matchedAsMerged) {
          final num existingQtyNum =
              existing['quantity'] is num
                  ? existing['quantity'] as num
                  : int.tryParse(existing['quantity']?.toString() ?? '') ?? 0;
          final int existingQty = existingQtyNum.toInt();

          final num existingAmountNum =
              existing['amount'] is num
                  ? existing['amount'] as num
                  : double.tryParse(existing['amount']?.toString() ?? '') ??
                      0.0;
          final double existingAmount = existingAmountNum.toDouble();

          double unit =
              existingQty > 0 ? existingAmount / existingQty : parsedAmount;

          singleMovedOrder = {
            'id': int.tryParse(orderId) ?? orderId,
            'order_item_id': int.tryParse(orderId) ?? orderId,
            'quantity': 1,
            'amount': double.parse(unit.toStringAsFixed(2)),
            'status': displayStatus,
            'drink':
                existing['drink'] ??
                {'name': incomingMenuLabel ?? 'Drink #$orderId'},
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          };

          final newQty = existingQty - 1;
          if (newQty <= 0) {
            orderList.removeAt(foundIndex);
          } else {
            existing['quantity'] = newQty;
            existing['amount'] = double.parse(
              (existingAmount - unit).toStringAsFixed(2),
            );
            if (existing['mergedOrderIds'] is List) {
              existing['mergedOrderIds'] =
                  (existing['mergedOrderIds'] as List)
                      .where((m) => m?.toString() != orderId)
                      .toList();
            }
            if (existing['kotNumbers'] is List) {
              existing['kotNumbers'] =
                  (existing['kotNumbers'] as List)
                      .where((k) => k?.toString() != orderId)
                      .toList();
            }
          }

          table['orderAmounts'][amountKey] =
              (table['orderAmounts'][amountKey] ?? 0) - unit;
          table['orderAmounts']['totalAmount'] =
              (table['orderAmounts']['totalAmount'] ?? 0) - unit;
        } else {
          final double prevAmount = _parseAmount(
            existing['amount'],
            fallback: parsedAmount,
          );
          singleMovedOrder = Map<String, dynamic>.from(existing);
          orderList.removeAt(foundIndex);
          table['orderAmounts'][amountKey] =
              (table['orderAmounts'][amountKey] ?? 0) - prevAmount;
          table['orderAmounts']['totalAmount'] =
              (table['orderAmounts']['totalAmount'] ?? 0) - prevAmount;
        }

        fromStatusListKey = statusKey;
        break;
      }
    }

    // Move or create placeholder
    if (singleMovedOrder != null) {
      if ((singleMovedOrder['drink'] == null ||
              (singleMovedOrder['drink'] is Map &&
                  (singleMovedOrder['drink']['name'] == null ||
                      singleMovedOrder['drink']['name']
                          .toString()
                          .trim()
                          .isEmpty))) &&
          incomingMenuLabel != null) {
        singleMovedOrder['drink'] = {
          'name': incomingMenuLabel,
          'kotCategory': singleMovedOrder['drink']?['kotCategory'],
        };
      }

      singleMovedOrder['status'] = displayStatus;
      singleMovedOrder['amount'] = _parseAmount(
        singleMovedOrder['amount'],
        fallback: parsedAmount,
      );

      table['drinksOrders'][targetList] ??= <dynamic>[];
      (table['drinksOrders'][targetList] as List).add(singleMovedOrder);

      final drinksOrdersKeyToAmountKey = <String, String>{
        'pendingDrinksOrders': 'pendingDrinksAmount',
        'ongoingDrinksOrders': 'ongoingDrinksAmount',
        'completeDrinksOrders': 'completeDrinksAmount',
      };
      final String targetAmountKey =
          drinksOrdersKeyToAmountKey[targetList] ??
          targetList
              .replaceAll('DrinksOrders', 'DrinksAmount')
              .replaceAll('Orders', 'Amount');

      final double amtToAdd = _parseAmount(
        singleMovedOrder['amount'],
        fallback: parsedAmount,
      );
      table['orderAmounts'][targetAmountKey] =
          (table['orderAmounts'][targetAmountKey] ?? 0) + amtToAdd;
      table['orderAmounts']['totalAmount'] =
          (table['orderAmounts']['totalAmount'] ?? 0) + amtToAdd;

      print(
        '✅ Moved one unit of drink order $orderId into $targetList (₹${amtToAdd.toStringAsFixed(2)}). Removed from $fromStatusListKey if present.',
      );
    } else {
      bool existsAnywhere = false;
      for (String statusKey in [
        'pendingDrinksOrders',
        'ongoingDrinksOrders',
        'completeDrinksOrders',
      ]) {
        final orderList = (table['drinksOrders'][statusKey] as List<dynamic>);
        if (orderList.any(
          (o) =>
              o != null &&
              ((o['id']?.toString() == orderId) ||
                  (o['orderId']?.toString() == orderId)),
        )) {
          existsAnywhere = true;
          break;
        }
      }

      if (!existsAnywhere) {
        final label =
            incomingMenuLabel?.isNotEmpty == true
                ? incomingMenuLabel!
                : 'Drink #$orderId';
        final placeholderOrder = {
          'id': int.tryParse(orderId) ?? orderId,
          'orderId': orderId,
          'order_item_id': int.tryParse(orderId) ?? orderId,
          'quantity': 1,
          'amount': parsedAmount,
          'status': displayStatus,
          'drink': {'name': label, 'kotCategory': 'Unknown'},
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'isPlaceholder': true,
        };

        table['drinksOrders'][targetList] ??= <dynamic>[];
        (table['drinksOrders'][targetList] as List).add(placeholderOrder);

        final drinksOrdersKeyToAmountKey = <String, String>{
          'pendingDrinksOrders': 'pendingDrinksAmount',
          'ongoingDrinksOrders': 'ongoingDrinksAmount',
          'completeDrinksOrders': 'completeDrinksAmount',
        };
        final String amountKey =
            drinksOrdersKeyToAmountKey[targetList] ??
            targetList
                .replaceAll('DrinksOrders', 'DrinksAmount')
                .replaceAll('Orders', 'Amount');

        table['orderAmounts'][amountKey] =
            (table['orderAmounts'][amountKey] ?? 0) + parsedAmount;
        table['orderAmounts']['totalAmount'] =
            (table['orderAmounts']['totalAmount'] ?? 0) + parsedAmount;

        print(
          '⚠️ Placeholder created for drinks order $orderId in $targetList (label="$label", ₹${parsedAmount.toStringAsFixed(2)})',
        );
      } else {
        print(
          'ℹ️ Drinks order $orderId exists elsewhere; no placeholder created.',
        );
      }
    }
  }

  double _parseAmount(dynamic rawAmount, {double fallback = 0.0}) {
    if (rawAmount == null) return fallback;
    if (rawAmount is num) return rawAmount.toDouble();
    if (rawAmount is String) {
      final cleaned = rawAmount.replaceAll(RegExp(r'[^\d\.\-]'), '');
      final parsed = double.tryParse(cleaned);
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  int findTableIndexInSection(
    Map<String, dynamic> section,
    dynamic payloadTableValue,
  ) {
    final tables = List<dynamic>.from(section['tables'] ?? []);

    print(
      '🔍 Searching for table with payload value: $payloadTableValue in section: ${section['name']}',
    );

    // Debug: Print all table info for this section
    for (var i = 0; i < tables.length; i++) {
      final t = tables[i];
    }

    // 1) Direct ID match if payload is db id
    if (payloadTableValue is int) {
      final byId = tables.indexWhere(
        (t) => (t['id'] is int && t['id'] == payloadTableValue),
      );
      if (byId != -1) {
        print('✅ Found table by direct ID match at index: $byId');
        return byId;
      }
    } else {
      // sometimes payload might be string numeric
      final payloadAsInt = int.tryParse(payloadTableValue?.toString() ?? '');
      if (payloadAsInt != null) {
        final byId = tables.indexWhere(
          (t) => (t['id'] is int && t['id'] == payloadAsInt),
        );
        if (byId != -1) {
          print('✅ Found table by parsed ID match at index: $byId');
          return byId;
        }
      }
    }

    // 2) Try common numeric/name fields on table object
    for (var i = 0; i < tables.length; i++) {
      final t = tables[i];
      final candidates = [
        t['table_number'],
        t['number'],
        t['actual_table_number'],
        t['tableNo'],
        t['display_number'],
        t['name'], // sometimes "Table 1" etc.
      ];

      for (var cand in candidates) {
        if (cand == null) continue;

        // compare as ints first
        final candInt =
            cand is int ? cand : int.tryParse(cand.toString() ?? '');
        final payloadInt =
            payloadTableValue is int
                ? payloadTableValue
                : int.tryParse(payloadTableValue?.toString() ?? '');

        if (candInt != null && payloadInt != null && candInt == payloadInt) {
          print(
            '✅ Found table by numeric field match at index: $i (field: $cand = $payloadTableValue)',
          );
          return i;
        }

        // fallback string comparison (e.g., name contains "1")
        if (cand.toString() == payloadTableValue?.toString()) {
          print(
            '✅ Found table by string match at index: $i (field: $cand = $payloadTableValue)',
          );
          return i;
        }

        // handle "Table 1" style:
        final nameDigits = RegExp(
          r'\d+',
        ).firstMatch(cand.toString() ?? '')?.group(0);
        if (nameDigits != null &&
            payloadTableValue != null &&
            nameDigits == payloadTableValue.toString()) {
          print(
            '✅ Found table by extracted digits match at index: $i (extracted: $nameDigits = $payloadTableValue)',
          );
          return i;
        }
      }
    }

    // 3) IMPROVED FALLBACK: Use root table display order logic
    // Group splits by parent and gather roots (parents)
    final Map<int, List<dynamic>> splitsByParent = {};
    final List<dynamic> roots = [];

    for (var t in tables) {
      final parentId = t['parent_table_id'];
      if (parentId == null) {
        roots.add(t);
      } else {
        final pid =
            parentId is int
                ? parentId
                : int.tryParse(parentId?.toString() ?? '');
        if (pid == null)
          roots.add(t);
        else
          splitsByParent.putIfAbsent(pid, () => []).add(t);
      }
    }

    // Sort roots by id (stable)
    roots.sort((a, b) {
      final ai =
          a['id'] is int
              ? a['id'] as int
              : int.tryParse(a['id']?.toString() ?? '') ?? 0;
      final bi =
          b['id'] is int
              ? b['id'] as int
              : int.tryParse(b['id']?.toString() ?? '') ?? 0;
      return ai.compareTo(bi);
    });

    // Map root display numbers (1-based) to actual table index in original tables list
    final payloadAsInt = int.tryParse(payloadTableValue?.toString() ?? '');
    if (payloadAsInt != null &&
        payloadAsInt >= 1 &&
        payloadAsInt <= roots.length) {
      final targetRoot =
          roots[payloadAsInt - 1]; // Convert from 1-based to 0-based
      final targetRootId = targetRoot['id'] as int;
      final idx = tables.indexWhere(
        (t) => (t['id'] is int && t['id'] == targetRootId),
      );
      if (idx != -1) {
        print(
          '✅ Found table by root display order at index: $idx (display number: $payloadAsInt -> root id: $targetRootId)',
        );
        return idx;
      }
    }

    print('❌ Table not found with payload value: $payloadTableValue');
    return -1;
  }

  @override
  void dispose() {
    try {
      socket.off('auto_split_table_created');
      socket.off('bill_generated');
      socket.off('table_settle_up');
      socket.off('delete_table');
      print('✅ Cleaned up duplicate table socket listeners');
    } catch (e) {
      print('Error cleaning up socket listeners: $e');
    }
    socket.dispose();
    super.dispose();
    _sectionScrollController.dispose();
  }

  // Calculate seating time from timestamp
  double calculateSeatingTime(String? seatingTime) {
    if (seatingTime == null || seatingTime.isEmpty) return 0;

    DateTime startTime = DateTime.parse(seatingTime);
    Duration duration = DateTime.now().difference(startTime);
    return duration.inMinutes.toDouble();
  }

  // Format seating time for display
  String formatSeatingTime(double seatingTime) {
    int hours = seatingTime ~/ 60;
    int minutes = (seatingTime % 60).toInt();
    return '${hours}h ${minutes}m';
  }

  // Show Add Section Dialog
  void showAddSectionDialog() {
    TextEditingController sectionController = TextEditingController();

    ScaffoldMessengerState scaffoldMessenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add New Section'),
          backgroundColor: const Color.fromARGB(255, 235, 235, 229),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              TextField(
                controller: sectionController,
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: Color(0xFFFCFAF8),
                  border: OutlineInputBorder(),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.blue, width: 2),
                  ),
                  hintText: 'Section Name',
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final sectionName = sectionController.text.trim();

                if (sectionName.isNotEmpty) {
                  try {
                    final response = await http.post(
                      Uri.parse('${dotenv.env['API_URL']}/sections/'),
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode({
                        'name': sectionName,
                        'description': '',
                      }),
                    );

                    if (response.statusCode == 201 ||
                        response.statusCode == 200) {
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            'Section added successfully!',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                      fetchSections();
                      Navigator.pop(context);
                    } else {
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            'Failed to add section: ${response.body}',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  } catch (e) {
                    scaffoldMessenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          'Error occurred while adding section.',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                } else {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        'Please fill in all fields.',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      backgroundColor: Color(0xFFFE7070),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Color.fromARGB(255, 241, 79, 79),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    15,
                  ), // Set your desired radius here
                ),
              ),
              child: Text(
                'Add',
                style: GoogleFonts.poppins(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  void showEditSectionDialog(dynamic section) {
    TextEditingController sectionController = TextEditingController(
      text: section['name'],
    );

    ScaffoldMessengerState scaffoldMessenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Section'),
          backgroundColor: const Color.fromARGB(255, 235, 235, 229),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              TextField(
                controller: sectionController,
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: Color(0xFFFCFAF8),
                  border: OutlineInputBorder(),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.blue, width: 2),
                  ),
                  hintText: 'Section Name',
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final sectionName = sectionController.text.trim();

                if (sectionName.isNotEmpty) {
                  try {
                    final response = await http.put(
                      Uri.parse(
                        '${dotenv.env['API_URL']}/sections/${section['id']}',
                      ),
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode({'name': sectionName}),
                    );

                    if (response.statusCode == 200) {
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            'Section updated successfully!',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                      fetchSections();
                      Navigator.pop(context);
                    } else {
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            'Failed to update section: ${response.body}',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  } catch (e) {
                    scaffoldMessenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          'Error occurred while updating section.',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                } else {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        'Please fill in all fields.',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Color.fromARGB(255, 241, 79, 79),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    15,
                  ), // Set your desired radius here
                ),
              ),
              child: Text(
                'Update',
                style: GoogleFonts.poppins(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> showCustomerInfoDialog(
    BuildContext context,
    Map<String, dynamic> table,
  ) async {
    final TextEditingController customerNameController =
        TextEditingController();
    final TextEditingController customerPhoneController =
        TextEditingController();
    final TextEditingController discountController = TextEditingController();
    final TextEditingController serviceChargeController =
        TextEditingController();
    final TextEditingController vatController = TextEditingController();
    String selectedPaymentMethod = 'Cash';

    final List<String> paymentMethods = ['Cash', 'UPI', 'Card'];

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Color(0xFFF8F5F2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Center(
            child: Text(
              'Customer & Billing Info',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              children: [
                _buildTextField(
                  controller: customerNameController,
                  label: 'Customer Name',
                  icon: Icons.person,
                ),
                SizedBox(height: 15),
                _buildTextField(
                  controller: customerPhoneController,
                  label: 'Phone Number',
                  icon: Icons.phone,
                  keyboardType: TextInputType.phone,
                ),
                SizedBox(height: 15),
                _buildTextField(
                  controller: discountController,
                  label: 'Discount (%)',
                  icon: Icons.percent,
                  keyboardType: TextInputType.number,
                ),
                SizedBox(height: 15),
                _buildTextField(
                  controller: serviceChargeController,
                  label: 'Service Charge (%)',
                  icon: Icons.receipt_long,
                  keyboardType: TextInputType.number,
                ),

                SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  value: selectedPaymentMethod,
                  decoration: InputDecoration(
                    labelText: 'Payment Method',
                    labelStyle: GoogleFonts.poppins(
                      color: Colors.grey[800],
                    ), // Grey label
                    filled: true,
                    fillColor: Colors.white, // Light grey background
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: Icon(
                      Icons.payment,
                      color: Colors.grey,
                    ), // Grey icon
                  ),
                  dropdownColor: Colors.white, // Dropdown menu background color
                  iconEnabledColor: Colors.white, // Dropdown arrow icon color
                  style: GoogleFonts.poppins(
                    color: Colors.grey[800],
                  ), // Text style for selected item
                  items:
                      paymentMethods.map((method) {
                        return DropdownMenuItem(
                          value: method,
                          child: Text(
                            method,
                            style: GoogleFonts.poppins(color: Colors.grey[800]),
                          ), // Item text color
                        );
                      }).toList(),
                  onChanged: (value) {
                    if (value != null) selectedPaymentMethod = value;
                  },
                ),
              ],
            ),
          ),
          actionsPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          actions: [
            TextButton(
              child: Text(
                'Cancel',
                style: GoogleFonts.poppins(color: Colors.grey[700]),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.lightGreen,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text('Continue'),
              onPressed: () async {
                Navigator.pop(context); // Close the dialog

                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => GenerateBillPage(
                          table: table,
                          userName: userName, // Pass the userName here
                          customerName: '',
                          customerPhone: '',
                          discount: 0,
                          serviceCharge: 0,
                          vat: 0,
                          paymentMethod: 'Cash',
                          index: 1,
                          section: 'section',
                          userId: userId, // Pass the section here
                        ),
                  ),
                );

                // After returning from GenerateBillPage
                fetchSections(); // Call your refresh function here
              },
            ),
            SizedBox(height: 20),
          ],
        );
      },
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  void showEditTableDialog(dynamic table) {
    TextEditingController TableController = TextEditingController(
      text: table['seatingCapacity'].toString(),
    );
    ScaffoldMessengerState scaffoldMessenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Table Capacity'),
          backgroundColor: const Color.fromARGB(255, 235, 235, 229),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              TextField(
                controller: TableController,
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: Color(0xFFFCFAF8),
                  border: OutlineInputBorder(),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.blue, width: 2),
                  ),
                  hintText: 'Table Capacity',
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final tableCapacity = TableController.text.trim();

                if (tableCapacity.isNotEmpty) {
                  try {
                    final response = await http.put(
                      Uri.parse(
                        '${dotenv.env['API_URL']}/tables/${table['id']}',
                      ),
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode({'seatingCapacity': tableCapacity}),
                    );

                    if (response.statusCode == 200) {
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            'Table capacity updated successfully!',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                      fetchSections();
                      Navigator.pop(context);
                    } else {
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            'Failed to update table capacity: ${response.body}',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  } catch (e) {
                    scaffoldMessenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          'Error occurred while updating table capacity.',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                } else {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        'Please fill in all fields.',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Color.fromARGB(255, 241, 79, 79),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    15,
                  ), // Set your desired radius here
                ),
              ),
              child: Text(
                'Update',
                style: GoogleFonts.poppins(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  void showTransferTableDialog(dynamic table) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    List<dynamic> categories = [];
    List<dynamic> filteredTables = [];

    String? selectedCategoryId;
    dynamic selectedTable;

    /// 🔍 Find current section ID safely
    String getCurrentSectionId() {
      for (var cat in sections) {
        if ((cat['tables'] as List).any(
          (t) => t['id'].toString() == table['id'].toString(),
        )) {
          return cat['id'].toString();
        }
      }
      return "";
    }

    /// 🔍 Find current section name safely
    String getCurrentSectionName() {
      for (var cat in sections) {
        if ((cat['tables'] as List).any(
          (t) => t['id'].toString() == table['id'].toString(),
        )) {
          return cat['name'];
        }
      }
      return "";
    }

    /// 🔢 Sort tables by display number
    void sortTablesByNumber() {
      filteredTables.sort((a, b) {
        final aNum = int.tryParse(a['display_number']?.toString() ?? '') ?? 0;
        final bNum = int.tryParse(b['display_number']?.toString() ?? '') ?? 0;
        return aNum.compareTo(bNum);
      });
    }

    Future<void> fetchCategories() async {
      final response = await http.get(
        Uri.parse('${dotenv.env['API_URL']}/sections'),
      );

      if (response.statusCode == 200) {
        categories = jsonDecode(response.body);
      }
    }

    showDialog(
      context: context,
      builder: (context) {
        return FutureBuilder(
          future: fetchCategories(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const AlertDialog(
                content: Center(child: CircularProgressIndicator()),
              );
            }

            /// ✅ Auto-select current section
            selectedCategoryId ??= getCurrentSectionId();

            if (selectedCategoryId!.isNotEmpty && filteredTables.isEmpty) {
              final currentCat = categories.firstWhere(
                (c) => c['id'].toString() == selectedCategoryId,
                orElse: () => null,
              );

              if (currentCat != null) {
                filteredTables = List.from(currentCat['tables']);
                sortTablesByNumber(); // ✅ SORT ON INITIAL LOAD
              }
            }

            return StatefulBuilder(
              builder: (context, setState) {
                void filterTablesByCategory(String? categoryId) {
                  final category = categories.firstWhere(
                    (cat) => cat['id'].toString() == categoryId,
                    orElse: () => null,
                  );

                  if (category != null) {
                    filteredTables = List.from(category['tables']);
                    sortTablesByNumber(); // ✅ SORT ON SECTION CHANGE
                  } else {
                    filteredTables = [];
                  }
                }

                final currentSectionId = getCurrentSectionId();
                final currentSectionName = getCurrentSectionName();

                final selectedSectionName =
                    selectedCategoryId != null
                        ? categories.firstWhere(
                          (cat) => cat['id'].toString() == selectedCategoryId,
                        )['name']
                        : null;

                return AlertDialog(
                  title: const Text('Transfer Table'),
                  backgroundColor: const Color.fromARGB(255, 235, 235, 229),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      /// SECTION DROPDOWN
                      DropdownButtonFormField<String>(
                        value:
                            selectedCategoryId!.isEmpty
                                ? null
                                : selectedCategoryId,
                        decoration: InputDecoration(
                          labelText: "Select Section",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        items:
                            categories.map((cat) {
                              return DropdownMenuItem<String>(
                                value: cat['id'].toString(),
                                child: Text(cat['name']),
                              );
                            }).toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedCategoryId = value;
                            selectedTable = null;
                            filterTablesByCategory(value);
                          });
                        },
                      ),

                      const SizedBox(height: 10),

                      /// TABLE DROPDOWN
                      DropdownButtonFormField<dynamic>(
                        value: selectedTable,
                        decoration: InputDecoration(
                          labelText: "Select Table",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        items:
                            filteredTables.map((t) {
                              final isCurrent =
                                  t['id'].toString() == table['id'].toString();

                              final displayNum = t['display_number'] ?? 0;

                              return DropdownMenuItem<dynamic>(
                                value: isCurrent ? null : t,
                                enabled: !isCurrent,
                                child: Text(
                                  "Table $displayNum - ${t['status']}"
                                  "${isCurrent ? ' (Current)' : ''}",
                                  style: GoogleFonts.poppins(
                                    color:
                                        isCurrent ? Colors.grey : Colors.black,
                                  ),
                                ),
                              );
                            }).toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedTable = value;
                          });
                        },
                      ),

                      const SizedBox(height: 20),

                      if (selectedTable != null)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "$currentSectionName - Table ${table['display_number']}",
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Icon(Icons.arrow_forward),
                            Text(
                              " $selectedSectionName - Table ${selectedTable['display_number']}",
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),

                  /// ACTIONS
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color.fromARGB(
                          255,
                          237,
                          237,
                          107,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () async {
                        if (selectedTable == null) {
                          scaffoldMessenger.showSnackBar(
                            const SnackBar(
                              content: Text('Please select a table'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                          return;
                        }

                        try {
                          final response = await http.put(
                            Uri.parse(
                              '${dotenv.env['API_URL']}/tables/transfer',
                            ),
                            headers: {'Content-Type': 'application/json'},
                            body: jsonEncode({
                              'fromTableId': table['display_number'],
                              'toTableId': selectedTable['display_number'],
                              'fromSectionId': int.parse(currentSectionId),
                              'toSectionId': int.parse(selectedCategoryId!),
                            }),
                          );

                          if (response.statusCode == 200 ||
                              response.statusCode == 201) {
                            Navigator.of(context, rootNavigator: true).pop();
                            Navigator.of(context, rootNavigator: true).pop();
                            scaffoldMessenger.showSnackBar(
                              const SnackBar(
                                content: Text('Table transferred successfully'),
                                backgroundColor: Colors.green,
                              ),
                            );

                            await fetchSections();
                          } else {
                            scaffoldMessenger.showSnackBar(
                              const SnackBar(
                                content: Text('Transfer failed'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        } catch (e) {
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.swap_horiz, color: Colors.black),
                          SizedBox(width: 6),
                          Text(
                            'Transfer',
                            style: TextStyle(color: Colors.black),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  /// 🔧 Helper function to get table's index from original category list
  int getTableIndex(dynamic table, List<dynamic> categories) {
    for (var cat in categories) {
      List<dynamic> tables = cat['tables'];
      int index = tables.indexWhere((t) => t['id'] == table['id']);
      if (index != -1) return index;
    }
    return 0;
  }

  void showAddTableDialog() {
    TextEditingController tableController = TextEditingController();
    String? selectedSectionId;

    ScaffoldMessengerState scaffoldMessenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add New Table'),
          backgroundColor: const Color.fromARGB(255, 235, 235, 229),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),

              // Dropdown for selecting section
              DropdownButtonFormField<String>(
                value: selectedSectionId,
                onChanged: (value) {
                  setState(() {
                    selectedSectionId = value;
                  });
                },
                decoration: const InputDecoration(
                  labelText: 'Select Section',
                  filled: true,
                  fillColor: Color(0xFFFCFAF8),
                  border: OutlineInputBorder(),
                ),
                items:
                    sections.map<DropdownMenuItem<String>>((section) {
                      return DropdownMenuItem<String>(
                        value:
                            section['id']
                                .toString(), // assuming section has an 'id'
                        child: Text(
                          section['name'],
                        ), // assuming section has a 'name'
                      );
                    }).toList(),
              ),

              const SizedBox(height: 25),

              // Input field for table capacity
              TextField(
                controller: tableController,
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: Color(0xFFFCFAF8),
                  border: OutlineInputBorder(),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.blue, width: 2),
                  ),
                  hintText: 'Table Capacity',
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (tableController.text.isNotEmpty &&
                    selectedSectionId != null) {
                  try {
                    final response = await http.post(
                      Uri.parse(
                        '${dotenv.env['API_URL']}/tables/',
                      ), // replace with your actual base URL
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode({
                        'sectionId': selectedSectionId,
                        'seatingCapacity': int.parse(tableController.text),
                      }),
                    );

                    if (response.statusCode == 200 ||
                        response.statusCode == 201) {
                      scaffoldMessenger.showSnackBar(
                        const SnackBar(
                          content: Text('Table added successfully!'),
                        ),
                      );
                      Navigator.pop(context);
                      fetchSections(); // Refresh sections after adding new table
                    } else {
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            'Failed to add table: ${response.body}',
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
                    const SnackBar(content: Text('Please fill in all fields.')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Color.fromARGB(255, 241, 79, 79),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    15,
                  ), // Set your desired radius here
                ),
              ),
              child: Text(
                'Add',
                style: GoogleFonts.poppins(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  void showMergeTableDialog(dynamic table) {
    ScaffoldMessengerState scaffoldMessenger = ScaffoldMessenger.of(context);

    List<dynamic> categories = [];
    List<dynamic> filteredTables = [];
    String? selectedSectionId;
    dynamic selectedTable;

    // ✅ Get current section info dynamically
    String getCurrentSectionId() {
      for (var cat in sections) {
        if ((cat['tables'] as List).any(
          (t) => t['id'].toString() == table['id'].toString(),
        )) {
          return cat['id'].toString();
        }
      }
      return "";
    }

    String getCurrentSectionName() {
      for (var cat in sections) {
        if ((cat['tables'] as List).any(
          (t) => t['id'].toString() == table['id'].toString(),
        )) {
          return cat['name'];
        }
      }
      return "";
    }

    Future<void> fetchCategories() async {
      final categoryResponse = await http.get(
        Uri.parse('${dotenv.env['API_URL']}/sections'),
      );

      if (categoryResponse.statusCode == 200) {
        categories = jsonDecode(categoryResponse.body);
      }
    }

    showDialog(
      context: context,
      builder: (context) {
        return FutureBuilder(
          future: fetchCategories(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const AlertDialog(
                content: Center(child: CircularProgressIndicator()),
              );
            }

            return StatefulBuilder(
              builder: (context, setState) {
                // Filter tables by selected section
                void filterTablesBySection(String? sectionId) {
                  final section = categories.firstWhere(
                    (cat) => cat['id'].toString() == sectionId,
                    orElse: () => null,
                  );

                  if (section != null) {
                    filteredTables = List.from(section['tables'] as List)
                      ..sort((a, b) {
                        final aNum = a['display_number'] ?? 0;
                        final bNum = b['display_number'] ?? 0;
                        return aNum.compareTo(bNum);
                      });
                  } else {
                    filteredTables = [];
                  }
                }

                final currentSectionId = getCurrentSectionId();
                final currentSectionName = getCurrentSectionName();

                String? selectedSectionName =
                    selectedSectionId != null
                        ? categories.firstWhere(
                          (cat) => cat['id'].toString() == selectedSectionId,
                        )['name']
                        : null;

                return AlertDialog(
                  title: const Text('Merge Table'),
                  backgroundColor: const Color.fromARGB(255, 235, 235, 229),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Section dropdown
                      DropdownButtonFormField<String>(
                        value: selectedSectionId,
                        decoration: InputDecoration(
                          labelText: "Select Section",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        items:
                            categories.map<DropdownMenuItem<String>>((cat) {
                              return DropdownMenuItem<String>(
                                value: cat['id'].toString(),
                                child: Text(cat['name']),
                              );
                            }).toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedSectionId = value;
                            filterTablesBySection(value);
                            selectedTable = null;
                          });
                        },
                      ),
                      const SizedBox(height: 10),

                      // Table dropdown
                      DropdownButtonFormField<dynamic>(
                        value: selectedTable,
                        decoration: InputDecoration(
                          labelText: "Select Table to Merge With",
                          labelStyle: GoogleFonts.poppins(fontSize: 13),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        items:
                            filteredTables.map<DropdownMenuItem<dynamic>>((t) {
                              bool isCurrent =
                                  t['id'].toString() == table['id'].toString();
                              bool isMerged = t['status'] == 'merged';
                              bool isDisabled = isCurrent || isMerged;

                              final displayNum =
                                  t['display_number'] ??
                                  (filteredTables.indexOf(t) + 1);

                              return DropdownMenuItem<dynamic>(
                                value: isDisabled ? null : t,
                                enabled: !isDisabled,
                                child: Row(
                                  children: [
                                    Text(
                                      "Table $displayNum - ${t['status']}",
                                      style: GoogleFonts.poppins(
                                        color:
                                            isDisabled
                                                ? Colors.grey
                                                : Colors.black,
                                      ),
                                    ),
                                    if (isCurrent) const SizedBox(width: 8),
                                    if (isCurrent)
                                      Text(
                                        "(Current table)",
                                        style: GoogleFonts.poppins(
                                          color: Colors.grey,
                                          fontStyle: FontStyle.italic,
                                          fontSize: 12,
                                        ),
                                      ),
                                    if (isMerged && !isCurrent)
                                      const SizedBox(width: 8),
                                    if (isMerged && !isCurrent)
                                      Text(
                                        "(Already Merged)",
                                        style: GoogleFonts.poppins(
                                          color: Colors.grey,
                                          fontStyle: FontStyle.italic,
                                          fontSize: 12,
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            }).toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedTable = value;
                          });
                        },
                      ),
                      const SizedBox(height: 20),
                      if (selectedTable != null)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "$currentSectionName - Table ${table['display_number'] ?? table['id']}  ",
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Icon(Icons.add),
                            Text(
                              "  $selectedSectionName - Table ${selectedTable['display_number'] ?? selectedTable['id']}",
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        if (selectedTable != null &&
                            selectedSectionId != null) {
                          try {
                            final primaryTableId = table['id'];
                            final mergeTableId = selectedTable['id'];
                            print('✅ Sending merge request:');
                            print(
                              '  Primary: Section $currentSectionId, Display Number $primaryTableId',
                            );
                            print(
                              '  Merge: Section $selectedSectionId, Display Number $mergeTableId',
                            );

                            final response = await http.put(
                              Uri.parse(
                                '${dotenv.env['API_URL']}/tables/merge',
                              ),
                              headers: {'Content-Type': 'application/json'},
                              body: jsonEncode({
                                'primaryTableId': primaryTableId, // ✅ REAL ID
                                'mergingTableId': mergeTableId, // ✅ REAL ID
                              }),
                            );

                            if (response.statusCode == 200) {
                              scaffoldMessenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Tables merged successfully!',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  backgroundColor: Colors.green,
                                ),
                              );
                              fetchSections();
                              Navigator.pop(context);
                              Navigator.pop(context);
                            } else {
                              final errorBody = jsonDecode(response.body);
                              scaffoldMessenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Failed: ${errorBody['message'] ?? response.body}',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          } catch (e) {
                            scaffoldMessenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Error occurred while merging tables.',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        } else {
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                'Please select both section and table to merge with.',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color.fromARGB(
                          255,
                          151,
                          225,
                          217,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.combine, color: Colors.black),
                          const SizedBox(width: 5),
                          Text(
                            'Merge',
                            style: GoogleFonts.poppins(
                              color: Colors.black,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void showSplitTableDialog(dynamic table, String displayLabel) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final TextEditingController nameController = TextEditingController();
    final TextEditingController capacityController = TextEditingController(
      text: (table['seatingCapacity'] ?? 4).toString(),
    );
    bool isSubmitting = false;

    // Split by hyphen
    List<String> parts = displayLabel.split('-');

    // Get the last part and extract digits
    String number = RegExp(r'\d+').stringMatch(parts.last) ?? '';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Split Table', style: GoogleFonts.poppins()),
              backgroundColor: const Color.fromARGB(255, 235, 235, 229),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Info about current table

                    // Split name
                    TextFormField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Enter new table name',
                        hintText: 'e.g. ${number}A, B, .., etc.',
                        labelStyle: GoogleFonts.poppins(fontSize: 13),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Seating capacity
                    TextFormField(
                      controller: capacityController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Seating capacity',
                        labelStyle: GoogleFonts.poppins(fontSize: 13),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),
                    if (isSubmitting) const SizedBox(height: 12),
                    if (isSubmitting) const CircularProgressIndicator(),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(context),
                  child: Text('Cancel', style: GoogleFonts.poppins()),
                ),
                ElevatedButton(
                  onPressed:
                      isSubmitting
                          ? null
                          : () async {
                            final splitName = nameController.text.trim();
                            final capacityText = capacityController.text.trim();
                            final capacity = int.tryParse(capacityText);

                            // validations
                            if (splitName.isEmpty) {
                              scaffoldMessenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Please enter a split name',
                                    style: GoogleFonts.poppins(),
                                  ),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                              return;
                            }
                            if (capacity == null || capacity <= 0) {
                              scaffoldMessenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Please enter a valid seating capacity',
                                    style: GoogleFonts.poppins(),
                                  ),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                              return;
                            }

                            // only allow split when table is occupied (mirrors button guard)

                            // send request
                            setState(() => isSubmitting = true);
                            try {
                              final response = await http.post(
                                Uri.parse(
                                  '${dotenv.env['API_URL']}/tables/${table['id']}/split',
                                ),
                                headers: {'Content-Type': 'application/json'},
                                body: jsonEncode({
                                  'splitName': splitName,
                                  'seatingCapacity': capacity,
                                  // not transferring orders by default; omit orderIds/drinksOrderIds
                                }),
                              );

                              if (response.statusCode == 200 ||
                                  response.statusCode == 201) {
                                scaffoldMessenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Table split successfully',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                      ),
                                    ),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                                await fetchSections();
                                Navigator.pop(context);
                                Navigator.pop(context);
                              } else {
                                scaffoldMessenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Failed to split table: ${response.body}',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                      ),
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            } catch (e) {
                              scaffoldMessenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Error while splitting table: $e',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                    ),
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            } finally {
                              if (mounted) setState(() => isSubmitting = false);
                            }
                          },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 151, 225, 217),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.call_split, color: Colors.black),
                      const SizedBox(width: 6),
                      Text(
                        'Split',
                        style: GoogleFonts.poppins(color: Colors.black),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  bool _canGenerateBill(Map<String, dynamic> table) {
    // Ensure nested structures exist
    final orders = table['orders'] ?? {};
    final drinksOrders = table['drinksOrders'] ?? {};

    final pendingFood = (orders['pendingOrders'] as List?) ?? [];
    final ongoingFood = (orders['ongoingOrders'] as List?) ?? [];

    final pendingDrinks = (drinksOrders['pendingDrinksOrders'] as List?) ?? [];
    final ongoingDrinks = (drinksOrders['ongoingDrinksOrders'] as List?) ?? [];

    // If there are *any* non-completed orders → cannot generate bill
    if (pendingFood.isNotEmpty ||
        ongoingFood.isNotEmpty ||
        pendingDrinks.isNotEmpty ||
        ongoingDrinks.isNotEmpty) {
      return false;
    }

    // Otherwise, all are completed → can generate
    return true;
  }

  void showDemergeTableDialog(dynamic primaryTable) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    /// 1️⃣ Parse merged_with → DATABASE IDs ONLY (JSONB array)
    List<int> mergedDbIds = [];
    try {
      final mw = primaryTable['merged_with'];
      if (mw != null) {
        if (mw is int) {
          mergedDbIds = [mw];
        } else if (mw is String) {
          // Sometimes backend may send '[1]' as string
          final clean = mw.replaceAll(RegExp(r'[\[\]]'), '');
          mergedDbIds =
              clean
                  .split(',')
                  .map((s) => int.tryParse(s.trim()))
                  .whereType<int>()
                  .toList();
        } else if (mw is List) {
          mergedDbIds =
              mw
                  .map((e) => int.tryParse(e.toString()))
                  .whereType<int>()
                  .toList();
        }
      }
    } catch (_) {
      mergedDbIds = [];
    }

    if (mergedDbIds.isEmpty) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            'No merged tables found for this table.',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    Future<List<dynamic>> fetchSectionsAndTables() async {
      final resp = await http.get(
        Uri.parse('${dotenv.env['API_URL']}/sections'),
      );
      if (resp.statusCode != 200) {
        throw Exception('Failed to load sections');
      }
      return jsonDecode(resp.body) as List<dynamic>;
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        return FutureBuilder<List<dynamic>>(
          future: fetchSectionsAndTables(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const AlertDialog(
                content: SizedBox(
                  height: 80,
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }

            if (snapshot.hasError) {
              return AlertDialog(
                title: const Text('Error'),
                content: Text(
                  'Failed to load data: ${snapshot.error}',
                  style: GoogleFonts.poppins(),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Close'),
                  ),
                ],
              );
            }

            final categories = snapshot.data ?? [];

            /// 2️⃣ Build merged table info using DATABASE IDs
            final List<Map<String, dynamic>> mergedTableInfo = [];

            for (var cat in categories) {
              final tables = (cat['tables'] as List).cast<dynamic>();
              for (var t in tables) {
                final tableDbId = int.tryParse(t['id'].toString());
                if (tableDbId != null && mergedDbIds.contains(tableDbId)) {
                  mergedTableInfo.add({
                    'table': t,
                    'databaseId': tableDbId, // ✅ DB ID
                    'displayNumber': t['display_number'], // UI only
                    'sectionName': cat['name'],
                    'sectionId': cat['id'],
                  });
                }
              }
            }

            Map<String, dynamic>? selectedMergedInfo =
                mergedTableInfo.isNotEmpty ? mergedTableInfo.first : null;

            return StatefulBuilder(
              builder: (context, setState) {
                return AlertDialog(
                  title: const Text('Demerge Table'),
                  backgroundColor: const Color.fromARGB(255, 235, 235, 229),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (mergedTableInfo.length == 1)
                        Text(
                          'Demerge Table ${mergedTableInfo.first['displayNumber']} '
                          'from Table ${primaryTable['display_number']}?',
                          style: GoogleFonts.poppins(),
                        )
                      else
                        DropdownButtonFormField<Map<String, dynamic>>(
                          value: selectedMergedInfo,
                          decoration: InputDecoration(
                            labelText: "Select merged table to restore",
                            labelStyle: GoogleFonts.poppins(fontSize: 13),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          items:
                              mergedTableInfo.map((info) {
                                return DropdownMenuItem<Map<String, dynamic>>(
                                  value: info,
                                  child: Text(
                                    "${info['sectionName']} - Table ${info['displayNumber']}",
                                    style: GoogleFonts.poppins(),
                                  ),
                                );
                              }).toList(),
                          onChanged:
                              (v) => setState(() => selectedMergedInfo = v),
                        ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        final mergedInfo = selectedMergedInfo;
                        if (mergedInfo == null) return;

                        try {
                          /// 🔥 3️⃣ SEND DATABASE IDs — THIS FIXES YOUR BUG
                          final primaryTableId = primaryTable['id'];
                          final mergedTableId = mergedInfo['databaseId'];

                          

                          final response = await http.put(
                            Uri.parse(
                              '${dotenv.env['API_URL']}/tables/demerge',
                            ),
                            headers: {'Content-Type': 'application/json'},
                            body: jsonEncode({
                              'primaryTableId': primaryTableId,
                              'mergingTableId':
                                  mergedTableId, // ✅ MATCHES BACKEND
                            }),
                          );

                          if (response.statusCode == 200) {
                            scaffoldMessenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Table demerged successfully!',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                            fetchSections();
                            Navigator.pop(dialogContext);
                            Navigator.pop(dialogContext);
                          } else {
                            final errorBody = jsonDecode(response.body);
                            scaffoldMessenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  errorBody['message'] ??
                                      'Failed to demerge table',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                  ),
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        } catch (e) {
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                'Error occurred while demerging tables.',
                                style: GoogleFonts.poppins(color: Colors.white),
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color.fromARGB(
                          255,
                          255,
                          200,
                          100,
                        ),
                      ),
                      child: const Text(
                        'Demerge',
                        style: TextStyle(color: Colors.black),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  List<dynamic> _getFilteredTables(List<dynamic> tables) {
    if (_tableFilter == 'all') {
      return tables;
    }
    // 'running' filter - show only occupied, reserved, and settleUp tables
    return tables.where((table) {
      final status = (table['status'] ?? '').toString().toLowerCase();
      return status == 'occupied' ||
          status == 'reserved' ||
          status == 'settleup' ||
          (_computeTableTotal(table) > 0);
    }).toList();
  }

  // Compute total from actual order items (fallback to orderAmounts if needed)
  double _computeTableTotal(dynamic table) {
    if (table == null) return 0.0;

    double total = 0.0;

    try {
      /// ---------------- FOOD ----------------
      final orders = table['orders'] ?? {};
      for (final key in ['pendingOrders', 'ongoingOrders', 'completeOrders']) {
        final list = List<dynamic>.from(orders[key] ?? []);
        for (final o in list) {
          if (o == null) continue;

          // 1️⃣ menu.price present → authoritative pre-tax base; apply 5% GST
          if (o['menu']?['price'] is num) {
            final qty = _parseQuantity(o['quantity']);
            total += (o['menu']['price'] as num).toDouble() * qty * 1.05;
            continue;
          }

          // 2️⃣ Backend-calculated amount (with tax) — socket orders
          if (o['taxedAmount'] is num) {
            total += (o['taxedAmount'] as num).toDouble();
            continue;
          }

          // 3️⃣ Alternate backend amount
          if (o['taxedActualAmount'] is num) {
            total += (o['taxedActualAmount'] as num).toDouble();
            continue;
          }

          // 4️⃣ Explicit stored amount (API orders)
          if (o['amount'] != null) {
            total += _parseAmount(o['amount']);
            continue;
          }
        }
      }

      /// ---------------- DRINKS ----------------
      final drinks = table['drinksOrders'] ?? {};
      for (final key in [
        'pendingDrinksOrders',
        'ongoingDrinksOrders',
        'completeDrinksOrders',
      ]) {
        final list = List<dynamic>.from(drinks[key] ?? []);
        for (final o in list) {
          if (o == null) continue;

          // 1️⃣ Backend-calculated taxed amount
          if (o['taxedAmount'] is num) {
            total += (o['taxedAmount'] as num).toDouble();
            continue;
          }

          // 2️⃣ Alternate backend taxed amount
          if (o['taxedActualAmount'] is num) {
            total += (o['taxedActualAmount'] as num).toDouble();
            continue;
          }

          // 3️⃣ Explicit amount
          if (o['amount'] is num) {
            total += (o['amount'] as num).toDouble();
            continue;
          }

          // 4️⃣ Fallback → price × qty (+ VAT if needed)
          if (o['drink']?['price'] is num) {
            final qty = _parseQuantity(o['quantity']);
            final price = (o['drink']['price'] as num).toDouble();
            final applyVAT = o['drink']?['applyVAT'] == true;

            double line = price * qty;
            if (applyVAT) {
              line *= 1.10; // 10% VAT
            }

            total += line;
          }
        }
      }
    } catch (e) {
      // Absolute fallback — backend total
      try {
        total = _parseAmount(table['orderAmounts']?['totalAmount'] ?? 0);
      } catch (_) {
        total = 0.0;
      }
    }

    return total.roundToDouble();
  }

  bool _isManager() {
    return userRole == 'Admin' ||
        userRole == 'Restaurant Manager' ||
        userRole == 'Acting Restaurant Manager' ||
        userRole == 'Owner';
  }

  Widget _fullWidthButton({
    required String label,
    required IconData icon,
    required Color color,
    required double height,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.black),
        label: Text(label, style: GoogleFonts.poppins(fontSize: 12)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Widget _halfButton({
    required String label,
    required IconData icon,
    required Color color,
    required double height,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: height,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: Colors.black),
        label: Text(label, style: GoogleFonts.poppins(fontSize: 10.5)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  String _buildMergedLabel(List mergedTables) {
    return mergedTables
        .map((t) {
          final section = t['section_name'] ?? '';
          final tableNo = t['display_number'] ?? '';
          return '$section - $tableNo';
        })
        .join(', ');
  }

  // Build table card dynamically
  Widget buildTableCard(
    dynamic table,
    int index,
    String sectionName,
    int sectionId,
    String displayLabel,
    int totalAmountFromParam,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth >= 600;
    final bool isLargeScreen = screenWidth > 600;
    final double buttonHeight = isLargeScreen ? 48.0 : 40.0;

    double seatingTime = calculateSeatingTime(table['seatingTime']);

    // Prefer the precomputed param, fallback to computing from items
    num totalAmount = totalAmountFromParam ?? 0;
    if (totalAmount == 0) {
      try {
        totalAmount = _computeTableTotal(table).round();
      } catch (_) {
        totalAmount = 0;
      }
    }

    final bool statusAllowsGenerate =
        !(table['status'] == 'free' ||
            table['status'] == 'reserved' ||
            table['status'] == 'merged');

    final bool canGenerate =
        _canGenerateBill(table) && statusAllowsGenerate && totalAmount > 0;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade400, width: 0.9),
      ),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// ================= HEADER =================
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      displayLabel,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),

                    if (_isManager())
                      IconButton(
                        icon: const Icon(LucideIcons.edit, size: 18),
                        color: Colors.redAccent,
                        onPressed: () => showEditTableDialog(table),
                      ),

                    if (_isManager())
                      IconButton(
                        icon: const Icon(LucideIcons.trash2, size: 18),
                        color: Colors.redAccent,
                        onPressed: () => DeleteTableDialog(context, table),
                      ),

                    IconButton(
                      icon: const Icon(LucideIcons.qrCode, size: 18),
                      color: Colors.blueGrey,
                      onPressed: () {
                        final qrUrl =
                            'http://13.60.15.89/customer-form?tableCode=${table['id']}';
                        showDialog(
                          context: context,
                          builder:
                              (context) => AlertDialog(
                                backgroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                title: Text(
                                  'Table QR Code',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 220,
                                      height: 220,
                                      child: PrettyQrView.data(
                                        data: qrUrl,
                                        decoration: const PrettyQrDecoration(
                                          shape: PrettyQrSmoothSymbol(
                                            color: Colors.black,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      displayLabel,
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    // Text(
                                    //   qrUrl,
                                    //   style: GoogleFonts.poppins(
                                    //     fontSize: 10,
                                    //     color: Colors.grey[600],
                                    //   ),
                                    //   textAlign: TextAlign.center,
                                    // ),
                                  ],
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: Text(
                                      'Close',
                                      style: GoogleFonts.poppins(),
                                    ),
                                  ),
                                ],
                              ),
                        );
                      },
                    ),
                  ],
                ),
                buildStatusIndicator(table['status']),
              ],
            ),

            if (table['status'] == 'merged' &&
                table['merged_with_details'] is List &&
                table['merged_with_details'].isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Merged with Table: ${_buildMergedLabel(table['merged_with_details'])}',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF3F8D85),
                  ),
                ),
              ),

            const SizedBox(height: 8),

            /// ================= INFO =================
            Row(
              children: [
                const Icon(Icons.people, size: 14, color: Colors.brown),
                const SizedBox(width: 4),
                Text(
                  'Capacity: ${table['seatingCapacity']}',
                  style: GoogleFonts.poppins(fontSize: 10.5),
                ),
              ],
            ),

            const SizedBox(height: 6),

            Row(
              children: [
                const Icon(Icons.access_time, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  formatSeatingTime(seatingTime),
                  style: GoogleFonts.poppins(fontSize: 10.5),
                ),
              ],
            ),

            const SizedBox(height: 12),

            buildOrderTableWithTotal(context, table),

            const SizedBox(height: 16),

            /// ================= BUTTONS =================

            /// 1️⃣ Take Order (Full Width)
            if (table['status'] != 'merged')
              _fullWidthButton(
                label: 'Take Order',
                icon: Icons.restaurant_menu,
                color: Colors.lightGreen.shade200,
                height: buttonHeight,
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (_) => MenuScreen(
                            preSelectedSectionId: sectionId.toString(),
                            preSelectedSectionName: sectionName,
                            preSelectedTableId: table['id'],
                            preSelectedTable: table,
                            preSelectedRestaurantTableId: index + 1,
                          ),
                    ),
                  );
                  fetchSections();
                },
              ),

            if (table['status'] == 'merged')
              _fullWidthButton(
                label: 'Demerge Table',
                icon: LucideIcons.undo2,
                color: Colors.orange.shade200,
                height: buttonHeight,
                onTap: () {
                  showDemergeTableDialog(table);
                },
              ),

            const SizedBox(height: 10),

            /// 2️⃣ Merge | Transfer
            if (table['status'] == 'occupied')
              Row(
                children: [
                  Expanded(
                    child: _halfButton(
                      label: 'Merge Table',
                      icon: LucideIcons.combine,
                      color: Colors.teal.shade200,
                      height: buttonHeight,
                      onTap: () => showMergeTableDialog(table),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _halfButton(
                      label: 'Transfer Table',
                      icon: LucideIcons.arrowUpRightSquare,
                      color: Colors.yellow.shade300,
                      height: buttonHeight,
                      onTap: () => showTransferTableDialog(table),
                    ),
                  ),
                ],
              ),

            if (table['status'] == 'occupied') const SizedBox(height: 10),

            /// 3️⃣ Split | Check KOT (Desktop)
            if (table['status'] != 'merged')
              Row(
                children: [
                  Expanded(
                    child: _halfButton(
                      label: 'Split Table',
                      icon: LucideIcons.split,
                      color: Colors.purple.shade100,
                      height: buttonHeight,
                      onTap: () => showSplitTableDialog(table, displayLabel),
                    ),
                  ),
                  const SizedBox(width: 8),

                  if (isDesktop)
                    Expanded(
                      child: _halfButton(
                        label: 'Check KOT',
                        icon: LucideIcons.printer,
                        color: Colors.orange.shade200,
                        height: buttonHeight,
                        onTap:
                            () => _printCheckKOT(
                              context,
                              table,
                              index,
                              sectionName,
                            ),
                      ),
                    ),
                ],
              ),

            const SizedBox(height: 10),

            /// 4️⃣ Generate Bill (Desktop only)
            if (isDesktop && table['status'] != 'merged')
              Row(
                children: [
                  Expanded(
                    child: _fullWidthButton(
                      label: 'Generate Bill',
                      icon: LucideIcons.receipt,
                      color: Colors.blue.shade200,
                      height: buttonHeight,
                      onTap:
                          canGenerate
                              ? () {
                                () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (_) => GenerateBillPage(
                                            table: table,
                                            userName: userName,
                                            customerName: '',
                                            customerPhone: '',
                                            discount: 0,
                                            serviceCharge: 0,
                                            vat: 10,
                                            paymentMethod: 'Cash',
                                            index: index,
                                            section: sectionName,
                                            userId: userId,
                                          ),
                                    ),
                                  );
                                  fetchSections();
                                }();
                              }
                              : null,
                    ),
                  ),
                ],
              ),

            if (isDesktop && table['status'] != 'merged')
              const SizedBox(height: 10),

            /// 5️⃣ Close Split Button (only for free split tables with no orders)
            if (table['is_split'] == true &&
                table['parent_table_id'] != null &&
                (table['status'] == 'free' || totalAmount == 0))
              _fullWidthButton(
                label: 'Close Split Table',
                icon: LucideIcons.x,
                color: Colors.red.shade200,
                height: buttonHeight,
                onTap: () => _closeSplitTable(context, table, table['id']),
              ),

            if (table['is_split'] == true &&
                table['parent_table_id'] != null &&
                (table['status'] == 'free' || totalAmount == 0))
              const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Future<void> handleDeleteOrder({
    required BuildContext context,
    required Map item,
    required List orders,
    required int quantity,
    required double amountPerItem,
    required String newStatus,
    required String orderIdStr,
  }) async {
    int? qtyToDelete;

    if (quantity > 1) {
      qtyToDelete = await showSelectDeleteQuantityDialog(context, quantity);
      if (qtyToDelete == null) return;
    } else {
      qtyToDelete = 1;
    }

    final sendId = orderIdStr.isNotEmpty ? orderIdStr : null;
    if (sendId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to identify order id for deletion'),
        ),
      );
      return;
    }

    int? tableId;
    String? menuId;
    final orderStatus = newStatus.toLowerCase();

    for (var s in sections) {
      for (var t in (s['tables'] as List)) {
        if ((t['orders']?['pendingOrders'] ??
                t['orders']?['ongoingOrders'] ??
                t['orders']?['completeOrders']) ==
            orders) {
          tableId = t['id'];
          break;
        }
      }
      if (tableId != null) break;
    }

    menuId = (item['menuId'] ?? item['menu']?['id'])?.toString();

    final result = await deleteOrder(
      context,
      sendId,
      qtyToDelete,
      tableId: tableId,
      menuId: menuId,
      status: orderStatus,
    );

    if (result != true) return;

    setState(() {
      final idx = orders.indexWhere((raw) {
        if (raw is! Map) return false;
        final rawId = raw['id'] ?? raw['menuId'] ?? raw['menu']?['id'];
        return rawId?.toString() == sendId;
      });

      if (idx != -1) {
        final raw = orders[idx] as Map;
        final rawQty = (raw['quantity'] as num?)?.toInt() ?? 1;
        final rawAmt = (raw['amount'] as num?)?.toDouble() ?? 0.0;
        final perUnit = rawQty > 0 ? rawAmt / rawQty : 0.0;

        if (qtyToDelete! >= rawQty) {
          orders.removeAt(idx);
        } else {
          raw['quantity'] = rawQty - qtyToDelete;
          raw['amount'] = double.parse(
            (rawAmt - perUnit * qtyToDelete).toStringAsFixed(2),
          );
        }
      }

      final delta = amountPerItem * qtyToDelete!;
      for (var s in sections) {
        for (var t in (s['tables'] as List)) {
          if ((t['orders']?['pendingOrders'] ??
                  t['orders']?['ongoingOrders'] ??
                  t['orders']?['completeOrders']) ==
              orders) {
            t['orderAmounts']['totalAmount'] -= delta;
            break;
          }
        }
      }
    });

    if (Navigator.canPop(context)) Navigator.pop(context);
  }

  Widget buildOrderList(
    BuildContext context,
    String title,
    List orders,
    String new_status,
  ) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    bool canDeleteOrder(String status, String role) {
      final alwaysAllowedRoles = [
        'Owner',
        'Admin',
        'Restaurant Manager',
        'Acting Restaurant Manager',
        'Billing Team',
      ];
      final conditionalRoles = [
        'Restaurant Manager',
        'Billing Team',
        'Acting Restaurant Manager',
      ];
      if (alwaysAllowedRoles.contains(role)) return true;
      if (conditionalRoles.contains(role))
        return status.toLowerCase() != 'completed';
      return false;
    }

    String capitalize(String value) {
      if (value.isEmpty) return value;
      return value[0].toUpperCase() + value.substring(1).toLowerCase();
    }

    final aggregated = _aggregateList(orders, isDrink: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: isDesktop ? 16 : 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        if (isDesktop)
          Table(
            columnWidths: const {
              0: FlexColumnWidth(3),
              1: FlexColumnWidth(1.5),
              2: FlexColumnWidth(1.5),
              3: FlexColumnWidth(1.2),
              4: FlexColumnWidth(0.5), // Shift icon
              5: FlexColumnWidth(0.5), // Delete icon
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                children: [
                  _tableHeader("Item", isDesktop),
                  _tableHeader("Qty", isDesktop),
                  _tableHeader("Amount", isDesktop),
                  _tableHeader("Status", isDesktop),
                  const SizedBox(),
                  const SizedBox(),
                ],
              ),
              ...aggregated.map<TableRow>((item) {
                final menuName =
                    (item['item_desc'] ??
                            item['menu']?['name'] ??
                            'Unnamed Item')
                        .toString();
                final quantity = item['quantity'] as int;

                double getAmountPerItem(Map item) {
                  try {
                    // 1️⃣ Valid explicit per-item amount
                    final apiPerItem = item['amount_per_item'];
                    if (apiPerItem is num && apiPerItem > 0) {
                      return apiPerItem.toDouble();
                    }

                    // 2️⃣ From raw items (MOST RELIABLE)
                    if (item['rawItems'] is List &&
                        item['rawItems'].isNotEmpty) {
                      for (final r in item['rawItems']) {
                        if (r is Map) {
                          final raw = r['raw'];
                          if (raw is Map &&
                              raw['amount'] is num &&
                              raw['quantity'] is num &&
                              raw['quantity'] > 0) {
                            return (raw['amount'] / raw['quantity']).toDouble();
                          }
                        }
                      }
                    }

                    // 3️⃣ Fallback to aggregated total
                    final totalAmt = item['amount'];
                    final qty = item['quantity'];
                    if (totalAmt is num && qty is num && qty > 0) {
                      return (totalAmt / qty).toDouble();
                    }
                  } catch (e) {
                    debugPrint('getAmountPerItem error: $e');
                  }

                  return 0.0;
                }

                final amountPerItem = getAmountPerItem(item);
                final totalAmountForAgg = (amountPerItem * quantity);

                final statusRaw = (item['status']?.toString() ?? 'Unknown');
                String normalizedStatus;
                if ([
                  'ongoing',
                  'accepted',
                  'in_progress',
                ].contains(statusRaw.toLowerCase())) {
                  normalizedStatus = 'Accepted';
                } else if ([
                  'complete',
                  'completed',
                ].contains(statusRaw.toLowerCase())) {
                  normalizedStatus = 'Completed';
                } else if (statusRaw.toLowerCase() == 'pending') {
                  normalizedStatus = 'Pending';
                } else {
                  normalizedStatus = capitalize(statusRaw);
                }
                final status = normalizedStatus;

                final sendIdCandidate =
                    item['id'] ??
                    ((item['mergedOrderIds'] is List &&
                            (item['mergedOrderIds'] as List).isNotEmpty)
                        ? (item['mergedOrderIds'] as List)[0]
                        : null);
                final orderIdStr = sendIdCandidate?.toString() ?? '';

                final canDelete = canDeleteOrder(status, userRole);

                return TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        menuName,
                        style: GoogleFonts.poppins(
                          fontSize: isDesktop ? 13 : 12,
                        ),
                      ),
                    ),
                    Text(
                      "x$quantity",
                      style: GoogleFonts.poppins(fontSize: isDesktop ? 13 : 12),
                    ),
                    Text(
                      "₹${totalAmountForAgg.toStringAsFixed(2)}",
                      style: GoogleFonts.poppins(fontSize: isDesktop ? 13 : 12),
                    ),
                    Text(
                      new_status,
                      style: GoogleFonts.poppins(fontSize: isDesktop ? 13 : 12),
                    ),
                    // ✅ SHIFT ICON
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_outward_rounded,
                        size: 18,
                        color: Colors.blue,
                      ),
                      onPressed: () {
                        showShiftOrderDialog(context, item, 'food', orders);
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Shift Order',
                    ),
                    // DELETE ICON
                    canDelete
                        ? IconButton(
                          icon: const Icon(
                            Icons.delete,
                            color: Colors.red,
                            size: 18,
                          ),
                          onPressed: () async {
                            await handleDeleteOrder(
                              context: context,
                              item: item,
                              orders: orders,
                              quantity: quantity,
                              amountPerItem: amountPerItem,
                              newStatus: new_status,
                              orderIdStr: orderIdStr,
                            );
                          },

                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Delete Order',
                        )
                        : const Icon(Icons.lock, size: 18, color: Colors.grey),
                  ],
                );
              }).toList(),
            ],
          )
        else
          // Mobile view - add shift button
          ...aggregated.map<Widget>((item) {
            final menuName =
                (item['item_desc'] ?? item['menu']?['name'] ?? 'Unnamed Item')
                    .toString();
            final quantity = item['quantity'] as int;

            final sendIdCandidate =
                item['id'] ??
                ((item['mergedOrderIds'] is List &&
                        (item['mergedOrderIds'] as List).isNotEmpty)
                    ? (item['mergedOrderIds'] as List)[0]
                    : null);

            final orderIdStr = sendIdCandidate?.toString() ?? '';

            double getAmountPerItem(Map item) {
              try {
                if (item.containsKey('amount_per_item') &&
                    item['amount_per_item'] != null) {
                  return (item['amount_per_item'] as num).toDouble();
                }
                if (item['rawItems'] is List &&
                    (item['rawItems'] as List).isNotEmpty) {
                  final first = (item['rawItems'] as List)[0];
                  if (first is Map) {
                    if (first.containsKey('amount_per_item') &&
                        first['amount_per_item'] != null) {
                      return (first['amount_per_item'] as num).toDouble();
                    }
                    if (first['raw'] is Map &&
                        first['raw'].containsKey('amount_per_item') &&
                        first['raw']['amount_per_item'] != null) {
                      return (first['raw']['amount_per_item'] as num)
                          .toDouble();
                    }
                  }
                }
                if (item.containsKey('amount') && item['amount'] != null) {
                  final totalAmt = (item['amount'] as num).toDouble();
                  return (quantity > 0) ? (totalAmt / quantity) : 0.0;
                }
              } catch (e) {}
              return 0.0;
            }

            final amountPerItem = getAmountPerItem(item);
            final totalAmountForAggMobile = (amountPerItem * quantity);

            final statusRaw = (item['status']?.toString() ?? 'Unknown');
            String normalizedStatus;
            if ([
              'ongoing',
              'accepted',
              'in_progress',
            ].contains(statusRaw.toLowerCase())) {
              normalizedStatus = 'Accepted';
            } else if ([
              'complete',
              'completed',
            ].contains(statusRaw.toLowerCase())) {
              normalizedStatus = 'Completed';
            } else if (statusRaw.toLowerCase() == 'pending') {
              normalizedStatus = 'Pending';
            } else {
              normalizedStatus = capitalize(statusRaw);
            }
            final status = normalizedStatus;

            final canDelete = canDeleteOrder(status, userRole);

            return Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          "$menuName  x$quantity",
                          style: GoogleFonts.poppins(
                            fontSize: isDesktop ? 13 : 11,
                          ),
                        ),
                      ),
                      // ✅ SHIFT ICON FOR MOBILE
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_outward_rounded,
                          size: 16,
                          color: Colors.blue,
                        ),
                        onPressed: () {
                          showShiftOrderDialog(context, item, 'food', orders);
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Shift Order',
                      ),
                      if (canDelete)
                        IconButton(
                          icon: const Icon(
                            Icons.delete,
                            size: 16,
                            color: Colors.red,
                          ),
                          onPressed: () async {
                            int? qtyToDelete;
                            if (quantity > 1) {
                              qtyToDelete =
                                  await showSelectDeleteQuantityDialog(
                                    context,
                                    quantity,
                                  );
                              if (qtyToDelete == null) return;
                            } else {
                              qtyToDelete = 1;
                            }

                            final sendId =
                                orderIdStr.isNotEmpty ? orderIdStr : null;
                            if (sendId == null) {
                              debugPrint(
                                'deleteOrder: missing id for aggregated item; aborting',
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Unable to identify order id for deletion',
                                  ),
                                ),
                              );
                              return;
                            }

                            // Extract additional parameters from the current context
                            int? tableId;
                            String? menuId;
                            String? orderStatus = new_status.toLowerCase();

                            // Find the table ID from sections
                            for (var s in sections) {
                              for (var t in (s['tables'] as List)) {
                                if ((t['orders']?['pendingOrders'] ??
                                        t['orders']?['ongoingOrders'] ??
                                        t['orders']?['completeOrders']) ==
                                    orders) {
                                  tableId = t['id'];
                                  break;
                                }
                              }
                              if (tableId != null) break;
                            }

                            // Extract menuId from the item
                            menuId =
                                (item['menuId'] ?? item['menu']?['id'])
                                    ?.toString();

                            final result = await deleteOrder(
                              context,
                              sendId,
                              qtyToDelete,
                              tableId: tableId,
                              menuId: menuId,
                              status: orderStatus,
                            );

                            if (result == true) {
                              setState(() {
                                // best-effort: find raw row that contributed to this aggregation and decrement/remove it
                                final idx = orders.indexWhere((raw) {
                                  if (raw == null || raw is! Map) return false;
                                  final rawId =
                                      raw['id'] ??
                                      raw['menuId'] ??
                                      raw['menu']?['id'];
                                  if (rawId != null &&
                                      sendId == rawId.toString())
                                    return true;
                                  final rawName =
                                      (raw['menu']?['name'] ??
                                              raw['item_desc'] ??
                                              '')
                                          .toString()
                                          .trim();
                                  final aggName = menuName.trim();
                                  final rawKot =
                                      raw['kotNumber']?.toString() ??
                                      (raw['kotNumbers'] is List &&
                                              raw['kotNumbers'].isNotEmpty
                                          ? raw['kotNumbers'][0].toString()
                                          : '');
                                  final aggKot =
                                      (item['kotNumbers'] is List &&
                                              (item['kotNumbers'] as List)
                                                  .isNotEmpty)
                                          ? (item['kotNumbers'] as List)[0]
                                              .toString()
                                          : '';
                                  return rawName == aggName &&
                                      (rawKot == aggKot ||
                                          rawKot.isEmpty ||
                                          aggKot.isEmpty);
                                });

                                if (idx != -1) {
                                  final rawMap = orders[idx] as Map;
                                  final rawQty =
                                      (rawMap['quantity'] is num)
                                          ? (rawMap['quantity'] as num).toInt()
                                          : (int.tryParse(
                                                rawMap['quantity']
                                                        ?.toString() ??
                                                    '',
                                              ) ??
                                              1);
                                  final rawAmt =
                                      (rawMap['amount'] is num)
                                          ? (rawMap['amount'] as num).toDouble()
                                          : (double.tryParse(
                                                rawMap['amount']?.toString() ??
                                                    '',
                                              ) ??
                                              0.0);
                                  final perUnit =
                                      rawQty > 0 ? (rawAmt / rawQty) : 0.0;

                                  if (qtyToDelete! >= rawQty) {
                                    orders.removeAt(idx);
                                  } else {
                                    rawMap['quantity'] = rawQty - qtyToDelete;
                                    rawMap['amount'] = double.parse(
                                      (rawAmt - (perUnit * qtyToDelete))
                                          .toStringAsFixed(2),
                                    );
                                  }
                                }

                                // <<-- changed: compute delta using amountPerItem * qtyToDelete
                                final double delta =
                                    (amountPerItem * (qtyToDelete ?? 0));

                                for (var s in sections) {
                                  for (var t in (s['tables'] as List)) {
                                    if ((t['orders']?['pendingOrders'] ??
                                            t['orders']?['ongoingOrders'] ??
                                            t['orders']?['completeOrders']) ==
                                        orders) {
                                      t['orderAmounts'] ??= {
                                        'pendingAmount': 0,
                                        'ongoingAmount': 0,
                                        'completeAmount': 0,
                                        'pendingDrinksAmount': 0,
                                        'ongoingDrinksAmount': 0,
                                        'completeDrinksAmount': 0,
                                        'totalAmount': 0,
                                      };
                                      t['orderAmounts']['totalAmount'] =
                                          (t['orderAmounts']['totalAmount'] ??
                                              0) -
                                          delta;
                                      if (identical(
                                        t['orders']['pendingOrders'],
                                        orders,
                                      )) {
                                        t['orderAmounts']['pendingAmount'] =
                                            (t['orderAmounts']['pendingAmount'] ??
                                                0) -
                                            delta;
                                      } else if (identical(
                                        t['orders']['ongoingOrders'],
                                        orders,
                                      )) {
                                        t['orderAmounts']['ongoingAmount'] =
                                            (t['orderAmounts']['ongoingAmount'] ??
                                                0) -
                                            delta;
                                      } else if (identical(
                                        t['orders']['completeOrders'],
                                        orders,
                                      )) {
                                        t['orderAmounts']['completeAmount'] =
                                            (t['orderAmounts']['completeAmount'] ??
                                                0) -
                                            delta;
                                      }
                                      break;
                                    }
                                  }
                                }
                              });

                              if (Navigator.canPop(context))
                                Navigator.pop(context);
                            }
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Delete Order',
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "₹${totalAmountForAggMobile.toStringAsFixed(2)} - $new_status",
                    style: GoogleFonts.poppins(
                      fontSize: isDesktop ? 13 : 11,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 7),
                ],
              ),
            );
          }).toList(),
        const SizedBox(height: 10),
        _dottedDivider(),
        const SizedBox(height: 10),
      ],
    );
  }

  // FIXED: _aggregateList method that properly handles API-provided taxed amounts

  List<Map<String, dynamic>> _aggregateList(List? raw, {bool isDrink = false}) {
    if (raw == null || raw is! List) {
      print('⚠️ _aggregateList received null or non-list: $raw');
      return <Map<String, dynamic>>[];
    }

    final Map<String, Map<String, dynamic>> map = {};

    String normalizeStatus(String? status) {
      final s = (status ?? 'pending').toString().toLowerCase();
      if (['ongoing', 'accepted', 'in_progress'].contains(s)) return 'accepted';
      if (['complete', 'completed'].contains(s)) return 'completed';
      if (s == 'pending') return 'pending';
      return s;
    }

    String keyForItem(Map item) {
      final isCustom = item['is_custom'] == true;
      if (isCustom) {
        final note =
            (item['note'] ?? item['item_desc'] ?? '').toString().trim();
        final kot =
            (item['kotNumber'] ??
                    (item['kotNumbers'] is List && item['kotNumbers'].isNotEmpty
                        ? item['kotNumbers'][0]
                        : null) ??
                    '')
                .toString();
        return 'custom_${note}_kot_${kot}';
      }
      final id =
          item['menuId'] ??
          item['menu']?['id'] ??
          item['drinkId'] ??
          item['drink']?['id'];
      if (id != null) return 'id_${id.toString()}';
      final name =
          (item['menu']?['name'] ??
                  item['drink']?['name'] ??
                  item['item_desc'] ??
                  item['drinkName'] ??
                  item['friendlyName'] ??
                  '')
              .toString()
              .trim();
      final kot =
          (item['kotNumber'] ??
                  (item['kotNumbers'] is List && item['kotNumbers'].isNotEmpty
                      ? item['kotNumbers'][0]
                      : null) ??
                  '')
              .toString();
      return 'name_${name}_kot_${kot}';
    }

    for (var i = 0; i < raw.length; i++) {
      final rawIt = raw[i];
      if (rawIt == null || rawIt is! Map) {
        print('⚠️ Skipping null or non-map item at index $i');
        continue;
      }

      try {
        final item = Map<String, dynamic>.from(rawIt);
        final normalizedStatus = normalizeStatus(item['status']?.toString());

        int qty =
            (item['quantity'] is num)
                ? (item['quantity'] as num).toInt()
                : int.tryParse(item['quantity']?.toString() ?? '') ?? 1;

        // ✅ FIX: Priority order for getting the correct amount per item
        double amountPerItem = 0.0;

        // 1️⃣ FIRST: Check if API provided taxedAmount or taxedActualAmount
        if (item['taxedAmount'] is num && item['taxedAmount'] != 0) {
          amountPerItem = (item['taxedAmount'] as num).toDouble();
          print('✅ Using taxedAmount from API: $amountPerItem');
        } else if (item['taxedActualAmount'] is num &&
            item['taxedActualAmount'] != 0) {
          amountPerItem = (item['taxedActualAmount'] as num).toDouble();
          print('✅ Using taxedActualAmount from API: $amountPerItem');
        }
        // 2️⃣ SECOND: Check amount_per_item (but verify if it needs tax)
        else if (item['amount_per_item'] is num &&
            item['amount_per_item'] != 0) {
          final storedAmount = (item['amount_per_item'] as num).toDouble();

          // Check if this amount already includes tax by comparing with base price.
          // If no base price is available, treat as already-taxed (backend always
          // stores amount_per_item as the final taxed per-item value).
          bool taxAlreadyIncluded = true; // default: assume taxed
          if (!isDrink && item['menu']?['price'] is num) {
            final basePrice = (item['menu']['price'] as num).toDouble();
            final expectedWithTax = basePrice * 1.05;
            taxAlreadyIncluded =
                (storedAmount >= expectedWithTax * 0.99 &&
                    storedAmount <= expectedWithTax * 1.01);
          } else if (isDrink && item['drink']?['price'] is num) {
            final basePrice = (item['drink']['price'] as num).toDouble();
            final applyVAT =
                item['drink']?['applyVAT'] == true || item['is_custom'] == true;
            final expectedWithTax =
                applyVAT ? basePrice * 1.10 : basePrice * 1.05;
            taxAlreadyIncluded =
                (storedAmount >= expectedWithTax * 0.99 &&
                    storedAmount <= expectedWithTax * 1.01);
          }

          amountPerItem = storedAmount;
          if (!taxAlreadyIncluded) {
            // Apply tax only when we've confirmed via base price that it's missing
            if (!isDrink) {
              amountPerItem = storedAmount * 1.05;
              print('✅ Applied 5% GST to amount_per_item: $amountPerItem');
            } else {
              final applyVAT =
                  item['drink']?['applyVAT'] == true ||
                  item['is_custom'] == true;
              amountPerItem =
                  applyVAT ? storedAmount * 1.10 : storedAmount * 1.05;
              print('✅ Applied tax to drink amount_per_item: $amountPerItem');
            }
          } else {
            print('✅ Tax already included in amount_per_item: $amountPerItem');
          }
        }
        // 3️⃣ THIRD: Calculate from total amount
        else if (item['amount'] != null) {
          final parsedAmount =
              (item['amount'] is num)
                  ? (item['amount'] as num).toDouble()
                  : double.tryParse(item['amount'].toString());

          if (parsedAmount != null && parsedAmount > 0) {
            amountPerItem = qty > 0 ? parsedAmount / qty : 0.0;
            print('✅ Calculated from total amount: $amountPerItem');
          }
        }
        // 4️⃣ LAST: Calculate from base price with tax
        else {
          if (!isDrink && item['menu']?['price'] is num) {
            final basePrice = (item['menu']['price'] as num).toDouble();
            amountPerItem =
                double.parse(
                  (basePrice * 1.05).toStringAsFixed(2),
                ).roundToDouble();
            print('✅ Calculated from menu price with GST: $amountPerItem');
          } else if (isDrink && item['drink']?['price'] is num) {
            final basePrice = (item['drink']['price'] as num).toDouble();
            final applyVAT =
                item['drink']?['applyVAT'] == true || item['is_custom'] == true;
            amountPerItem =
                applyVAT
                    ? double.parse(
                      (basePrice * 1.10).toStringAsFixed(2),
                    ).roundToDouble()
                    : double.parse(
                      (basePrice * 1.05).toStringAsFixed(2),
                    ).roundToDouble();
            print('✅ Calculated from drink price with tax: $amountPerItem');
          }
        }

        final totalAmount = (amountPerItem * qty).roundToDouble();

        final key = keyForItem(item);
        final isCustom = item['is_custom'] == true;

        if (!map.containsKey(key)) {
          String displayName = '';
          if (isCustom) {
            displayName =
                (item['note'] ?? item['item_desc'] ?? '').toString().trim();
            if (displayName.isEmpty &&
                isDrink &&
                item['drink'] is Map<String, dynamic>) {
              final drink = item['drink'] as Map<String, dynamic>;
              displayName =
                  (drink['name'] ?? drink['friendlyName'] ?? '')
                      .toString()
                      .trim();
            }
            if (displayName.isEmpty)
              displayName = isDrink ? 'Custom Drink' : 'Custom Item';
          } else {
            displayName =
                item['item_desc'] ??
                item['menu']?['name'] ??
                item['drink']?['name'] ??
                'Unnamed ${isDrink ? "Drink" : "Item"}';
          }

          var itemId = item['id'];
          int? parsedId;
          if (itemId is int) {
            parsedId = itemId;
          } else if (itemId != null) {
            parsedId = int.tryParse(itemId.toString());
          }

          List<dynamic> mergedIds = [];
          if (item['mergedOrderIds'] is List) {
            mergedIds = List.from(item['mergedOrderIds']);
          } else if (parsedId != null) {
            mergedIds = [parsedId];
          }

          List<dynamic> kotNums = [];
          if (item['kotNumbers'] is List) {
            kotNums = List.from(item['kotNumbers']);
          } else if (item['kotNumber'] != null) {
            kotNums = [item['kotNumber']];
          }

          map[key] = {
            'id': parsedId,
            'menuId': item['menuId'] ?? item['menu']?['id'],
            'drinkId': item['drinkId'] ?? item['drink']?['id'],
            'item_desc': displayName,
            'drinkName': isDrink ? displayName : null,
            'quantity': qty,
            'amount': totalAmount,
            'status': normalizedStatus,
            'menu': item['menu'],
            'drink': item['drink'],
            'is_custom': isCustom,
            'note': item['note'],
            'amount_per_item': amountPerItem.roundToDouble(),
            'mergedOrderIds': mergedIds,
            'kotNumbers': kotNums,
            'rawItems': [item],
          };

          print(
            '✅ Created aggregated item: key=$key, id=$parsedId, amountPerItem=$amountPerItem',
          );
        } else {
          final e = map[key]!;
          e['quantity'] = (e['quantity'] as int) + qty;
          e['amount'] = ((e['amount'] as double) + totalAmount).roundToDouble();

          // Keep the same amount_per_item (don't recalculate)

          final currentStatus = e['status']?.toString() ?? 'pending';
          if (normalizedStatus == 'completed' && currentStatus != 'completed')
            e['status'] = 'completed';
          else if (normalizedStatus == 'accepted' && currentStatus == 'pending')
            e['status'] = 'accepted';

          var itemId = item['id'];
          if (itemId != null) {
            int? parsedId;
            if (itemId is int) {
              parsedId = itemId;
            } else {
              parsedId = int.tryParse(itemId.toString());
            }
            if (parsedId != null) {
              (e['mergedOrderIds'] as List).add(parsedId);
            }
          }

          if (item['mergedOrderIds'] is List) {
            (e['mergedOrderIds'] as List).addAll(item['mergedOrderIds']);
          }

          if (item['kotNumbers'] is List)
            (e['kotNumbers'] as List).addAll(item['kotNumbers']);
          else if (item['kotNumber'] != null)
            (e['kotNumbers'] as List).add(item['kotNumber']);

          (e['rawItems'] as List).add(item);

          e['mergedOrderIds'] =
              (e['mergedOrderIds'] as List)
                  .where((x) => x != null)
                  .toSet()
                  .toList();
          e['kotNumbers'] =
              (e['kotNumbers'] as List)
                  .where((x) => x != null)
                  .toSet()
                  .toList();

          print(
            '✅ Merged into existing: key=$key, total mergedIds=${e['mergedOrderIds']}',
          );
        }
      } catch (e, stack) {
        print('❌ Error processing item at index $i: $e');
        print('Stack: $stack');
        print('Item: $rawIt');
        continue;
      }
    }

    final result =
        map.values.map((e) {
          final qty =
              (e['quantity'] is num)
                  ? (e['quantity'] as num).toInt()
                  : int.tryParse(e['quantity']?.toString() ?? '') ?? 0;

          final storedTotal =
              (e['amount'] is num)
                  ? (e['amount'] as num).toDouble()
                  : double.tryParse(e['amount']?.toString() ?? '') ?? 0.0;

          final storedPerItem =
              (e['amount_per_item'] is num)
                  ? (e['amount_per_item'] as num).toDouble()
                  : 0.0;

          // ✅ derive per-item ONLY if missing
          final safePerItem =
              (storedPerItem > 0 && qty > 0)
                  ? storedPerItem
                  : (qty > 0 ? storedTotal / qty : 0.0);

          final finalItem = {
            ...e,
            'quantity': qty,
            'amount_per_item': safePerItem.roundToDouble(),
            'amount': storedTotal.roundToDouble(), // ✅ PRESERVE API TOTAL
          };

          print(
            '📦 Final aggregated item: id=${finalItem['id']}, qty=$qty, total=${finalItem['amount']}',
          );

          return finalItem;
        }).toList();

    print('✅ Aggregation complete: ${result.length} items');
    return result;
  }

  void testOrderAggregation() {
    print('\n========== TESTING ORDER AGGREGATION ==========');

    // Sample test data
    final testOrders = [
      {
        'id': 101,
        'quantity': 2,
        'amount': 200.0,
        'status': 'pending',
        'menu': {'id': 1, 'name': 'Butter Chicken', 'price': 100.0},
        'item_desc': 'Butter Chicken',
        'is_custom': false,
      },
      {
        'id': 102,
        'quantity': 1,
        'amount': 100.0,
        'status': 'pending',
        'menu': {'id': 1, 'name': 'Butter Chicken', 'price': 100.0},
        'item_desc': 'Butter Chicken',
        'is_custom': false,
      },
    ];

    final aggregated = _aggregateList(testOrders, isDrink: false);

    print('Result: ${aggregated.length} aggregated items');
    for (var item in aggregated) {
      print(
        '  - ${item['item_desc']}: qty=${item['quantity']}, ids=${item['mergedOrderIds']}',
      );
    }

    print('==============================================\n');
  }

  Future<int?> showSelectDeleteQuantityDialog(
    BuildContext context,
    int maxQuantity,
  ) {
    return showDialog<int>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        int selected = 1;
        return StatefulBuilder(
          builder:
              (context, setState) => AlertDialog(
                title: const Text('Select quantity to delete'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Choose how many units of this item you want to delete:',
                    ),
                    const SizedBox(height: 12),
                    // Simple Dropdown from 1..maxQuantity
                    DropdownButton<int>(
                      value: selected,
                      isExpanded: true,
                      items: List.generate(
                        maxQuantity,
                        (i) => DropdownMenuItem<int>(
                          value: i + 1,
                          child: Text('${i + 1}'),
                        ),
                      ),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => selected = v);
                      },
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, null),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, selected),
                    child: Text('Delete $selected'),
                  ),
                ],
              ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------
  // 🔹 buildDrinksOrderList (full UI code)
  // ---------------------------------------------------------------------

  Widget buildDrinksOrderList(
    BuildContext context,
    String title,
    List drinksOrders,
    String new_status,
  ) {
    print("\n\ndrinksOrders: $drinksOrders\n\n");
    final isDesktop = MediaQuery.of(context).size.width >= 800;
    final aggregated = _aggregateList(drinksOrders, isDrink: true);

    String capitalize(String value) =>
        value.isEmpty
            ? value
            : value[0].toUpperCase() + value.substring(1).toLowerCase();

    bool canDeleteOrder(String status, String role) {
      final alwaysAllowed = [
        'Owner',
        'Admin',
        'Restaurant Manager',
        'Acting Restaurant Manager',
        'Billing Team',
      ];
      if (alwaysAllowed.contains(role)) return true;
      return role == 'Manager' && status.toLowerCase() != 'completed';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: isDesktop ? 16 : 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        if (isDesktop)
          Table(
            columnWidths: const {
              0: FlexColumnWidth(3),
              1: FlexColumnWidth(1.5),
              2: FlexColumnWidth(1.5),
              3: FlexColumnWidth(1.2),
              4: FlexColumnWidth(0.5), // ✅ Shift icon column
              5: FlexColumnWidth(0.5), // Delete icon column
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                children: [
                  _tableHeader("Drink", isDesktop),
                  _tableHeader("Qty", isDesktop),
                  _tableHeader("Amount", isDesktop),
                  _tableHeader("Status", isDesktop),
                  const SizedBox(), // Shift icon header
                  const SizedBox(), // Delete icon header
                ],
              ),
              ...aggregated.map<TableRow>((item) {
                final menuName =
                    (item['item_desc'] ??
                            item['drink']?['name'] ??
                            'Unnamed Drink')
                        .toString();
                final quantity = item['quantity'] as int;

                // compute per-drink amount
                double getAmountPerItem(Map item) {
                  try {
                    // 1️⃣ Direct field (flat data)
                    if (item['amount_per_item'] != null) {
                      return (item['amount_per_item'] as num).toDouble();
                    }

                    // 2️⃣ Nested inside "raw" object (common in your backend data)
                    if (item['raw'] is Map &&
                        item['raw']['amount_per_item'] != null) {
                      return (item['raw']['amount_per_item'] as num).toDouble();
                    }

                    // 3️⃣ Fallback: compute per-item from total amount ÷ quantity
                    if (item['amount'] != null && quantity > 0) {
                      return (item['amount'] as num).toDouble() / quantity;
                    }
                  } catch (e) {
                    print('⚠️ Error computing amount_per_item: $e');
                  }
                  return 0.0;
                }

                final amountPerItem = getAmountPerItem(item);
                final totalAmount = (amountPerItem * quantity);

                String statusRaw = (item['status']?.toString() ?? 'Unknown');
                String status;
                if ([
                  'ongoing',
                  'accepted',
                  'in_progress',
                ].contains(statusRaw.toLowerCase()))
                  status = 'Accepted';
                else if ([
                  'complete',
                  'completed',
                ].contains(statusRaw.toLowerCase()))
                  status = 'Completed';
                else if (statusRaw.toLowerCase() == 'pending')
                  status = 'Pending';
                else
                  status = capitalize(statusRaw);

                final canDelete = canDeleteOrder(status, userRole);

                final sendIdCandidate =
                    item['id'] ??
                    ((item['mergedOrderIds'] is List &&
                            (item['mergedOrderIds'] as List).isNotEmpty)
                        ? (item['mergedOrderIds'] as List)[0]
                        : null);
                final orderIdStr = sendIdCandidate?.toString() ?? '';

                return TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        menuName,
                        style: GoogleFonts.poppins(fontSize: 13),
                      ),
                    ),
                    Text(
                      "x$quantity",
                      style: GoogleFonts.poppins(fontSize: 13),
                    ),
                    Text(
                      "₹${totalAmount.toStringAsFixed(2)}",
                      style: GoogleFonts.poppins(fontSize: 13),
                    ),
                    Text(new_status, style: GoogleFonts.poppins(fontSize: 13)),

                    // ✅ SHIFT ICON FOR DRINKS
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_outward_rounded,
                        size: 18,
                        color: Colors.blue,
                      ),
                      onPressed: () {
                        showShiftOrderDialog(
                          context,
                          item,
                          'drink', // ✅ Changed from 'food' to 'drink'
                          drinksOrders,
                        );
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Shift Drink Order',
                    ),

                    // DELETE ICON
                    canDelete
                        ? IconButton(
                          icon: const Icon(
                            Icons.delete,
                            color: Colors.red,
                            size: 18,
                          ),
                          onPressed: () async {
                            int? qtyToDelete;
                            if (quantity > 1) {
                              qtyToDelete =
                                  await showSelectDeleteQuantityDialog(
                                    context,
                                    quantity,
                                  );
                              if (qtyToDelete == null) return;
                            } else {
                              qtyToDelete = 1;
                            }

                            final sendId =
                                orderIdStr.isNotEmpty ? orderIdStr : null;
                            if (sendId == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Unable to identify drink order for deletion',
                                  ),
                                ),
                              );
                              return;
                            }

                            int? tableId;
                            String? drinkId =
                                (item['drinkId'] ?? item['drink']?['id'])
                                    ?.toString();
                            String? orderStatus = new_status.toLowerCase();

                            // locate the tableId by matching drinksOrders reference
                            for (var s in sections) {
                              for (var t in (s['tables'] as List)) {
                                if ((t['drinksOrders']?['pendingDrinksOrders'] ??
                                        t['drinksOrders']?['ongoingDrinksOrders'] ??
                                        t['drinksOrders']?['completeDrinksOrders']) ==
                                    drinksOrders) {
                                  tableId = t['id'];
                                  break;
                                }
                              }
                              if (tableId != null) break;
                            }

                            final result = await deleteDrinksOrder(
                              context,
                              sendId,
                              qtyToDelete!,
                              tableId: tableId,
                              drinkId: drinkId,
                              status: orderStatus,
                            );

                            if (result == true) {
                              setState(() {
                                // update local list after deletion
                                final idx = drinksOrders.indexWhere((raw) {
                                  if (raw == null || raw is! Map) return false;
                                  final rawId =
                                      raw['id'] ??
                                      raw['drinkId'] ??
                                      raw['drink']?['id'];
                                  return rawId?.toString() == sendId;
                                });

                                final int deleteQty = qtyToDelete ?? 1;

                                if (idx != -1) {
                                  final raw = drinksOrders[idx] as Map;
                                  final int rawQty =
                                      (raw['quantity'] is num)
                                          ? (raw['quantity'] as num).toInt()
                                          : 1;
                                  final double rawAmt =
                                      (raw['amount'] is num)
                                          ? (raw['amount'] as num).toDouble()
                                          : 0.0;
                                  final double perUnit =
                                      rawQty > 0 ? rawAmt / rawQty : 0.0;

                                  if (deleteQty >= rawQty) {
                                    drinksOrders.removeAt(idx);
                                  } else {
                                    raw['quantity'] = rawQty - deleteQty;
                                    raw['amount'] = double.parse(
                                      (rawAmt - (perUnit * deleteQty))
                                          .toStringAsFixed(2),
                                    );
                                  }
                                }

                                // adjust totals
                                final double delta = amountPerItem * deleteQty;
                                for (var s in sections) {
                                  for (var t in (s['tables'] as List)) {
                                    if ((t['drinksOrders']?['pendingDrinksOrders'] ??
                                            t['drinksOrders']?['ongoingDrinksOrders'] ??
                                            t['drinksOrders']?['completeDrinksOrders']) ==
                                        drinksOrders) {
                                      t['orderAmounts'] ??= {
                                        'pendingDrinksAmount': 0,
                                        'ongoingDrinksAmount': 0,
                                        'completeDrinksAmount': 0,
                                        'totalAmount': 0,
                                      };
                                      t['orderAmounts']['totalAmount'] =
                                          (t['orderAmounts']['totalAmount'] ??
                                              0) -
                                          delta;

                                      if (identical(
                                        t['drinksOrders']['pendingDrinksOrders'],
                                        drinksOrders,
                                      )) {
                                        t['orderAmounts']['pendingDrinksAmount'] =
                                            (t['orderAmounts']['pendingDrinksAmount'] ??
                                                0) -
                                            delta;
                                      } else if (identical(
                                        t['drinksOrders']['ongoingDrinksOrders'],
                                        drinksOrders,
                                      )) {
                                        t['orderAmounts']['ongoingDrinksAmount'] =
                                            (t['orderAmounts']['ongoingDrinksAmount'] ??
                                                0) -
                                            delta;
                                      } else if (identical(
                                        t['drinksOrders']['completeDrinksOrders'],
                                        drinksOrders,
                                      )) {
                                        t['orderAmounts']['completeDrinksAmount'] =
                                            (t['orderAmounts']['completeDrinksAmount'] ??
                                                0) -
                                            delta;
                                      }
                                      break;
                                    }
                                  }
                                }
                              });
                            }
                          },
                        )
                        : const Icon(Icons.lock, color: Colors.grey, size: 18),
                  ],
                );
              }).toList(),
            ],
          )
        else
          // ✅ MOBILE VIEW WITH SHIFT ICON
          ...aggregated.map<Widget>((item) {
            final menuName =
                (item['item_desc'] ?? item['drink']?['name'] ?? 'Unnamed Drink')
                    .toString();
            final quantity = item['quantity'] as int;

            double getAmountPerItem(Map item) {
              try {
                if (item['amount_per_item'] != null) {
                  return (item['amount_per_item'] as num).toDouble();
                }
                if (item['raw'] is Map &&
                    item['raw']['amount_per_item'] != null) {
                  return (item['raw']['amount_per_item'] as num).toDouble();
                }
                if (item['amount'] != null && quantity > 0) {
                  return (item['amount'] as num).toDouble() / quantity;
                }
              } catch (e) {}
              return 0.0;
            }

            final amountPerItem = getAmountPerItem(item);
            final amount = (amountPerItem * quantity);

            final statusRaw = (item['status']?.toString() ?? 'Unknown');
            String status;
            if ([
              'ongoing',
              'accepted',
              'in_progress',
            ].contains(statusRaw.toLowerCase()))
              status = 'Accepted';
            else if ([
              'complete',
              'completed',
            ].contains(statusRaw.toLowerCase()))
              status = 'Completed';
            else if (statusRaw.toLowerCase() == 'pending')
              status = 'Pending';
            else
              status = capitalize(statusRaw);

            final canDelete = canDeleteOrder(status, userRole);

            final sendIdCandidate =
                item['id'] ??
                ((item['mergedOrderIds'] is List &&
                        (item['mergedOrderIds'] as List).isNotEmpty)
                    ? (item['mergedOrderIds'] as List)[0]
                    : null);
            final orderIdStr = sendIdCandidate?.toString() ?? '';

            return Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          "$menuName  x$quantity",
                          style: GoogleFonts.poppins(fontSize: 12),
                        ),
                      ),

                      // ✅ SHIFT ICON FOR MOBILE DRINKS
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_outward_rounded,
                          size: 16,
                          color: Colors.blue,
                        ),
                        onPressed: () {
                          showShiftOrderDialog(
                            context,
                            item,
                            'drink', // ✅ Changed from 'food' to 'drink'
                            drinksOrders,
                          );
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Shift Drink Order',
                      ),

                      // DELETE ICON
                      if (canDelete)
                        IconButton(
                          icon: const Icon(
                            Icons.delete,
                            size: 16,
                            color: Colors.red,
                          ),
                          onPressed: () async {
                            int? qtyToDelete;
                            if (quantity > 1) {
                              qtyToDelete =
                                  await showSelectDeleteQuantityDialog(
                                    context,
                                    quantity,
                                  );
                              if (qtyToDelete == null) return;
                            } else {
                              qtyToDelete = 1;
                            }

                            final sendId =
                                orderIdStr.isNotEmpty ? orderIdStr : null;
                            if (sendId == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Unable to identify drink order for deletion',
                                  ),
                                ),
                              );
                              return;
                            }

                            int? tableId;
                            String? drinkId =
                                (item['drinkId'] ?? item['drink']?['id'])
                                    ?.toString();
                            String? orderStatus = new_status.toLowerCase();

                            for (var s in sections) {
                              for (var t in (s['tables'] as List)) {
                                if ((t['drinksOrders']?['pendingDrinksOrders'] ??
                                        t['drinksOrders']?['ongoingDrinksOrders'] ??
                                        t['drinksOrders']?['completeDrinksOrders']) ==
                                    drinksOrders) {
                                  tableId = t['id'];
                                  break;
                                }
                              }
                              if (tableId != null) break;
                            }

                            final result = await deleteDrinksOrder(
                              context,
                              sendId,
                              qtyToDelete!,
                              tableId: tableId,
                              drinkId: drinkId,
                              status: orderStatus,
                            );

                            if (result == true) {
                              setState(() {
                                final idx = drinksOrders.indexWhere((raw) {
                                  if (raw == null || raw is! Map) return false;
                                  final rawId =
                                      raw['id'] ??
                                      raw['drinkId'] ??
                                      raw['drink']?['id'];
                                  return rawId?.toString() == sendId;
                                });

                                final int deleteQty = qtyToDelete ?? 1;

                                if (idx != -1) {
                                  final raw = drinksOrders[idx] as Map;
                                  final int rawQty =
                                      (raw['quantity'] is num)
                                          ? (raw['quantity'] as num).toInt()
                                          : 1;
                                  final double rawAmt =
                                      (raw['amount'] is num)
                                          ? (raw['amount'] as num).toDouble()
                                          : 0.0;
                                  final double perUnit =
                                      rawQty > 0 ? rawAmt / rawQty : 0.0;

                                  if (deleteQty >= rawQty) {
                                    drinksOrders.removeAt(idx);
                                  } else {
                                    raw['quantity'] = rawQty - deleteQty;
                                    raw['amount'] = double.parse(
                                      (rawAmt - (perUnit * deleteQty))
                                          .toStringAsFixed(2),
                                    );
                                  }
                                }

                                final double delta = amountPerItem * deleteQty;
                                for (var s in sections) {
                                  for (var t in (s['tables'] as List)) {
                                    if ((t['drinksOrders']?['pendingDrinksOrders'] ??
                                            t['drinksOrders']?['ongoingDrinksOrders'] ??
                                            t['drinksOrders']?['completeDrinksOrders']) ==
                                        drinksOrders) {
                                      t['orderAmounts'] ??= {'totalAmount': 0};
                                      t['orderAmounts']['totalAmount'] =
                                          (t['orderAmounts']['totalAmount'] ??
                                              0) -
                                          delta;

                                      if (identical(
                                        t['drinksOrders']['pendingDrinksOrders'],
                                        drinksOrders,
                                      )) {
                                        t['orderAmounts']['pendingDrinksAmount'] =
                                            (t['orderAmounts']['pendingDrinksAmount'] ??
                                                0) -
                                            delta;
                                      } else if (identical(
                                        t['drinksOrders']['ongoingDrinksOrders'],
                                        drinksOrders,
                                      )) {
                                        t['orderAmounts']['ongoingDrinksAmount'] =
                                            (t['orderAmounts']['ongoingDrinksAmount'] ??
                                                0) -
                                            delta;
                                      } else if (identical(
                                        t['drinksOrders']['completeDrinksOrders'],
                                        drinksOrders,
                                      )) {
                                        t['orderAmounts']['completeDrinksAmount'] =
                                            (t['orderAmounts']['completeDrinksAmount'] ??
                                                0) -
                                            delta;
                                      }
                                      break;
                                    }
                                  }
                                }
                              });
                            }
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Delete Order',
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "₹${amount.toStringAsFixed(2)} - $new_status",
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 7),
                ],
              ),
            );
          }).toList(),
        const SizedBox(height: 10),
        _dottedDivider(),
        const SizedBox(height: 10),
      ],
    );
  }

  void showShiftOrderDialog(
    BuildContext context,
    Map<String, dynamic> item,
    String orderType, // 'food' or 'drink'
    List<dynamic> sourceOrderList,
  ) {
    ScaffoldMessengerState scaffoldMessenger = ScaffoldMessenger.of(context);

    List<dynamic> categories = [];
    List<dynamic> filteredTables = [];

    String? selectedCategoryId;
    dynamic selectedTable;
    int quantityToShift = 1;

    // Get current section info
    String getCurrentSectionId() {
      try {
        for (var cat in sections) {
          if ((cat['tables'] as List).any((t) {
            if (orderType == 'food') {
              return (t['orders']?['pendingOrders'] == sourceOrderList ||
                  t['orders']?['ongoingOrders'] == sourceOrderList ||
                  t['orders']?['completeOrders'] == sourceOrderList);
            } else {
              return (t['drinksOrders']?['pendingDrinksOrders'] ==
                      sourceOrderList ||
                  t['drinksOrders']?['ongoingDrinksOrders'] ==
                      sourceOrderList ||
                  t['drinksOrders']?['completeDrinksOrders'] ==
                      sourceOrderList);
            }
          })) {
            return cat['id'].toString();
          }
        }
      } catch (e) {
        print('❌ Error getting current section ID: $e');
      }
      return "";
    }

    String getSectionNameByTableId(int tableId) {
      try {
        for (final section in sections) {
          final tables = section['tables'] as List? ?? [];

          for (final table in tables) {
            final tId = table['id'];
            if (tId != null && int.tryParse(tId.toString()) == tableId) {
              return section['name']?.toString() ?? 'Unknown Section';
            }
          }
        }
      } catch (e, st) {
        debugPrint('❌ Error getting section by tableId: $e');
        debugPrint('$st');
      }
      return 'Unknown Section';
    }

    String getCurrentSectionName() {
      try {
        for (var cat in sections) {
          if ((cat['tables'] as List).any((t) {
            if (orderType == 'food') {
              return (t['orders']?['pendingOrders'] == sourceOrderList ||
                  t['orders']?['ongoingOrders'] == sourceOrderList ||
                  t['orders']?['completeOrders'] == sourceOrderList);
            } else {
              return (t['drinksOrders']?['pendingDrinksOrders'] ==
                      sourceOrderList ||
                  t['drinksOrders']?['ongoingDrinksOrders'] ==
                      sourceOrderList ||
                  t['drinksOrders']?['completeDrinksOrders'] ==
                      sourceOrderList);
            }
          })) {
            return cat['name'];
          }
        }
      } catch (e) {
        print('❌ Error getting current section name: $e');
      }
      return "Unknown Section";
    }

    int? getCurrentTableId() {
      try {
        // ✅ PRIORITY 1: Direct reference match via identical()
        // This is the most reliable check — works even when mergedOrderIds is empty
        for (var cat in sections) {
          for (var t in (cat['tables'] as List)) {
            final drinksMap = t['drinksOrders'];
            final ordersMap = t['orders'];

            if (orderType == 'drink' && drinksMap != null) {
              if (identical(
                    drinksMap['pendingDrinksOrders'],
                    sourceOrderList,
                  ) ||
                  identical(
                    drinksMap['ongoingDrinksOrders'],
                    sourceOrderList,
                  ) ||
                  identical(
                    drinksMap['completeDrinksOrders'],
                    sourceOrderList,
                  )) {
                final id = t['id'];
                if (id is int) return id;
                return int.tryParse(id.toString());
              }
            } else if (orderType == 'food' && ordersMap != null) {
              if (identical(ordersMap['pendingOrders'], sourceOrderList) ||
                  identical(ordersMap['ongoingOrders'], sourceOrderList) ||
                  identical(ordersMap['completeOrders'], sourceOrderList)) {
                final id = t['id'];
                if (id is int) return id;
                return int.tryParse(id.toString());
              }
            }
          }
        }

        // ✅ PRIORITY 2: Search by item ID in the correct order type
        final searchId =
            item['id'] ??
            ((item['mergedOrderIds'] is List &&
                    (item['mergedOrderIds'] as List).isNotEmpty)
                ? (item['mergedOrderIds'] as List).first
                : null);

        if (searchId != null) {
          for (var cat in sections) {
            for (var t in (cat['tables'] as List)) {
              final orderLists =
                  orderType == 'drink'
                      ? [
                        t['drinksOrders']?['pendingDrinksOrders'],
                        t['drinksOrders']?['ongoingDrinksOrders'],
                        t['drinksOrders']?['completeDrinksOrders'],
                      ]
                      : [
                        t['orders']?['pendingOrders'],
                        t['orders']?['ongoingOrders'],
                        t['orders']?['completeOrders'],
                      ];

              for (var list in orderLists) {
                if (list is List) {
                  for (var order in list) {
                    if (order != null && order['id'] == searchId) {
                      final id = t['id'];
                      if (id is int) return id;
                      return int.tryParse(id.toString());
                    }
                  }
                }
              }
            }
          }
        }

        // ✅ PRIORITY 3: table_number stored directly on the order
        final tableNum = item['table_number'];
        if (tableNum != null) {
          return int.tryParse(tableNum.toString());
        }

        debugPrint(
          '⚠️ Could not find table for order — item keys: ${item.keys.toList()}',
        );
        return null;
      } catch (e, st) {
        debugPrint('❌ Error in getCurrentTableId: $e\n$st');
        return null;
      }
    }

    Future<void> fetchCategories() async {
      try {
        final categoryResponse = await http.get(
          Uri.parse('${dotenv.env['API_URL']}/sections'),
        );

        if (categoryResponse.statusCode == 200) {
          categories = jsonDecode(categoryResponse.body);
        } else {
          print('❌ Failed to fetch categories: ${categoryResponse.statusCode}');
        }
      } catch (e) {
        print('❌ Error fetching categories: $e');
      }
    }

    final currentTableId = getCurrentTableId();
    int? getCurrentTableDisplayNumber() {
      if (currentTableId == null) return null;
      for (var cat in sections) {
        for (var t in (cat['tables'] as List)) {
          if (t['id'] == currentTableId) {
            final dn = t['display_number'];
            if (dn is int) return dn;
            return int.tryParse(dn?.toString() ?? '');
          }
        }
      }
      return currentTableId; // fallback
    }

    final currentTableDisplayNumber = getCurrentTableDisplayNumber();

    final currentSectionName =
        currentTableId != null
            ? getSectionNameByTableId(currentTableId)
            : 'Unknown Section';

    // ✅ VALIDATION: Check if we have the required data
    if (currentTableId == null) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            'Error: Cannot determine current table. Please try again.',
            style: GoogleFonts.poppins(color: Colors.white),
          ),
          backgroundColor: Colors.red,
        ),
      );
      print('❌ Cannot shift order - currentTableId is null');
      print('📊 Debug info:');
      print('  Section ID: $currentTableId ');
      print('  Section Name: $currentSectionName');
      print('  Order Type: $orderType');
      print('  Source List Length: ${sourceOrderList.length}');
      return;
    }

    // Get max quantity from item
    final maxQuantity =
        (item['quantity'] is num)
            ? (item['quantity'] as num).toInt()
            : int.tryParse(item['quantity']?.toString() ?? '') ?? 1;

    showDialog(
      context: context,
      builder: (context) {
        return FutureBuilder(
          future: fetchCategories(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const AlertDialog(
                content: Center(child: CircularProgressIndicator()),
              );
            }

            return StatefulBuilder(
              builder: (context, setState) {
                void filterTablesByCategory(String? categoryId) {
                  try {
                    final category = categories.firstWhere(
                      (cat) => cat['id'].toString() == categoryId,
                      orElse: () => null,
                    );

                    if (category != null) {
                      filteredTables = List.from(category['tables'] as List)
                        ..sort((a, b) {
                          final aNum = a['display_number'] ?? 0;
                          final bNum = b['display_number'] ?? 0;
                          return aNum.compareTo(bNum);
                        });
                    } else {
                      filteredTables = [];
                    }
                  } catch (e) {
                    print('❌ Error filtering tables: $e');
                    filteredTables = [];
                  }
                }

                String? selectedSectionName =
                    selectedCategoryId != null
                        ? categories.firstWhere(
                          (cat) => cat['id'].toString() == selectedCategoryId,
                        )['name']
                        : null;

                // Get item name
                String itemName =
                    orderType == 'food'
                        ? (item['item_desc'] ??
                            item['menu']?['name'] ??
                            'Unknown Item')
                        : (item['item_desc'] ??
                            item['drink']?['name'] ??
                            'Unknown Drink');

                return AlertDialog(
                  title: Text('Shift Order', style: GoogleFonts.poppins()),
                  backgroundColor: const Color.fromARGB(255, 235, 235, 229),
                  content: SingleChildScrollView(
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width * 0.7,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Display item name
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Container(
                              width: double.infinity, // ✅ THIS is required
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Item: $itemName',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Current Location: $currentSectionName - Table $currentTableDisplayNumber',
                                    style: GoogleFonts.poppins(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Quantity selector
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Quantity to shift:',
                                style: GoogleFonts.poppins(fontSize: 13),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    onPressed:
                                        quantityToShift > 1
                                            ? () {
                                              setState(() {
                                                quantityToShift--;
                                              });
                                            }
                                            : null,
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                    ),
                                  ),
                                  Text(
                                    quantityToShift.toString(),
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed:
                                        quantityToShift < maxQuantity
                                            ? () {
                                              setState(() {
                                                quantityToShift++;
                                              });
                                            }
                                            : null,
                                    icon: const Icon(Icons.add_circle_outline),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Text(
                            'Max: $maxQuantity',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Section dropdown
                          DropdownButtonFormField<String>(
                            value: selectedCategoryId,
                            decoration: InputDecoration(
                              labelText: "Select Destination Section",
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            items:
                                categories.map<DropdownMenuItem<String>>((cat) {
                                  return DropdownMenuItem<String>(
                                    value: cat['id'].toString(),
                                    child: Text(cat['name']),
                                  );
                                }).toList(),
                            onChanged: (value) {
                              setState(() {
                                selectedCategoryId = value;
                                filterTablesByCategory(value);
                                selectedTable = null;
                              });
                            },
                          ),
                          const SizedBox(height: 10),

                          // Table dropdown
                          DropdownButtonFormField<dynamic>(
                            value: selectedTable,
                            decoration: InputDecoration(
                              labelText: "Select Destination Table",
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            items:
                                filteredTables.map<DropdownMenuItem<dynamic>>((
                                  t,
                                ) {
                                  bool isCurrent =
                                      t['id']?.toString() ==
                                      currentTableId.toString();

                                  final displayNum =
                                      t['display_number'] ??
                                      (filteredTables.indexOf(t) + 1);

                                  return DropdownMenuItem<dynamic>(
                                    value: isCurrent ? null : t,
                                    enabled: !isCurrent,
                                    child: Row(
                                      children: [
                                        Text(
                                          "Table $displayNum - ${t['status']}",
                                          style: GoogleFonts.poppins(
                                            color:
                                                isCurrent
                                                    ? Colors.grey
                                                    : Colors.black,
                                          ),
                                        ),
                                        if (isCurrent) ...[
                                          const SizedBox(width: 8),
                                          Text(
                                            "(Current table)",
                                            style: GoogleFonts.poppins(
                                              color: Colors.grey,
                                              fontStyle: FontStyle.italic,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                }).toList(),
                            onChanged: (value) {
                              setState(() {
                                selectedTable = value;
                              });
                            },
                          ),
                          const SizedBox(height: 20),

                          // Summary
                          if (selectedTable != null)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.green.shade300,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Shift Summary:',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'From: $currentSectionName - Table $currentTableDisplayNumber',
                                    style: GoogleFonts.poppins(fontSize: 12),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'To: $selectedSectionName - Table ${selectedTable['display_number'] ?? selectedTable['id']}',
                                    style: GoogleFonts.poppins(fontSize: 12),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Quantity: $quantityToShift of $maxQuantity',
                                    style: GoogleFonts.poppins(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed:
                          selectedTable != null
                              ? () async {
                                try {
                                  if (currentTableId == null) {
                                    throw Exception('Current table ID is null');
                                  }
                                  final toTableId = selectedTable['id'];
                                  if (toTableId == null) {
                                    throw Exception(
                                      'Destination table ID is null',
                                    );
                                  }

                                  print('🚀 Initiating shift:');
                                  print('  From Table: $currentTableId');
                                  print('  To Table: $toTableId');
                                  print('  Quantity: $quantityToShift');

                                  await shiftOrder(
                                    context,
                                    scaffoldMessenger,
                                    item,
                                    orderType,
                                    currentTableId,
                                    toTableId is int
                                        ? toTableId
                                        : int.parse(toTableId.toString()),
                                    quantityToShift,
                                  );
                                  // ✅ shiftOrder already handles pop + fetchSections
                                  // Do NOT pop here — context is already dead
                                } catch (e, stackTrace) {
                                  print('❌ Dialog error: $e');
                                  print('Stack trace: $stackTrace');
                                  scaffoldMessenger.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Error shifting order: ${e.toString()}',
                                        style: GoogleFonts.poppins(
                                          color: Colors.white,
                                        ),
                                      ),
                                      backgroundColor: Colors.red,
                                      duration: const Duration(seconds: 5),
                                    ),
                                  );
                                }
                              }
                              : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color.fromARGB(
                          255,
                          237,
                          237,
                          107,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            LucideIcons.arrowRightLeft,
                            color: Colors.black,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Shift Order',
                            style: GoogleFonts.poppins(
                              color: Colors.black,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  // 2. Add this method to handle the actual order shifting API call

  Future<void> shiftOrder(
    BuildContext context,
    ScaffoldMessengerState scaffoldMessenger,
    Map<String, dynamic> item,
    String orderType,
    int fromTableId,
    int toTableId,
    int quantity,
  ) async {
    try {
      final url = Uri.parse('${dotenv.env['API_URL']}/tables/orders/shift');

      // ✅ IMPROVED: Get order IDs with better null handling
      List<int> orderIdsToShift = [];

      // Debug: Print the item structure
      print('📦 Item structure: $item');
      print('📦 Item keys: ${item.keys.toList()}');
      print('📦 mergedOrderIds: ${item['mergedOrderIds']}');
      print('📦 id: ${item['id']}');

      // Try to get IDs from mergedOrderIds first
      if (item.containsKey('mergedOrderIds') &&
          item['mergedOrderIds'] != null) {
        final merged = item['mergedOrderIds'];

        if (merged is List && merged.isNotEmpty) {
          print('📦 Processing mergedOrderIds list: $merged');

          for (var id in merged) {
            if (id == null) continue;

            int? parsedId;
            if (id is int) {
              parsedId = id;
            } else if (id is String) {
              parsedId = int.tryParse(id);
            } else {
              parsedId = int.tryParse(id.toString());
            }

            if (parsedId != null && parsedId > 0) {
              orderIdsToShift.add(parsedId);
              print('✅ Added order ID: $parsedId');
            }
          }

          // Take only the quantity we need
          if (orderIdsToShift.length > quantity) {
            orderIdsToShift = orderIdsToShift.take(quantity).toList();
          }
        }
      }

      // Fallback to single ID if mergedOrderIds didn't work
      if (orderIdsToShift.isEmpty &&
          item.containsKey('id') &&
          item['id'] != null) {
        print('📦 Fallback to single ID');

        int? singleId;
        if (item['id'] is int) {
          singleId = item['id'] as int;
        } else if (item['id'] is String) {
          singleId = int.tryParse(item['id'] as String);
        } else {
          singleId = int.tryParse(item['id'].toString());
        }

        if (singleId != null && singleId > 0) {
          orderIdsToShift.add(singleId);
          print('✅ Added single order ID: $singleId');
        }
      }

      // Additional fallback: check rawItems
      if (orderIdsToShift.isEmpty &&
          item.containsKey('rawItems') &&
          item['rawItems'] is List) {
        print('📦 Checking rawItems for IDs');
        final rawItems = item['rawItems'] as List;

        for (var rawItem in rawItems) {
          if (rawItem == null || rawItem is! Map) continue;

          var id = rawItem['id'];
          if (id == null &&
              rawItem.containsKey('raw') &&
              rawItem['raw'] is Map) {
            id = rawItem['raw']['id'];
          }

          if (id != null) {
            int? parsedId;
            if (id is int) {
              parsedId = id;
            } else {
              parsedId = int.tryParse(id.toString());
            }

            if (parsedId != null && parsedId > 0) {
              orderIdsToShift.add(parsedId);
              print('✅ Added ID from rawItems: $parsedId');

              if (orderIdsToShift.length >= quantity) break;
            }
          }
        }
      }

      if (orderIdsToShift.isEmpty) {
        throw Exception(
          'No valid order IDs found in item. Item structure: ${item.keys.toList()}',
        );
      }

      print('🚀 Final order IDs to shift: $orderIdsToShift');
      print('🚀 Shifting from table $fromTableId to table $toTableId');
      print('🚀 Order type: $orderType, Quantity: $quantity');

      // ✅ Build request body with null safety
      final requestBody = {
        'fromTableId': fromTableId,
        'toTableId': toTableId,
        'orderIds': orderIdsToShift,
        'orderType': orderType,
        'quantity': quantity,
      };

      print('🚀 Request body: ${jsonEncode(requestBody)}');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      print('📡 Response status: ${response.statusCode}');
      print('📡 Response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              'Order shifted successfully!',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            backgroundColor: Colors.green,
          ),
        );

        // ✅ Pop BEFORE fetchSections — while context is still valid
        if (context.mounted) {
          Navigator.pop(context);
          Navigator.pop(context);
          Navigator.pop(context);
        }

        // ✅ Refresh after popping
        await fetchSections();
      } else {
        final errorBody =
            response.body.isNotEmpty ? jsonDecode(response.body) : {};
        final errorMessage =
            errorBody['message'] ??
            errorBody['error'] ??
            'Failed to shift order';
        throw Exception(errorMessage);
      }
    } catch (e, stackTrace) {
      print('❌ Error shifting order: $e');
      print('📚 Stack trace: $stackTrace');

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            'Failed to shift order: ${e.toString()}',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
      rethrow;
    }
  }

  void debugPrintItem(Map<String, dynamic> item, String label) {
    print('\n========== DEBUG: $label ==========');
    print('Keys: ${item.keys.toList()}');

    item.forEach((key, value) {
      if (value is List) {
        print('$key: List with ${value.length} items');
        if (value.isNotEmpty) {
          print('  First item: ${value.first}');
        }
      } else if (value is Map) {
        print('$key: Map with keys ${(value as Map).keys.toList()}');
      } else {
        print('$key: $value (${value.runtimeType})');
      }
    });
    print('=====================================\n');
  }

  Widget _tableHeader(String label, bool isDesktop) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: isDesktop ? 14 : 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _dottedDivider() {
    return Wrap(
      children: List.generate(30, (index) {
        return Container(
          width: 4,
          height: 1,
          color: index % 2 == 0 ? Colors.grey : Colors.transparent,
          margin: const EdgeInsets.symmetric(horizontal: 1),
        );
      }),
    );
  }

  // Updated deleteOrder function with actual_table_number as table_id
  Future<bool?> deleteOrder(
    BuildContext context,
    String orderId,
    int deleteQty, {
    int? tableId,
    String? menuId,
    String? status,
  }) async {
    final remarksController = TextEditingController();
    final passwordController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        bool isDeleting = false;
        String? passwordError;

        return StatefulBuilder(
          builder:
              (context, setState) => AlertDialog(
                backgroundColor: Theme.of(context).dialogBackgroundColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                insetPadding: const EdgeInsets.symmetric(horizontal: 24),
                title: const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Delete Order',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
                  ),
                ),
                content:
                    isDeleting
                        ? const SizedBox(
                          height: 72,
                          child: Center(child: CircularProgressIndicator()),
                        )
                        : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              controller: remarksController,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: InputDecoration(
                                hintText: 'Reason (optional)',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              maxLines: 2,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: passwordController,
                              decoration: InputDecoration(
                                hintText: 'Password',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                errorText: passwordError,
                              ),
                              obscureText: true,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: const [
                                Icon(Icons.lock_outline, size: 14),
                                SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Enter your password to confirm deletion',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Deleting quantity: $deleteQty',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                actionsPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                actions: [
                  if (!isDeleting)
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                  if (!isDeleting)
                    TextButton(
                      onPressed: () async {
                        final remarks = remarksController.text.trim();
                        final password = passwordController.text.trim();

                        setState(() => passwordError = null);

                        if (password.isEmpty) {
                          setState(
                            () => passwordError = 'Please enter your password',
                          );
                          return;
                        }

                        setState(() => isDeleting = true);

                        try {
                          final url = Uri.parse(
                            '${dotenv.env['API_URL']}/orders/$orderId',
                          );

                          // Find actual_table_number from the table
                          int? actualTableNumber;
                          for (var s in sections) {
                            for (var t in (s['tables'] as List)) {
                              final tableOrders = t['orders'];
                              if (tableOrders != null) {
                                bool hasOrder = false;
                                for (var orderList in [
                                  tableOrders['pendingOrders'],
                                  tableOrders['ongoingOrders'],
                                  tableOrders['completeOrders'],
                                ]) {
                                  if (orderList != null && orderList is List) {
                                    if (orderList.any(
                                      (o) =>
                                          o != null &&
                                          (o['id']?.toString() == orderId ||
                                              o['orderId']?.toString() ==
                                                  orderId ||
                                              (o['mergedOrderIds'] is List &&
                                                  (o['mergedOrderIds'] as List)
                                                      .any(
                                                        (m) =>
                                                            m?.toString() ==
                                                            orderId,
                                                      ))),
                                    )) {
                                      hasOrder = true;
                                      break;
                                    }
                                  }
                                }
                                if (hasOrder) {
                                  // Use actual_table_number, or fallback to other table number fields
                                  actualTableNumber =
                                      t['actual_table_number'] ??
                                      t['table_number'] ??
                                      t['restaurent_table_number'] ??
                                      t['number'] ??
                                      t['id'];
                                  break;
                                }
                              }
                            }
                            if (actualTableNumber != null) break;
                          }

                          // Enhanced body with actual_table_number as table_id
                          final body = jsonEncode({
                            'remarks': remarks,
                            'password': password,
                            'userId': userId,
                            'quantity': deleteQty,
                            'table_id':
                                actualTableNumber, // Send actual_table_number as table_id
                            'menuId': menuId,
                            'status': status,
                          });

                          final response = await http.delete(
                            url,
                            headers: {
                              'Content-Type': 'application/json',
                              'Authorization': 'Bearer $token',
                            },
                            body: body,
                          );

                          if (!mounted) return;

                          if (response.statusCode == 200) {
                            await fetchSections();
                            if (!mounted) return;

                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Order deleted successfully'),
                              ),
                            );

                            Navigator.pop(context, true);
                            Navigator.pop(context, true);
                          } else if (response.statusCode == 401) {
                            setState(() {
                              isDeleting = false;
                              passwordError =
                                  'Wrong password — please try again';
                            });
                          } else {
                            setState(() => isDeleting = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Failed to delete order (${response.statusCode})',
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          if (!mounted) return;
                          setState(() => isDeleting = false);
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('Error: $e')));
                        }
                      },
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.redAccent.withOpacity(0.06),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      child: const Text(
                        'Delete',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  if (isDeleting)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: ElevatedButton.icon(
                        onPressed: null,
                        icon: const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        label: const Text('Deleting...'),
                      ),
                    ),
                ],
              ),
        );
      },
    );

    remarksController.dispose();
    passwordController.dispose();

    return result;
  }

  // Updated deleteDrinksOrder function with actual_table_number as table_id
  Future<bool?> deleteDrinksOrder(
    BuildContext context,
    String orderId,
    int deleteQty, {
    int? tableId,
    String? drinkId,
    String? status,
  }) async {
    final remarksController = TextEditingController();
    final passwordController = TextEditingController();
    print("orderId, deleteQty: $orderId $deleteQty\n\n");

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        bool isDeleting = false;
        String? passwordError;

        return StatefulBuilder(
          builder:
              (context, setState) => AlertDialog(
                backgroundColor: Theme.of(context).dialogBackgroundColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                insetPadding: const EdgeInsets.symmetric(horizontal: 24),
                title: const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Delete Order',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
                  ),
                ),
                content:
                    isDeleting
                        ? const SizedBox(
                          height: 72,
                          child: Center(child: CircularProgressIndicator()),
                        )
                        : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              controller: remarksController,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: InputDecoration(
                                hintText: 'Reason (optional)',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              maxLines: 2,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: passwordController,
                              decoration: InputDecoration(
                                hintText: 'Password',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                errorText: passwordError,
                              ),
                              obscureText: true,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: const [
                                Icon(Icons.lock_outline, size: 14),
                                SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Enter your password to confirm deletion',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Deleting quantity: $deleteQty',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                actionsPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                actions: [
                  if (!isDeleting)
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                  if (!isDeleting)
                    TextButton(
                      onPressed: () async {
                        final remarks = remarksController.text.trim();
                        final password = passwordController.text.trim();

                        setState(() => passwordError = null);

                        if (password.isEmpty) {
                          setState(
                            () => passwordError = 'Please enter your password',
                          );
                          return;
                        }

                        setState(() => isDeleting = true);

                        try {
                          final url = Uri.parse(
                            '${dotenv.env['API_URL']}/drinks-orders/$orderId',
                          );

                          // Find actual_table_number from the table
                          int? actualTableNumber;
                          for (var s in sections) {
                            for (var t in (s['tables'] as List)) {
                              final tableDrinksOrders = t['drinksOrders'];
                              if (tableDrinksOrders != null) {
                                bool hasOrder = false;
                                for (var orderList in [
                                  tableDrinksOrders['pendingDrinksOrders'],
                                  tableDrinksOrders['ongoingDrinksOrders'],
                                  tableDrinksOrders['completeDrinksOrders'],
                                ]) {
                                  if (orderList != null && orderList is List) {
                                    if (orderList.any(
                                      (o) =>
                                          o != null &&
                                          (o['id']?.toString() == orderId ||
                                              o['orderId']?.toString() ==
                                                  orderId ||
                                              (o['mergedOrderIds'] is List &&
                                                  (o['mergedOrderIds'] as List)
                                                      .any(
                                                        (m) =>
                                                            m?.toString() ==
                                                            orderId,
                                                      ))),
                                    )) {
                                      hasOrder = true;
                                      break;
                                    }
                                  }
                                }
                                if (hasOrder) {
                                  // Use actual_table_number, or fallback to other table number fields
                                  actualTableNumber =
                                      t['actual_table_number'] ??
                                      t['table_number'] ??
                                      t['restaurent_table_number'] ??
                                      t['number'] ??
                                      t['id'];
                                  break;
                                }
                              }
                            }
                            if (actualTableNumber != null) break;
                          }

                          // Enhanced body with actual_table_number as table_id
                          final body = jsonEncode({
                            'remarks': remarks,
                            'password': password,
                            'userId': userId,
                            'quantity': deleteQty,
                            'table_id':
                                actualTableNumber, // Send actual_table_number as table_id
                            'drinkId':
                                drinkId, // Using drinkId instead of menuId for drinks
                            'status': status,
                          });

                          final response = await http.delete(
                            url,
                            headers: {
                              'Content-Type': 'application/json',
                              'Authorization': 'Bearer $token',
                            },
                            body: body,
                          );

                          if (!mounted) return;

                          if (response.statusCode == 200) {
                            await fetchSections();
                            if (!mounted) return;

                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Order deleted successfully'),
                              ),
                            );

                            Navigator.pop(context, true);
                            Navigator.pop(context, true);
                            Navigator.pop(context, true);
                          } else if (response.statusCode == 401) {
                            setState(() {
                              isDeleting = false;
                              passwordError =
                                  'Wrong password — please try again';
                            });
                          } else {
                            if (!mounted) return;
                            setState(() => isDeleting = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Failed to delete order (${response.statusCode})',
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          if (!mounted) return;
                          setState(() => isDeleting = false);
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('Error: $e')));
                        }
                      },
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.redAccent.withOpacity(0.06),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      child: const Text(
                        'Delete',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  if (isDeleting)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: ElevatedButton.icon(
                        onPressed: null,
                        icon: const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        label: const Text('Deleting...'),
                      ),
                    ),
                ],
              ),
        );
      },
    );

    remarksController.dispose();
    passwordController.dispose();

    return result;
  }

  Widget buildOrderTableWithTotal(BuildContext context, dynamic table) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 800;

    print("\n\n--- Table Data Debug ---$table\n\n");
    // Helper: if list items have 'quantity' use sum(quantity), otherwise fallback to list length.
    int countItems(dynamic list) {
      if (list == null) return 0;
      if (list is! List) return 0;
      var total = 0;
      for (final it in list) {
        try {
          final q =
              (it is Map && it.containsKey('quantity'))
                  ? (it['quantity'] is String
                      ? int.tryParse(it['quantity']) ?? 0
                      : (it['quantity'] is num
                          ? (it['quantity'] as num).toInt()
                          : 0))
                  : null;
          if (q != null && q > 0) {
            total += q;
          } else {
            total += 1;
          }
        } catch (_) {
          total += 1;
        }
      }
      return total;
    }

    // Replace the normalizeFoodList function with this updated version:
    List<Map<String, dynamic>> normalizeFoodList(dynamic raw) {
      if (raw == null || raw is! List) return <Map<String, dynamic>>[];
      final out = <Map<String, dynamic>>[];
      for (final it in raw) {
        if (it == null) continue;
        try {
          final Map<String, dynamic> m = it as Map<String, dynamic>;
          final qty =
              m['quantity'] is num
                  ? (m['quantity'] as num).toInt()
                  : (m['quantity'] is String
                      ? int.tryParse(m['quantity']) ?? 1
                      : 1);

          double amt;

          // ✅ PRIORITY 1: Stored `amount` — always the final taxed total
          // Set correctly by _normalizeOrderAmount (refresh) or socket handlers (live)
          if (m['amount'] is num && (m['amount'] as num) > 0) {
            amt = (m['amount'] as num).toDouble();
          }
          // ✅ PRIORITY 2: taxedAmount / taxedActualAmount from socket
          else if (m['taxedAmount'] is num && (m['taxedAmount'] as num) > 0) {
            amt = (m['taxedAmount'] as num).toDouble();
          } else if (m['taxedActualAmount'] is num &&
              (m['taxedActualAmount'] as num) > 0) {
            amt = (m['taxedActualAmount'] as num).toDouble();
          }
          // ✅ PRIORITY 3: amount_per_item × qty
          else if (m['amount_per_item'] is num &&
              (m['amount_per_item'] as num) > 0) {
            amt = (m['amount_per_item'] as num).toDouble() * qty;
          }
          // ✅ PRIORITY 4 (last resort): base price + tax
          else if (m['menu'] is Map && m['menu']['price'] is num) {
            amt = (m['menu']['price'] as num).toDouble() * qty * 1.05;
          } else {
            amt = 0.0;
          }

          String displayName;
          final isCustom = m['is_custom'] == true;

          if (isCustom) {
            displayName =
                (m['note'] ?? m['item_desc'] ?? 'Custom Item').toString();
            if (displayName.trim().isEmpty) displayName = 'Custom Item';
          } else {
            displayName = (m['item_desc'] ?? '').toString();
            if (displayName.trim().isEmpty && m['menu'] is Map) {
              displayName = (m['menu']['name'] ?? '').toString();
            }
            if (displayName.trim().isEmpty) displayName = 'Unknown Item';
          }

          out.add({
            'id': m['id'],
            'menuId': m['menuId'] ?? m['menu']?['id'],
            'item_desc': displayName,
            'quantity': qty,
            'amount': amt,
            'amount_per_item': amt / qty,
            'status': m['status'] ?? 'pending',
            'menu': m['menu'],
            'is_custom': isCustom,
            'note': m['note'],
            'mergedOrderIds': m['mergedOrderIds'] ?? [],
            'kotNumbers': m['kotNumbers'] ?? [],
            'raw': m,
          });
        } catch (e) {
          continue;
        }
      }
      return out;
    }

    // Replace the normalizeDrinkList function with this updated version:
    List<Map<String, dynamic>> normalizeDrinkList(dynamic raw) {
      if (raw == null || raw is! List) return <Map<String, dynamic>>[];
      final out = <Map<String, dynamic>>[];
      for (final it in raw) {
        if (it == null) continue;
        try {
          final Map<String, dynamic> m = it as Map<String, dynamic>;
          final qty =
              m['quantity'] is num
                  ? (m['quantity'] as num).toInt()
                  : (m['quantity'] is String
                      ? int.tryParse(m['quantity']) ?? 1
                      : 1);

          double amt;

          // ✅ PRIORITY 1: Stored `amount` — always the final taxed total
          if (m['amount'] is num && (m['amount'] as num) > 0) {
            amt = (m['amount'] as num).toDouble();
          }
          // ✅ PRIORITY 2: taxedAmount / taxedActualAmount from socket
          else if (m['taxedAmount'] is num && (m['taxedAmount'] as num) > 0) {
            amt = (m['taxedAmount'] as num).toDouble();
          } else if (m['taxedActualAmount'] is num &&
              (m['taxedActualAmount'] as num) > 0) {
            amt = (m['taxedActualAmount'] as num).toDouble();
          }
          // ✅ PRIORITY 3: amount_per_item × qty
          else if (m['amount_per_item'] is num &&
              (m['amount_per_item'] as num) > 0) {
            amt = (m['amount_per_item'] as num).toDouble() * qty;
          }
          // ✅ PRIORITY 4 (last resort): base price + tax
          else if (m['drink'] is Map && m['drink']['price'] is num) {
            final price = (m['drink']['price'] as num).toDouble();
            final applyVAT = m['drink']?['applyVAT'] == true;
            amt = price * qty * (applyVAT ? 1.10 : 1.05);
          } else {
            amt = 0.0;
          }

          String displayName;
          final isCustom = m['is_custom'] == true;

          if (isCustom) {
            displayName = '';
            if (m['note'] != null && m['note'].toString().trim().isNotEmpty) {
              displayName = m['note'].toString().trim();
            }
            if (displayName.isEmpty &&
                m['item_desc'] != null &&
                m['item_desc'].toString().trim().isNotEmpty) {
              displayName = m['item_desc'].toString().trim();
            }
            if (displayName.isEmpty &&
                m['drink'] is Map &&
                m['drink']['name'] != null) {
              displayName = m['drink']['name'].toString().trim();
            }
            if (displayName.isEmpty) displayName = 'Custom Drink';
          } else {
            if (m['drink'] is Map) {
              displayName =
                  (m['drink']['name'] ?? m['drink']['friendlyName'] ?? '')
                      .toString();
            } else {
              displayName = '';
            }
            if (displayName.isEmpty) {
              displayName =
                  (m['drinkName'] ??
                          m['friendlyName'] ??
                          m['item_desc'] ??
                          'Unknown Drink')
                      .toString();
            }
          }

          out.add({
            'id': m['id'],
            'drinkId': m['drink']?['id'] ?? m['drinkId'],
            'drinkName': displayName,
            'item_desc': displayName,
            'quantity': qty,
            'amount': amt,
            'amount_per_item': qty > 0 ? amt / qty : 0.0,
            'status': m['status'] ?? 'pending',
            'drink': m['drink'],
            'is_custom': isCustom,
            'note': m['note'],
            'mergedOrderIds': m['mergedOrderIds'] ?? [],
            'kotNumbers': m['kotNumbers'] ?? [],
            'raw': m,
          });
        } catch (e) {
          continue;
        }
      }
      return out;
    }

    // Prepare normalized lists once to reuse in counts & builders
    final normalizedPendingFood = normalizeFoodList(
      table['orders']?['pendingOrders'],
    );
    final normalizedOngoingFood = normalizeFoodList(
      table['orders']?['ongoingOrders'],
    );
    final normalizedCompleteFood = normalizeFoodList(
      table['orders']?['completeOrders'],
    );

    final normalizedPendingDrinks = normalizeDrinkList(
      table['drinksOrders']?['pendingDrinksOrders'],
    );
    final normalizedOngoingDrinks = normalizeDrinkList(
      table['drinksOrders']?['ongoingDrinksOrders'],
    );
    final normalizedCompleteDrinks = normalizeDrinkList(
      table['drinksOrders']?['completeDrinksOrders'],
    );

    print("\n\nnormalizedPendingDrinks: $normalizedPendingDrinks");
    print("\nnormalizedOngoingDrinks: $normalizedOngoingDrinks");
    print("\nnormalizedCompleteDrinks: $normalizedCompleteDrinks");

    // Helper count that uses normalized lists (keeps backward compatibility)
    int countNormalized(List<Map<String, dynamic>> list) {
      if (list == null) return 0;
      var total = 0;
      for (final it in list) {
        final q =
            it['quantity'] is num
                ? (it['quantity'] as num).toInt()
                : (it['quantity'] is String
                    ? int.tryParse(it['quantity']?.toString() ?? '') ?? 1
                    : 1);
        total += (q > 0 ? q : 1);
      }
      return total;
    }

    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          builder: (context) {
            final screenWidth = MediaQuery.of(context).size.width;
            final isDesktop = screenWidth >= 800;
            final dialogWidth = isDesktop ? 800.0 : null;

            return Dialog(
              backgroundColor: const Color(0xFFF1EFEC),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: dialogWidth ?? double.infinity,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Orders Overview',
                          style: GoogleFonts.poppins(
                            fontSize: isDesktop ? 20 : 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 16),
                        buildOrderRow(
                          context,
                          'Pending Orders',
                          countNormalized(normalizedPendingFood),
                          countNormalized(normalizedPendingDrinks),
                        ),
                        const SizedBox(height: 8),
                        buildOrderRow(
                          context,
                          'Ongoing Orders',
                          countNormalized(normalizedOngoingFood),
                          countNormalized(normalizedOngoingDrinks),
                        ),
                        const SizedBox(height: 8),
                        buildOrderRow(
                          context,
                          'Complete Orders',
                          countNormalized(normalizedCompleteFood),
                          countNormalized(normalizedCompleteDrinks),
                        ),
                        const Divider(height: 24),
                        if (normalizedPendingFood.isNotEmpty)
                          buildOrderList(
                            context,
                            'Pending Orders',
                            normalizedPendingFood,
                            'Pending',
                          ),
                        if (normalizedOngoingFood.isNotEmpty)
                          buildOrderList(
                            context,
                            'Ongoing Orders',
                            normalizedOngoingFood,
                            'Accepted',
                          ),
                        if (normalizedCompleteFood.isNotEmpty)
                          buildOrderList(
                            context,
                            'Completed Orders',
                            normalizedCompleteFood,
                            'Completed',
                          ),
                        const Divider(height: 24),
                        if (normalizedPendingDrinks.isNotEmpty)
                          buildDrinksOrderList(
                            context,
                            'Pending Drinks Orders',
                            normalizedPendingDrinks,
                            'Pending',
                          ),
                        if (normalizedOngoingDrinks.isNotEmpty)
                          buildDrinksOrderList(
                            context,
                            'Ongoing Drinks Orders',
                            normalizedOngoingDrinks,
                            'Accepted',
                          ),
                        if (normalizedCompleteDrinks.isNotEmpty)
                          buildDrinksOrderList(
                            context,
                            'Completed Drinks Orders',
                            normalizedCompleteDrinks,
                            'Completed',
                          ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
      child:
          isDesktop
              ? Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                color: const Color(0xFFF7F6F2),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      // Order Summary
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Orders Overview',
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 16),
                            buildOrderRow(
                              context,
                              'Pending Orders',
                              countNormalized(normalizedPendingFood),
                              countNormalized(normalizedPendingDrinks),
                            ),
                            const SizedBox(height: 12),
                            buildOrderRow(
                              context,
                              'Ongoing Orders',
                              countNormalized(normalizedOngoingFood),
                              countNormalized(normalizedOngoingDrinks),
                            ),
                            const SizedBox(height: 12),
                            buildOrderRow(
                              context,
                              'Complete Orders',
                              countNormalized(normalizedCompleteFood),
                              countNormalized(normalizedCompleteDrinks),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 32),
                      // Total Amount
                      Expanded(
                        flex: 2,
                        child: Container(
                          height: 100,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE6E4DC),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Total Amount: ₹${_roundAmount(table['orderAmounts']?['totalAmount']).round()}',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              : IntrinsicHeight(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Orders Table
                    Expanded(
                      flex: 3,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color.fromARGB(255, 235, 235, 229),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            buildOrderRow(
                              context,
                              'Pending Orders',
                              countNormalized(normalizedPendingFood),
                              countNormalized(normalizedPendingDrinks),
                            ),
                            const SizedBox(height: 8),
                            buildOrderRow(
                              context,
                              'Ongoing Orders',
                              countNormalized(normalizedOngoingFood),
                              countNormalized(normalizedOngoingDrinks),
                            ),
                            const SizedBox(height: 8),
                            buildOrderRow(
                              context,
                              'Complete Orders',
                              countNormalized(normalizedCompleteFood),
                              countNormalized(normalizedCompleteDrinks),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Total Amount
                    Expanded(
                      flex: 2,
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color.fromARGB(255, 235, 235, 229),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Total Amount: ₹${_roundAmount(table['orderAmounts']?['totalAmount']).round()}',
                          style: GoogleFonts.poppins(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
    );
  }

  Future<void> deleteSectionById(dynamic id) async {
    final sectionId = id.toString();
    try {
      final response = await http.delete(
        Uri.parse(
          '${dotenv.env['API_URL']}/sections/$id',
        ), // Replace with actual base URL
        headers: {"Content-Type": "application/json"},
      );

      if (response.statusCode == 200) {
        // Success - you can add your logic to refresh the list
        print('Section deleted successfully');
        fetchSections();
      } else {
        print('Failed to delete section: ${response.body}');
      }
    } catch (e) {
      print('Error deleting section: $e');
    }
  }

  void DeleteSectionDialog(BuildContext context, Map section) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Confirm Delete"),
          backgroundColor: Colors.white,
          content: Text(
            "Are you sure you want to delete section ${section['name']}?,\nIt will also delete all the tables in ${section['name']} section.",
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await deleteSectionById(section['id'].toString());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Color.fromARGB(255, 241, 79, 79),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    15,
                  ), // Set your desired radius here
                ),
              ),
              child: Text(
                "Yes, Delete",
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> deleteTableById(dynamic id) async {
    final tableId = id.toString();
    try {
      final response = await http.delete(
        Uri.parse(
          '${dotenv.env['API_URL']}/tables/$id',
        ), // Replace with actual base URL
        headers: {"Content-Type": "application/json"},
      );

      if (response.statusCode == 200) {
        // Success - you can add your logic to refresh the list
        print('Table deleted successfully');
        fetchSections();
        Navigator.of(context).pop();
      } else {
        print('Failed to delete table: ${response.body}');
      }
    } catch (e) {
      print('Error deleting table: $e');
    }
  }

  void DeleteTableDialog(BuildContext context, Map table) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Confirm Delete"),
          backgroundColor: Colors.white,
          content: Text(
            "Are you sure you want to delete this table",
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await deleteTableById(table['id'].toString());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Color.fromARGB(255, 241, 79, 79),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    15,
                  ), // Set your desired radius here
                ),
              ),
              child: Text(
                "Yes, Delete",
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget buildOrderRow(
    BuildContext context,
    String label,
    int foodCount,
    int drinksCount,
  ) {
    int totalCount = foodCount + drinksCount;

    // Determine if the screen is large (desktop or tablet)
    double screenWidth = MediaQuery.of(context).size.width;
    bool isLargeScreen = screenWidth > 600; // You can adjust this threshold

    double fontSize = isLargeScreen ? 13 : 11;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          totalCount.toString(),
          style: GoogleFonts.poppins(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // Build status indicator
  Widget buildStatusIndicator(String status) {
    Color statusColor =
        status == 'free'
            ? Colors.green
            : (status == 'occupied'
                ? Colors.red
                : (status == 'merged'
                    ? Color.fromARGB(255, 47, 157, 146)
                    : Colors.orange));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.toUpperCase(),
        style: GoogleFonts.poppins(
          color: statusColor,
          fontWeight: FontWeight.bold,
          fontSize: 9,
        ),
      ),
    );
  }

  void updateTableStatus(
    BuildContext context,
    int tableId,
    String status,
  ) async {
    final String url = '${dotenv.env['API_URL']}/tables/$tableId/$status';

    try {
      final response = await http.put(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({}),
      );

      if (response.statusCode == 200) {
        fetchSections();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Table $tableId updated to $status',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: Colors.black, // Keep white text for contrast
              ),
            ),
            backgroundColor: Colors.green,
          ),
        );
        fetchSections();
      } else {
        print('Failed to update table: ${response.statusCode}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to update table $tableId',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                color: Colors.white, // Keep white text for contrast
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('Error occurred while updating table: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating table $tableId'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  // Build section with collapsible tables

  void _recomputeSectionSummaryInline(int sectionIndex) {
    if (sectionIndex < 0 || sectionIndex >= sections.length) return;
    final section = sections[sectionIndex];
    int activeCount = 0;
    double sectionTotal = 0.0;

    for (final table in (section['tables'] as List? ?? [])) {
      if (table == null) continue;
      final tableTotal = _roundAmount(table['orderAmounts']?['totalAmount']);
      if (tableTotal > 0) {
        activeCount++;
        sectionTotal += tableTotal;
      }
    }

    section['summary'] = {
      'activeTableCount': activeCount,
      'sectionTotalAmount': sectionTotal.round(),
    };

    print(
      '✅ Recomputed section ${section['name']}: $activeCount active tables, ₹${sectionTotal.round()} total',
    );
  }

  void _updateSectionSummary(
    int sectionId,
    double amountToAdd,
    bool tableWasFree,
  ) {
    setState(() {
      final sectionIndex = sections.indexWhere((s) => s['id'] == sectionId);
      if (sectionIndex == -1) return;
      _recomputeSectionSummaryInline(sectionIndex);
    });
  }

  /// Check if table was free before adding order
  bool _wasTableFree(Map<String, dynamic> table, double currentTotal) {
    // If current total is just the amount we're adding, table was free
    return currentTotal == 0 || (table['status'] ?? 'free') == 'free';
  }

  String getSectionInitials(String name) {
    if (name.trim().isEmpty) return '';

    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }

    // Take first letter of first 2 words (VIP Lounge → VL)
    return parts.take(2).map((e) => e.substring(0, 1).toUpperCase()).join();
  }

  // FIXED buildSectionCard method (remove StatefulBuilder):

  Widget buildSectionCard(dynamic section) {
    List<dynamic> tables = List<dynamic>.from(section['tables'] ?? []);
    bool isExpanded = false;

    // ✅ Sort tables by display_number (or id as fallback) to maintain consistent ordering
    tables.sort((a, b) {
      final aNum = a['display_number'] ?? a['id'] ?? 0;
      final bNum = b['display_number'] ?? b['id'] ?? 0;
      return (aNum as int).compareTo(bNum as int);
    });

    // Group splits by parent and gather roots (parents)
    final Map<int, List<dynamic>> splitsByParent = {};
    final List<dynamic> roots = [];

    for (var t in tables) {
      final parentId = t['parent_table_id'];
      if (parentId == null) {
        roots.add(t);
      } else {
        final pid =
            parentId is int
                ? parentId
                : int.tryParse(parentId?.toString() ?? '');
        if (pid == null) {
          roots.add(t);
        } else {
          splitsByParent.putIfAbsent(pid, () => []).add(t);
        }
      }
    }

    // ✅ Build display structure using display_number instead of dynamic indexing
    final Map<int, int> rootNumberMap = {};
    for (var root in roots) {
      final rootId = root['id'] as int;
      // ✅ Use display_number as the persistent table number
      final displayNumber = root['display_number'] ?? root['id'];
      rootNumberMap[rootId] =
          displayNumber is int
              ? displayNumber
              : int.tryParse(displayNumber.toString()) ?? rootId;
    }

    final List<Map<String, dynamic>> orderedTables = [];
    for (var root in roots) {
      final int rootId = root['id'] as int;
      final int rootDisplayNumber = rootNumberMap[rootId]!;

      orderedTables.add({
        'table': root,
        'isSplit': false,
        'rootNumber': rootDisplayNumber,
        'splitIndex': null,
      });

      final children = splitsByParent[rootId] ?? [];
      if (children.isNotEmpty) {
        children.sort((a, b) {
          final sa = (a['split_name'] ?? '').toString();
          final sb = (b['split_name'] ?? '').toString();
          if (sa.isNotEmpty && sb.isNotEmpty) return sa.compareTo(sb);
          final ai =
              a['id'] is int
                  ? a['id'] as int
                  : int.tryParse(a['id']?.toString() ?? '') ?? 0;
          final bi =
              b['id'] is int
                  ? b['id'] as int
                  : int.tryParse(b['id']?.toString() ?? '') ?? 0;
          return ai.compareTo(bi);
        });

        for (var cIndex = 0; cIndex < children.length; cIndex++) {
          final child = children[cIndex];
          orderedTables.add({
            'table': child,
            'isSplit': true,
            'rootNumber': rootDisplayNumber,
            'splitIndex': cIndex,
          });
        }
        splitsByParent.remove(rootId);
      }
    }

    // Handle orphan splits (splits without parents)
    if (splitsByParent.isNotEmpty) {
      splitsByParent.values.forEach((list) {
        list.forEach((child) {
          orderedTables.add({
            'table': child,
            'isSplit': true,
            'rootNumber': null,
            'splitIndex': null,
          });
        });
      });
    }

    return Container(
      width: MediaQuery.of(context).size.width * 0.9,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 18),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: isExpanded ? 0 : 2,
        color: const Color.fromARGB(255, 235, 235, 229),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            iconColor: Colors.red,
            collapsedIconColor: Colors.black54,
            onExpansionChanged: (expanded) {
              setState(() {
                isExpanded = expanded;
              });
            },
            title: StatefulBuilder(
              builder: (context, setStateLocal) {
                // Re-read the summary values each time this rebuilds
                final activeTableCount =
                    section['summary']?['activeTableCount'] ?? 0;
                final sectionTotalAmount =
                    section['summary']?['sectionTotalAmount'] ?? 0;

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${section['name']} (Ongoing:$activeTableCount/ ₹$sectionTotalAmount)',
                        style: GoogleFonts.poppins(
                          fontSize: 9.0.sp.clamp(13.0, 14.0),
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    if (userRole == 'Admin' ||
                        userRole == 'Restaurant Manager' ||
                        userRole == 'Billing Team' ||
                        userRole == 'Owner' ||
                        userRole == 'Acting Restaurant Manager')
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: GestureDetector(
                              onTap: () => showEditSectionDialog(section),
                              child: Icon(
                                LucideIcons.edit,
                                size: 17,
                                color: Colors.redAccent,
                              ),
                            ),
                          ),
                          SizedBox(width: 10),
                          GestureDetector(
                            onTap: () => DeleteSectionDialog(context, section),
                            child: Icon(
                              LucideIcons.trash2,
                              size: 17,
                              color: Colors.redAccent,
                            ),
                          ),
                        ],
                      ),
                  ],
                );
              },
            ),
            children: [
              // Legend
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Wrap(
                  alignment: WrapAlignment.start,
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    buildLegendItem('Free', Color.fromARGB(255, 116, 200, 169)),
                    buildLegendItem('Occupied', Colors.red.shade300),
                    buildLegendItem('Reserved', Colors.orange.shade300),
                    buildLegendItem('Merged', Colors.blue.shade300),
                    buildLegendItem('Settle Up', Color(0xFF8FA31E)),
                  ],
                ),
              ),

              // Grid of tables
              LayoutBuilder(
                builder: (context, constraints) {
                  bool isLargeScreen = constraints.maxWidth > 500;
                  int crossAxisCount = isLargeScreen ? 5 : 3;

                  return GridView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: orderedTables.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 1,
                    ),
                    itemBuilder: (context, visualIndex) {
                      final meta = orderedTables[visualIndex];
                      final table = meta['table'] as Map<String, dynamic>;
                      final bool isSplit = meta['isSplit'] == true;
                      final int? rootNumber = meta['rootNumber'] as int?;
                      final int? splitIndex = meta['splitIndex'] as int?;

                      String status = (table['status'] ?? '').toString();
                      String capitalizedStatus =
                          status.isNotEmpty
                              ? status[0].toUpperCase() + status.substring(1)
                              : '';

                      Color bgColor;
                      switch (status) {
                        case 'settleUp':
                          bgColor = Color(0xFF8FA31E);
                          break;
                        case 'occupied':
                          bgColor = Colors.red.shade300;
                          break;
                        case 'reserved':
                          bgColor = Colors.orange.shade300;
                          break;
                        case 'merged':
                          bgColor = Colors.blue.shade300;
                          break;
                        default:
                          bgColor = const Color.fromARGB(255, 116, 200, 169);
                      }

                      // ✅ Generate display label using persistent display_number
                      String displayLabel;
                      if (!isSplit) {
                        String name = section['name'];
                        if (name.endsWith(" Sir")) {
                          name = name.substring(0, name.length - 4);
                        }
                        if (name.endsWith(" sir")) {
                          name = name.substring(0, name.length - 4);
                        }
                        final tableNum =
                            rootNumber ??
                            table['display_number'] ??
                            table['id'];
                        displayLabel = "$name-T $tableNum";
                      } else {
                        final splitName =
                            (table['split_name'] ?? '').toString();
                        if (splitName.isNotEmpty) {
                          displayLabel = "${section['name']}-$splitName";
                        } else if (rootNumber != null && splitIndex != null) {
                          final suffix = String.fromCharCode(
                            65 + (splitIndex % 26),
                          );
                          displayLabel =
                              "${section['name']}-T ${rootNumber}$suffix";
                        } else {
                          // ⚠️ FIX: Fallback for orphan splits without parent
                          displayLabel =
                              "${section['name']}-${table['split_name'] ?? 'Split ${table['id']}'}";
                        }
                      }
                      String sectionName = section['name'];
                      String tablePart = displayLabel.replaceFirst(
                        '$sectionName-',
                        '',
                      );

                      int totalAmount =
                          _roundAmount(
                            table['orderAmounts']?['totalAmount'],
                          ).round();

                      return GestureDetector(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder:
                                (dialogContext) => Dialog(
                                  insetPadding: const EdgeInsets.all(12),
                                  child: SingleChildScrollView(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        buildTableCard(
                                          table,
                                          visualIndex,
                                          section['name'],
                                          section['id'],
                                          displayLabel,
                                          totalAmount,
                                        ),
                                        const SizedBox(height: 12),
                                        Align(
                                          alignment: Alignment.center,
                                          child: ElevatedButton.icon(
                                            onPressed:
                                                () =>
                                                    Navigator.of(
                                                      dialogContext,
                                                    ).pop(),
                                            icon: const Icon(
                                              Icons.close,
                                              color: Colors.black,
                                            ),
                                            label: Text(
                                              "Close",
                                              style: GoogleFonts.poppins(
                                                color: Colors.black,
                                              ),
                                            ),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  const Color.fromARGB(
                                                    255,
                                                    255,
                                                    159,
                                                    159,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 30),
                                      ],
                                    ),
                                  ),
                                ),
                          );
                        },
                        child: Card(
                          color: bgColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(6.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  children: [
                                    Text(
                                      kIsWeb
                                          ? displayLabel
                                          : '${getSectionInitials(sectionName)}-$tablePart',
                                      style: GoogleFonts.poppins(
                                        fontSize: 10.0,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),

                                    if (isSplit)
                                      const Icon(
                                        Icons.call_split,
                                        size: 12,
                                        color: Colors.white70,
                                      ),

                                    const SizedBox(height: 4),
                                    Text(
                                      '₹${_roundAmount(table['orderAmounts']?['totalAmount']).round()}',
                                      style: GoogleFonts.poppins(
                                        fontSize: 9.0.sp.clamp(9.0, 13.0),
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  capitalizedStatus,
                                  style: GoogleFonts.poppins(
                                    fontSize: kIsWeb ? 14 : 9,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: GoogleFonts.poppins(fontSize: kIsWeb ? 12 : 9)),
      ],
    );
  }

  Widget _buildSectionTabs() {
    return Listener(
      onPointerSignal: (pointerSignal) {
        if (kIsWeb && pointerSignal is PointerScrollEvent) {
          final newOffset =
              _sectionScrollController.offset + pointerSignal.scrollDelta.dy;

          if (newOffset >= _sectionScrollController.position.minScrollExtent &&
              newOffset <= _sectionScrollController.position.maxScrollExtent) {
            _sectionScrollController.jumpTo(newOffset);
          }
        }
      },
      child: SingleChildScrollView(
        controller: _sectionScrollController,
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        child: Row(
          children: List.generate(sections.length, (index) {
            final section = sections[index];
            final isSelected = _selectedSectionIndex == index;

            final activeTableCount =
                section['summary']?['activeTableCount'] ?? 0;
            final sectionTotalAmount =
                section['summary']?['sectionTotalAmount'] ?? 0;

            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  setState(() {
                    _selectedSectionIndex = index;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFD95326) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color:
                          isSelected
                              ? const Color(0xFFD95326)
                              : Colors.grey.shade300,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 6,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        section['name'],
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '($activeTableCount / ₹$sectionTotalAmount)',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: isSelected ? Colors.white70 : Colors.black54,
                        ),
                      ),
                      if (_isPrivilegedUser())
                        PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            Icons.more_vert,
                            size: 16,
                            color: isSelected ? Colors.white : Colors.black87,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          onSelected: (value) {
                            if (value == 'edit') {
                              showEditSectionDialog(section);
                            } else if (value == 'delete') {
                              DeleteSectionDialog(context, section);
                            } else if (value == 'all_tables') {
                              setState(() => _tableFilter = 'all');
                            } else if (value == 'running_tables') {
                              setState(() => _tableFilter = 'running');
                            }
                          },
                          itemBuilder:
                              (_) => [
                                _popupItem(
                                  LucideIcons.edit,
                                  "Edit Section",
                                  Colors.blue,
                                  "edit",
                                ),
                                _popupItem(
                                  LucideIcons.trash2,
                                  "Delete Section",
                                  Colors.redAccent,
                                  "delete",
                                ),
                                const PopupMenuDivider(),
                                _popupItem(
                                  LucideIcons.grid,
                                  "All Tables",
                                  _tableFilter == 'all'
                                      ? const Color(0xFF22C55E)
                                      : Colors.grey,
                                  "all_tables",
                                ),
                                _popupItem(
                                  LucideIcons.activity,
                                  "Running Tables",
                                  _tableFilter == 'running'
                                      ? const Color(0xFF22C55E)
                                      : Colors.grey,
                                  "running_tables",
                                ),
                              ],
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        drawer: const Sidebar(),

        appBar: AppBar(
          backgroundColor: const Color(0xFFF5F5F5),
          elevation: 0,
          title: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tables',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Manage restaurant sections and tables',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ),

        body:
            isLoading
                ? Center(
                  child: LoadingAnimationWidget.staggeredDotsWave(
                    color: Colors.black,
                    size: 45,
                  ),
                )
                : hasErrorOccurred
                /// ------------------ ERROR VIEW ------------------
                ? Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    margin: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
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
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              isLoading = true;
                              hasErrorOccurred = false;
                            });
                            fetchSections();
                          },
                          icon: const Icon(
                            LucideIcons.refreshCw,
                            size: 18,
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                /// ------------------ SUCCESS VIEW ------------------
                : Column(
                  children: [
                    // ------------------ SECTION TABS ------------------
                    if (sections.isNotEmpty)
                      Container(
                        height: 80, // 🔥 match content height
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child:
                            kIsWeb
                                ? Scrollbar(
                                  controller: _sectionScrollController,
                                  thumbVisibility: true,
                                  interactive: true,
                                  child: _buildSectionTabs(),
                                )
                                : _buildSectionTabs(), // ✅ No scrollbar on mobile
                      ),

                    // ------------------ ADD BUTTONS ------------------
                    if (_isPrivilegedUser())
                      Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _addButton(
                              label: "Add Section",
                              onTap: showAddSectionDialog,
                            ),
                            SizedBox(width: 16),
                            _addButton(
                              label: "Add Table",
                              onTap: showAddTableDialog,
                            ),
                          ],
                        ),
                      ),

                    // ------------------ CONTENT ------------------
                    Expanded(
                      child:
                          sections.isEmpty
                              ? Center(
                                child: Text(
                                  "No sections available",
                                  style: GoogleFonts.poppins(
                                    color: Colors.grey,
                                    fontSize: 15,
                                  ),
                                ),
                              )
                              : SingleChildScrollView(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: _buildSectionContent(
                                  sections[_selectedSectionIndex],
                                ),
                              ),
                    ),
                  ],
                ),
      ),
    );
  }

  bool _isPrivilegedUser() {
    return userRole == 'Admin' ||
        userRole == 'Manager' ||
        userRole == 'Restaurant Manager' ||
        userRole == 'Owner' ||
        userRole == 'Billing Team' ||
        userRole == 'Acting Restaurant Manager';
  }

  PopupMenuItem<String> _popupItem(icon, text, color, value) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(text, style: GoogleFonts.poppins(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _addButton({required String label, required VoidCallback onTap}) {
    return Expanded(
      child: SizedBox(
        height: 42,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFD95326),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _closeSplitTable(
    BuildContext context,
    Map<String, dynamic> table,
    int tableId,
  ) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Close Split Table', style: GoogleFonts.poppins()),
            backgroundColor: const Color.fromARGB(255, 235, 235, 229),
            content: Text(
              'Are you sure you want to close this split table? This action cannot be undone.',
              style: GoogleFonts.poppins(fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Cancel', style: GoogleFonts.poppins()),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  'Close Split',
                  style: GoogleFonts.poppins(color: Colors.white),
                ),
              ),
            ],
          ),
    );

    if (confirmed != true) return;

    try {
      final response = await http.delete(
        Uri.parse('${dotenv.env['API_URL']}/tables/$tableId/close-split'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        await fetchSections();
        Navigator.pop(context);

        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              'Split table closed successfully!',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            backgroundColor: Colors.green,
          ),
        );

        // Close the dialog
      } else {
        final errorBody =
            response.body.isNotEmpty ? jsonDecode(response.body) : {};
        final errorMessage =
            errorBody['message'] ?? 'Failed to close split table';

        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              errorMessage,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('Error closing split table: $e');
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            'Error occurred while closing split table.',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Add this new method to build the section content
  Widget _buildSectionContent(dynamic section) {
    List<dynamic> tables = List<dynamic>.from(section['tables'] ?? []);

    // ✅ APPLY FILTER HERE - Store the result
    tables = _getFilteredTables(tables);

    // ✅ Show empty state if no tables match filter
    if (tables.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _tableFilter == 'running'
                    ? LucideIcons.activity
                    : LucideIcons.table,
                size: 48,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              Text(
                _tableFilter == 'running'
                    ? 'No running tables'
                    : 'No tables available',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _tableFilter == 'running'
                    ? 'All tables in this section are currently free'
                    : 'Add tables to this section to get started',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: Colors.grey.shade500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Sort tables by display_number
    tables.sort((a, b) {
      final aNum = a['display_number'] ?? a['id'] ?? 0;
      final bNum = b['display_number'] ?? b['id'] ?? 0;
      return (aNum as int).compareTo(bNum as int);
    });

    // Group splits by parent and gather roots
    final Map<int, List<dynamic>> splitsByParent = {};
    final List<dynamic> roots = [];

    for (var t in tables) {
      final parentId = t['parent_table_id'];
      if (parentId == null) {
        roots.add(t);
      } else {
        final pid =
            parentId is int
                ? parentId
                : int.tryParse(parentId?.toString() ?? '');
        if (pid == null) {
          roots.add(t);
        } else {
          splitsByParent.putIfAbsent(pid, () => []).add(t);
        }
      }
    }

    // Build display structure
    final Map<int, int> rootNumberMap = {};
    for (var root in roots) {
      final rootId = root['id'] as int;
      final displayNumber = root['display_number'] ?? root['id'];
      rootNumberMap[rootId] =
          displayNumber is int
              ? displayNumber
              : int.tryParse(displayNumber.toString()) ?? rootId;
    }

    final List<Map<String, dynamic>> orderedTables = [];
    for (var root in roots) {
      final int rootId = root['id'] as int;
      final int rootDisplayNumber = rootNumberMap[rootId]!;

      orderedTables.add({
        'table': root,
        'isSplit': false,
        'rootNumber': rootDisplayNumber,
        'splitIndex': null,
      });

      final children = splitsByParent[rootId] ?? [];
      if (children.isNotEmpty) {
        children.sort((a, b) {
          final sa = (a['split_name'] ?? '').toString();
          final sb = (b['split_name'] ?? '').toString();
          if (sa.isNotEmpty && sb.isNotEmpty) return sa.compareTo(sb);
          final ai =
              a['id'] is int
                  ? a['id'] as int
                  : int.tryParse(a['id']?.toString() ?? '') ?? 0;
          final bi =
              b['id'] is int
                  ? b['id'] as int
                  : int.tryParse(b['id']?.toString() ?? '') ?? 0;
          return ai.compareTo(bi);
        });

        for (var cIndex = 0; cIndex < children.length; cIndex++) {
          final child = children[cIndex];
          orderedTables.add({
            'table': child,
            'isSplit': true,
            'rootNumber': rootDisplayNumber,
            'splitIndex': cIndex,
          });
        }
        splitsByParent.remove(rootId);
      }
    }

    // Handle orphan splits
    if (splitsByParent.isNotEmpty) {
      splitsByParent.values.forEach((list) {
        list.forEach((child) {
          orderedTables.add({
            'table': child,
            'isSplit': true,
            'rootNumber': null,
            'splitIndex': null,
          });
        });
      });
    }

    return Column(
      children: [
        // ✅ OPTIONAL: Show filter indicator badge
        if (_tableFilter == 'running')
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF22C55E).withOpacity(0.3),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      LucideIcons.activity,
                      size: 16,
                      color: Color(0xFF22C55E),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Showing running tables only',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF22C55E),
                      ),
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _tableFilter = 'all';
                    });
                  },
                  child: const Icon(
                    Icons.close,
                    size: 18,
                    color: Color(0xFF22C55E),
                  ),
                ),
              ],
            ),
          ),

        // Legend
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Wrap(
            alignment: WrapAlignment.start,
            spacing: 12,
            runSpacing: 6,
            children: [
              buildLegendItem('Free', Color.fromARGB(255, 116, 200, 169)),
              buildLegendItem('Occupied', Colors.red.shade300),
              buildLegendItem('Reserved', Colors.orange.shade300),
              buildLegendItem('Merged', Colors.blue.shade300),
              buildLegendItem('Settle Up', Color(0xFF8FA31E)),
            ],
          ),
        ),

        // Grid of tables
        LayoutBuilder(
          builder: (context, constraints) {
            bool isLargeScreen = constraints.maxWidth > 600;
            int crossAxisCount = isLargeScreen ? 6 : 4;

            return GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: orderedTables.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1,
              ),
              itemBuilder: (context, visualIndex) {
                final meta = orderedTables[visualIndex];
                final table = meta['table'] as Map<String, dynamic>;
                final bool isSplit = meta['isSplit'] == true;
                final int? rootNumber = meta['rootNumber'] as int?;
                final int? splitIndex = meta['splitIndex'] as int?;

                String status = (table['status'] ?? '').toString();
                String capitalizedStatus =
                    status.isNotEmpty
                        ? status[0].toUpperCase() + status.substring(1)
                        : '';

                Color bgColor;
                switch (status) {
                  case 'settleUp':
                    bgColor = Color(0xFF8FA31E);
                    break;
                  case 'occupied':
                    bgColor = Colors.red.shade300;
                    break;
                  case 'reserved':
                    bgColor = Colors.orange.shade300;
                    break;
                  case 'merged':
                    bgColor = Colors.blue.shade300;
                    break;
                  default:
                    bgColor = const Color.fromARGB(255, 116, 200, 169);
                }

                // Generate display label
                String displayLabel;
                String fullSectionName = section['name'] ?? '';

                // Remove " Sir"
                if (fullSectionName.endsWith(" Sir")) {
                  fullSectionName = fullSectionName.substring(
                    0,
                    fullSectionName.length - 4,
                  );
                }
                if (fullSectionName.endsWith(" sir")) {
                  fullSectionName = fullSectionName.substring(
                    0,
                    fullSectionName.length - 4,
                  );
                }

                // Short name only for UI grid
                String sectionDisplayName =
                    isLargeScreen
                        ? fullSectionName
                        : (fullSectionName.isNotEmpty
                            ? fullSectionName[0].toUpperCase()
                            : '');

                if (!isSplit) {
                  final tableNum =
                      rootNumber ?? table['display_number'] ?? table['id'];

                  displayLabel = "$sectionDisplayName - T$tableNum";
                } else {
                  final splitName = (table['split_name'] ?? '').toString();
                  final tableNum =
                      rootNumber ?? table['display_number'] ?? table['id'];

                  if (splitName.isNotEmpty) {
                    displayLabel =
                        "$sectionDisplayName - T${tableNum}$splitName";
                  } else {
                    displayLabel = "$sectionDisplayName - T$tableNum";
                  }
                }

                int totalAmount =
                    _roundAmount(table['orderAmounts']?['totalAmount']).round();

                return GestureDetector(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder:
                          (dialogContext) => Dialog(
                            insetPadding: const EdgeInsets.all(12),
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  buildTableCard(
                                    table,
                                    visualIndex,
                                    section['name'], // ❌ old
                                    section['id'],
                                    displayLabel,
                                    totalAmount,
                                  ),
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.center,
                                    child: ElevatedButton.icon(
                                      onPressed:
                                          () =>
                                              Navigator.of(dialogContext).pop(),
                                      icon: const Icon(
                                        Icons.close,
                                        color: Colors.black,
                                      ),
                                      label: Text(
                                        "Close",
                                        style: GoogleFonts.poppins(
                                          color: Colors.black,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color.fromARGB(
                                          255,
                                          255,
                                          159,
                                          159,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 30),
                                ],
                              ),
                            ),
                          ),
                    );
                  },
                  child: Card(
                    color: bgColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(6.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            children: [
                              // Table label
                              Text(
                                displayLabel,
                                style: GoogleFonts.poppins(
                                  fontSize: 10.0.sp.clamp(10.0, 14.0),
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: isLargeScreen ? 2 : 1,
                                overflow: TextOverflow.ellipsis,
                              ),

                              // 🔀 Split icon → ONLY on large screens
                              if (isSplit && isLargeScreen)
                                const Padding(
                                  padding: EdgeInsets.only(top: 2),
                                  child: Icon(
                                    Icons.call_split,
                                    size: 12,
                                    color: Colors.white70,
                                  ),
                                ),

                              const SizedBox(height: 4),

                              // Amount
                              Text(
                                '₹${_roundAmount(table['orderAmounts']?['totalAmount']).round()}',
                                style: GoogleFonts.poppins(
                                  fontSize: 9.0.sp.clamp(9.0, 13.0),
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),

                          Text(
                            capitalizedStatus,
                            style: GoogleFonts.poppins(
                              fontSize: kIsWeb ? 14 : 9,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}
