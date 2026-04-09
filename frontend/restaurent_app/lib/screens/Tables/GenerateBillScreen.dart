import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:Neevika/utils/print_service_stub.dart'
    if (dart.library.html) 'package:Neevika/utils/print_service_web.dart'
    as print_service;

class GenerateBillPage extends StatefulWidget {
  /// Only the table ID is strictly required now.
  /// All order/amount data is fetched fresh inside this screen.
  final Map<String, dynamic> table; // kept for backward compat (only .id is used)
  final String userName;
  final String customerName;
  final String customerPhone;
  final double discount;
  final double serviceCharge;
  final double vat;
  final String userId;
  final String paymentMethod;
  final int index;
  final String section;

  const GenerateBillPage({
    super.key,
    required this.table,
    required this.userName,
    required this.customerName,
    required this.customerPhone,
    required this.discount,
    required this.serviceCharge,
    required this.vat,
    required this.paymentMethod,
    required this.index,
    required this.section,
    required this.userId,
  });

  @override
  State<GenerateBillPage> createState() => _GenerateBillPageState();
}

class _GenerateBillPageState extends State<GenerateBillPage> {
  int? billId;

  final TextEditingController foodDiscountController = TextEditingController();
  final TextEditingController drinkDiscountController = TextEditingController();
  TextEditingController cashController = TextEditingController();
  TextEditingController upiController = TextEditingController();
  TextEditingController cardController = TextEditingController();
  bool isLoading = true;
  String captain = '';

  // ─── Fresh table+orders fetched from /tables/all-details/:id ──────────────
  Map<String, dynamic>? tableData;

  // Complimentary
  bool isComplimentary = false;
  String complimentaryRemark = '';
  String complimentaryPassword = '';
  bool isComplimentaryLocked = false;
  bool tableIsComplimentary = false;
  List<Map<String, dynamic>> complimentaryProfiles = [];
  String? selectedProfileId;
  bool isLoadingProfiles = false;

  String foodDiscountType = 'percent';
  String drinkDiscountType = 'percent';
  double food_discount = 0.0;
  double drink_discount = 0.0;
  double foodDiscountAmount = 0.0;
  double drinkDiscountAmount = 0.0;
bool isQRDiscount = false; // true when discount came from lottery_discount_detail

  bool get isDiscountApplied => (food_discount > 0 || drink_discount > 0);

  Map<String, dynamic> get _source => tableData ?? widget.table;

  List<dynamic> get _completeFoodOrders =>
      (_source['orders']?['completeOrders'] as List?) ?? [];

  List<dynamic> get _completeDrinkOrders =>
      (_source['drinksOrders']?['completeDrinksOrders'] as List?) ?? [];

  bool get hasFoodItems => _completeFoodOrders.isNotEmpty;

  bool get hasAlcoholicDrinks =>
      _completeDrinkOrders.any((item) => _isDrinkAlcoholic(item));

  bool _isDrinkAlcoholic(dynamic item) {
    if (item['isAlcoholic'] != null) return item['isAlcoholic'] == true;
    if (item['drink']?['applyVAT'] != null) {
      return item['drink']['applyVAT'].toString().toLowerCase() == 'true';
    }
    if (item['applyVAT'] != null) {
      return item['applyVAT'].toString().toLowerCase() == 'true';
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    fetchTableDetails();
    fetchCaptainName();
  }

  @override
  void dispose() {
    foodDiscountController.dispose();
    drinkDiscountController.dispose();
    super.dispose();
  }

  Future<void> fetchTableDetails() async {
    try {
      final tableId = widget.table['id'];
      if (tableId == null) {
        _fallbackToWidgetTable();
        return;
      }

      final url = '${dotenv.env['API_URL']}/tables/all-details/$tableId';
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        final freshBillId = data['food_bill_id'];
        billId = freshBillId is int
            ? freshBillId
            : int.tryParse(freshBillId?.toString() ?? '');

        _applyStoredDiscounts(data);

        final rawComp = data['isComplimentary'] ??
            data['isCompliemntary'] ??
            data['complimentary'] ??
            false;
        tableIsComplimentary = _toBool(rawComp);
        if (tableIsComplimentary) {
          isComplimentary = true;
          isComplimentaryLocked = true;
          food_discount = 0;
          drink_discount = 0;
          foodDiscountController.text = '0';
          drinkDiscountController.text = '0';
        }

        if (mounted) {
          setState(() {
            tableData = data;
            isLoading = false;
          });
        }

        if (billId != null) fetchBillDetails();
      } else {
        _fallbackToWidgetTable();
      }
    } catch (e) {
      print('❌ Exception in fetchTableDetails: $e');
      _fallbackToWidgetTable();
    }
  }

  void _fallbackToWidgetTable() {
    if (mounted) {
      setState(() {
        tableData = Map<String, dynamic>.from(widget.table);
        billId = widget.table['food_bill_id'] is int
            ? widget.table['food_bill_id'] as int
            : int.tryParse(widget.table['food_bill_id']?.toString() ?? '');
        isLoading = false;
      });
    }
  }

  void _applyStoredDiscounts(Map<String, dynamic> data) {
    final lotteryDiscount = data['lottery_discount_detail'];
    final discountDetails = data['bill_discount_details'];

    final tempSource = data;
    final hasFoodTemp = ((tempSource['orders']?['completeOrders'] as List?) ?? []).isNotEmpty;
    final hasAlcTemp = ((tempSource['drinksOrders']?['completeDrinksOrders'] as List?) ?? [])
        .any((item) => _isDrinkAlcoholic(item));

    if (!hasFoodTemp) {
      food_discount = 0.0;
      foodDiscountController.text = '0';
    }
    if (!hasAlcTemp) {
      drink_discount = 0.0;
      drinkDiscountController.text = '0';
    }

    // AFTER
if (lotteryDiscount != null && lotteryDiscount is Map) {
  final val = (lotteryDiscount['discount'] is num)
      ? (lotteryDiscount['discount'] as num).toDouble()
      : double.tryParse(lotteryDiscount['discount']?.toString() ?? '0') ?? 0.0;
  final type = lotteryDiscount['type']?.toString() ?? 'percent';
  isQRDiscount = true; // ← mark as QR Discount
  if (hasFoodTemp) {
    foodDiscountType = type;
    food_discount = val;
    foodDiscountController.text = val.toString();
  } else if (hasAlcTemp) {
    drinkDiscountType = type;
    drink_discount = val;
    drinkDiscountController.text = val.toString();
  }
} else if (discountDetails != null && discountDetails is Map) {
  isQRDiscount = false; // ← normal discount

      final fd = discountDetails['food'];
      if (fd != null && fd is Map) {
        foodDiscountType = fd['type'] ?? 'percent';
        food_discount = (fd['value'] is num)
            ? (fd['value'] as num).toDouble()
            : double.tryParse(fd['value']?.toString() ?? '0') ?? 0.0;
        foodDiscountController.text = food_discount.toString();
      }
      final dd = discountDetails['drinks'];
      if (dd != null && dd is Map) {
        drinkDiscountType = dd['type'] ?? 'percent';
        drink_discount = (dd['value'] is num)
            ? (dd['value'] as num).toDouble()
            : double.tryParse(dd['value']?.toString() ?? '0') ?? 0.0;
        drinkDiscountController.text = drink_discount.toString();
      }
    }
  }

  Future<void> fetchCaptainName() async {
    try {
      final response = await http.get(
        Uri.parse('${dotenv.env['API_URL']}/auth/user_details/${widget.userId}'),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          setState(() {
            final userDetails = json.decode(response.body);
            captain = (userDetails['name'] ?? '').toString().split(' ').first;
          });
        }
      }
    } catch (e) {
      print('Error fetching captain name: $e');
    }
  }

  Future<void> fetchBillDetails() async {
    if (billId == null) return;
    try {
      final response = await http.get(
        Uri.parse('${dotenv.env['API_URL']}/tables/bills/$billId'),
      );
      if (response.statusCode == 200) {
        final billData = json.decode(response.body);
        final rawComp = billData['complimentary'] ??
            billData['isComplimentary'] ??
            billData['isCompliemntary'] ??
            false;
        final billComplimentary = _toBool(rawComp);
        if (mounted) {
          setState(() {
            isComplimentary = billComplimentary;
            isComplimentaryLocked = billComplimentary;
            if (isComplimentary) {
              complimentaryRemark = billData['complimentary_remark'] ?? '';
              foodDiscountController.text = '0';
              food_discount = 0;
            }
          });
        }
      }
    } catch (e) {
      print('Error fetching bill details: $e');
    }
  }

  Future<void> fetchComplimentaryProfiles() async {
    setState(() => isLoadingProfiles = true);
    try {
      final response = await http.get(
        Uri.parse('${dotenv.env['API_URL']}/complimentaryProfiles'),
      );
      if (response.statusCode == 200) {
        final dynamic responseData = json.decode(response.body);
        List<dynamic> data;
        if (responseData is List) {
          data = responseData;
        } else if (responseData is Map && responseData['data'] != null) {
          data = responseData['data'] as List;
        } else {
          data = [];
        }
        if (mounted) {
          setState(() {
            complimentaryProfiles = data.map((p) => {
              'id': p['id'].toString(),
              'name': p['name']?.toString() ?? 'Unknown',
            }).toList();
            isLoadingProfiles = false;
          });
        }
      } else {
        if (mounted) setState(() => isLoadingProfiles = false);
      }
    } catch (e) {
      print('Error fetching complimentary profiles: $e');
      if (mounted) setState(() => isLoadingProfiles = false);
    }
  }

  Map<String, Map<String, dynamic>> _groupItems(
    List<dynamic> items,
    String type,
  ) {
    final Map<String, Map<String, dynamic>> grouped = {};

    for (var item in items) {
      try {
        String name;
        double price = 0.0;
        int qty;
        bool isAlcoholic = false;

        if (type == 'food') {
          name = item['is_custom'] == true
              ? (item['note'] ?? item['item_desc'] ?? 'Custom Item')
              : (item['menu']?['name'] ?? item['item_desc'] ?? 'Unknown');
          qty = (item['quantity'] as num?)?.toInt() ?? 1;

          if (item['menu']?['price'] is num) {
            price = (item['menu']['price'] as num).toDouble();
          } else if (item['amount'] is num && qty > 0) {
            price = double.parse(
                ((item['amount'] as num).toDouble() / qty).toStringAsFixed(2));
          }
        } else {
          if (item['isAlcoholic'] != null) {
            isAlcoholic = item['isAlcoholic'] == true;
          } else if (item['drink']?['applyVAT'] != null) {
            isAlcoholic = item['drink']['applyVAT'].toString() == 'true';
          } else if (item['drink']?['applyVat'] != null) {
            isAlcoholic = item['drink']['applyVat'].toString() == 'true';
          } else if (item['applyVat'] != null) {
            isAlcoholic = item['applyVat'].toString() == 'true';
          } else if (item['applyVAT'] != null) {
            isAlcoholic = item['applyVAT'].toString() == 'true';
          }

          name = item['is_custom'] == true
              ? (item['note'] ?? item['item_desc'] ?? 'Custom Drink')
              : (item['drink']?['name'] ?? item['item_desc'] ?? 'Unknown');
          qty = (item['quantity'] as num?)?.toInt() ?? 1;

          if (item['drink']?['price'] is num) {
            price = (item['drink']['price'] as num).toDouble();
          } else if (item['amount'] is num && qty > 0) {
            price = double.parse(
                ((item['amount'] as num).toDouble() / qty).toStringAsFixed(2));
          }
        }

        final totalAmount = double.parse((price * qty).toStringAsFixed(2));

        if (grouped.containsKey(name)) {
          grouped[name]!['qty'] += qty;
          grouped[name]!['totalAmount'] =
              (grouped[name]!['qty'] as int) * price;
        } else {
          String finalType = type;
          if (type == 'drink' && !isAlcoholic) finalType = 'food';

          grouped[name] = {
            'name': name,
            'price': price,
            'qty': qty,
            'totalAmount': totalAmount,
            'type': finalType,
            'isAlcoholic': isAlcoholic,
            'originalType': type,
          };
        }
      } catch (e) {
        print('❌ Error in _groupItems: $e  item=$item');
      }
    }
    return grouped;
  }

  bool _toBool(dynamic raw) {
    if (raw == null) return false;
    if (raw is bool) return raw;
    if (raw is num) return raw == 1;
    if (raw is String) {
      final l = raw.trim().toLowerCase();
      return l == 'true' || l == '1' || l == 'yes';
    }
    return false;
  }

  _BillCalc _compute() {
    final groupedFood = _groupItems(_completeFoodOrders, 'food');
    final groupedDrink = _groupItems(_completeDrinkOrders, 'drink');

    final List<Map<String, dynamic>> alcoholicDrinks = [];
    final List<Map<String, dynamic>> nonAlcoholicDrinks = [];
    final List<Map<String, dynamic>> foodItems = groupedFood.values.toList();

    for (final d in groupedDrink.values) {
      if (d['isAlcoholic'] == true) {
        alcoholicDrinks.add(d);
      } else {
        nonAlcoholicDrinks.add(Map<String, dynamic>.from(d)..['type'] = 'food');
      }
    }

    final cgstItems = [...foodItems, ...nonAlcoholicDrinks];
    final combinedItems = [...cgstItems, ...alcoholicDrinks];

    double actualFoodTotal =
        foodItems.fold(0.0, (s, i) => s + (i['totalAmount'] as double));
    double nonAlcoholicTotal =
        nonAlcoholicDrinks.fold(0.0, (s, i) => s + (i['totalAmount'] as double));
    double alcoholicTotal =
        alcoholicDrinks.fold(0.0, (s, i) => s + (i['totalAmount'] as double));
    double combinedSubTotal = actualFoodTotal + nonAlcoholicTotal + alcoholicTotal;

    if (foodDiscountType == 'percent') {
      foodDiscountAmount = actualFoodTotal * (food_discount / 100);
    } else {
      foodDiscountAmount = food_discount.clamp(0, actualFoodTotal);
    }

    if (drinkDiscountType == 'percent') {
      drinkDiscountAmount = alcoholicTotal * (drink_discount / 100);
    } else {
      drinkDiscountAmount = drink_discount.clamp(0, alcoholicTotal);
    }

    final discountAmount = foodDiscountAmount + drinkDiscountAmount;
    final subtotalAfterDiscount = combinedSubTotal - discountAmount;

    final foodAfterDiscount = actualFoodTotal - foodDiscountAmount;
    final alcoholicAfterDiscount = alcoholicTotal - drinkDiscountAmount;
    final cgstSgstBase = foodAfterDiscount + nonAlcoholicTotal;

    final cgst = cgstSgstBase * 0.025;
    final sgst = cgstSgstBase * 0.025;
    final vatAmount = alcoholicAfterDiscount * 0.10;
    final serviceChargeAmount =
        subtotalAfterDiscount * (widget.serviceCharge / 100);

    final totalAmount =
        subtotalAfterDiscount + serviceChargeAmount + cgst + sgst + vatAmount;
    final grandTotalRounded = totalAmount.roundToDouble();
    final roundOffAmount = grandTotalRounded - totalAmount;

    return _BillCalc(
      combinedItems: combinedItems,
      foodItems: foodItems,
      nonAlcoholicDrinks: nonAlcoholicDrinks,
      alcoholicDrinks: alcoholicDrinks,
      actualFoodTotal: actualFoodTotal,
      nonAlcoholicTotal: nonAlcoholicTotal,
      alcoholicTotal: alcoholicTotal,
      combinedSubTotal: combinedSubTotal,
      discountAmount: discountAmount,
      subtotalAfterDiscount: subtotalAfterDiscount,
      cgst: cgst,
      sgst: sgst,
      vatAmount: vatAmount,
      serviceChargeAmount: serviceChargeAmount,
      grandTotalRounded: grandTotalRounded,
      roundOffAmount: roundOffAmount,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        appBar: AppBar(
          title: Text('Generate Bill',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          backgroundColor: Colors.white,
          elevation: 1,
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.black87),
        ),
        body: Center(
          child: LoadingAnimationWidget.staggeredDotsWave(
            color: Colors.black,
            size: 40,
          ),
        ),
      );
    }

    final calc = _compute();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: Text(
          'Generate Bill',
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600, color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _buildImprovedBillCard(context, calc),
            ),
          ),
          Container(
            width: 380,
            color: Colors.white,
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildDiscountCard(),
                        const SizedBox(height: 16),
                        _buildComplimentaryCard(),
                        const SizedBox(height: 16),
                        _buildSummaryCard(calc),
                        const SizedBox(height: 20),
                        _buildActionButtons(calc),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscountCard() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: (isComplimentary || isComplimentaryLocked)
          ? Colors.grey.shade100
          : Colors.white,
      child: AbsorbPointer(
        absorbing: isComplimentary || isComplimentaryLocked,
        child: Opacity(
          opacity: (isComplimentary || isComplimentaryLocked) ? 0.6 : 1.0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.discount, color: Colors.orange.shade600, size: 18),
                  const SizedBox(width: 8),
                  Text('Adjust Discount',
                      style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade800)),
                ]),
                const SizedBox(height: 16),
                _buildDiscountSection(
                  label: 'Food Discount',
                  enabled: hasFoodItems,
                  type: foodDiscountType,
                  controller: foodDiscountController,
                  onTypeChanged: (v) => setState(() => foodDiscountType = v!),
                  onValueChanged: (v) =>
                      setState(() => food_discount = double.tryParse(v) ?? 0.0),
                  disabledNote: '(No food items)',
                ),
                const SizedBox(height: 16),
                _buildDiscountSection(
                  label: 'Drink Discount',
                  enabled: hasAlcoholicDrinks,
                  type: drinkDiscountType,
                  controller: drinkDiscountController,
                  onTypeChanged: (v) => setState(() => drinkDiscountType = v!),
                  onValueChanged: (v) =>
                      setState(() => drink_discount = double.tryParse(v) ?? 0.0),
                  disabledNote: '(Alcoholic drinks only)',
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total Discount:',
                          style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.orange.shade800)),
                      Text(
                        '₹${(foodDiscountAmount + drinkDiscountAmount).toStringAsFixed(2)}',
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade800),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDiscountSection({
    required String label,
    required bool enabled,
    required String type,
    required TextEditingController controller,
    required ValueChanged<String?> onTypeChanged,
    required ValueChanged<String> onValueChanged,
    required String disabledNote,
  }) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: AbsorbPointer(
        absorbing: !enabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(label,
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.teal.shade700)),
              if (!enabled) ...[
                const SizedBox(width: 8),
                Text(disabledNote,
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: Colors.grey.shade500)),
              ]
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: type,
                  items: const [
                    DropdownMenuItem(value: 'percent', child: Text('Percentage')),
                    DropdownMenuItem(value: 'flat', child: Text('Flat Amount')),
                  ],
                  onChanged: enabled ? onTypeChanged : null,
                  decoration: InputDecoration(
                    labelText: 'Type',
                    labelStyle:
                        GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade700),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  style: GoogleFonts.poppins(fontSize: 14, color: Colors.black),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: type == 'percent' ? 'Value (%)' : 'Value (₹)',
                    labelStyle:
                        GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade700),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    prefixIcon: Icon(
                      type == 'percent' ? Icons.percent : Icons.currency_rupee,
                      color: Colors.teal.shade600,
                      size: 20,
                    ),
                  ),
                  style: GoogleFonts.poppins(fontSize: 14, color: Colors.black),
                  onChanged: onValueChanged,
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildComplimentaryCard() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: (isComplimentaryLocked || isDiscountApplied)
          ? Colors.grey.shade100
          : Colors.white,
      child: AbsorbPointer(
        absorbing: isComplimentaryLocked || isDiscountApplied,
        child: Opacity(
          opacity: (isComplimentaryLocked || isDiscountApplied) ? 0.6 : 1.0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.card_giftcard, color: Colors.red.shade600, size: 18),
                  const SizedBox(width: 8),
                  Text('Special Options',
                      style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade800)),
                ]),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: isComplimentary,
                  onChanged: (v) {
                    if (v == true) {
                      setState(() {
                        isComplimentary = true;
                        food_discount = 0;
                        drink_discount = 0;
                        foodDiscountController.text = '0';
                        drinkDiscountController.text = '0';
                      });
                      _showComplimentaryDialog();
                    } else {
                      setState(() {
                        isComplimentary = false;
                        complimentaryRemark = '';
                        complimentaryPassword = '';
                        selectedProfileId = null;
                      });
                    }
                  },
                  title: Text('Complimentary Bill',
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: (isComplimentaryLocked || isComplimentary)
                              ? Colors.grey.shade500
                              : Colors.red.shade700)),
                  subtitle: isComplimentary && complimentaryRemark.isNotEmpty
                      ? Text('Reason: $complimentaryRemark',
                          style: GoogleFonts.poppins(
                              fontSize: 12, color: Colors.grey.shade600))
                      : isComplimentaryLocked
                          ? Text('Already set as complimentary',
                              style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                  fontStyle: FontStyle.italic))
                          : null,
                  activeColor: Colors.red.shade600,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(_BillCalc calc) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.receipt, color: Colors.blue.shade600, size: 18),
              const SizedBox(width: 8),
              Text('Bill Summary',
                  style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800)),
            ]),
            const SizedBox(height: 12),
            _buildSummaryItem('Food Total',
                calc.actualFoodTotal + calc.nonAlcoholicTotal,
                color: Colors.teal),
            _buildSummaryItem('Drinks Total', calc.alcoholicTotal,
                color: Colors.deepPurple),
            _buildSummaryItem('Subtotal', calc.combinedSubTotal),
            // AFTER
if (foodDiscountAmount > 0)
  _buildSummaryItem(
      isQRDiscount
          ? 'QR Discount (${foodDiscountType == 'percent' ? '${food_discount.toStringAsFixed(2)}%' : '₹${food_discount.toStringAsFixed(2)}'})'
          : foodDiscountType == 'percent'
              ? 'Food Discount (${food_discount.toStringAsFixed(2)}%)'
              : 'Food Discount (₹${food_discount.toStringAsFixed(2)})',
      -foodDiscountAmount,
      color: Colors.orange),
if (drinkDiscountAmount > 0)
  _buildSummaryItem(
      isQRDiscount
          ? 'QR Discount - Drinks (${drinkDiscountType == 'percent' ? '${drink_discount.toStringAsFixed(2)}%' : '₹${drink_discount.toStringAsFixed(2)}'})'
          : drinkDiscountType == 'percent'
              ? 'Drink Discount (${drink_discount.toStringAsFixed(2)}%)'
              : 'Drink Discount (₹${drink_discount.toStringAsFixed(2)})',
      -drinkDiscountAmount,
      color: Colors.deepOrange),
            if (calc.serviceChargeAmount > 0)
              _buildSummaryItem('Service Charge', calc.serviceChargeAmount),
            if (calc.cgst > 0) _buildSummaryItem('CGST @ 2.5% (incl.)', calc.cgst),
            if (calc.sgst > 0) _buildSummaryItem('SGST @ 2.5% (incl.)', calc.sgst),
            if (calc.vatAmount > 0)
              _buildSummaryItem('VAT @ 10% (incl.)', calc.vatAmount),
            if (calc.roundOffAmount != 0)
              _buildSummaryItem('Round Off', calc.roundOffAmount),
            const Divider(height: 20, thickness: 2),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color:
                    isComplimentary ? Colors.red.shade50 : Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: isComplimentary
                        ? Colors.red.shade300
                        : Colors.green.shade300,
                    width: 2),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(isComplimentary ? 'COMPLIMENTARY' : 'GRAND TOTAL',
                      style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isComplimentary
                              ? Colors.red.shade800
                              : Colors.green.shade800)),
                  Text(
                    isComplimentary
                        ? '₹0.00'
                        : '₹${calc.grandTotalRounded.toStringAsFixed(2)}',
                    style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isComplimentary
                            ? Colors.red.shade800
                            : Colors.green.shade800),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(_BillCalc calc) {
    return Column(
      children: [
        ElevatedButton.icon(
          onPressed: () => _generateBill(calc),
          icon: const Icon(Icons.receipt_long, size: 18),
          label: Text('Generate Bill',
              style: GoogleFonts.poppins(
                  fontSize: 15, fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue.shade600,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 48),
            elevation: 3,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: billId != null
              ? () {
                  if (isComplimentary) {
                    _settleUpBill(context, 0, {'complimentary': 0});
                  } else {
                    _showPaymentDialog(
                        context, calc.grandTotalRounded.toInt());
                  }
                }
              : null,
          icon: Icon(
            billId != null
                ? (isComplimentary ? Icons.card_giftcard : Icons.check_circle)
                : Icons.lock,
            size: 18,
          ),
          label: Text(
            billId != null
                ? (isComplimentary ? 'Settle Complimentary' : 'Settle Bill')
                : 'Generate Bill First',
            style:
                GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: billId != null
                ? (isComplimentary
                    ? Colors.red.shade600
                    : Colors.green.shade600)
                : Colors.grey.shade400,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 48),
            elevation: billId != null ? 3 : 1,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _buildImprovedBillCard(BuildContext context, _BillCalc calc) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isComplimentary
                  ? Colors.red.shade600
                  : Colors.teal.shade600,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(
                    isComplimentary
                        ? Icons.card_giftcard
                        : Icons.receipt_long,
                    color: Colors.white,
                    size: 24),
                const SizedBox(width: 12),
                Text(
                    isComplimentary
                        ? 'Complimentary Bill Preview'
                        : 'Bill Preview',
                    style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('Table ${widget.index + 1}',
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Order Items',
                    style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade800)),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    Expanded(
                        flex: 3,
                        child: Text('Item',
                            style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700))),
                    Expanded(
                        child: Text('Qty',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700))),
                    Expanded(
                        child: Text('Price',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700))),
                    Expanded(
                        child: Text('Total',
                            textAlign: TextAlign.right,
                            style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700))),
                  ]),
                ),
                const SizedBox(height: 8),
                if (calc.combinedItems
                    .where((i) => i['type'] == 'food')
                    .isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 8, horizontal: 16),
                    decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(
                      'Food & Beverages (CGST+SGST @2.5% each incl. — '
                      '₹${(calc.actualFoodTotal + calc.nonAlcoholicTotal).toStringAsFixed(2)})',
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange.shade800),
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...calc.combinedItems
                      .where((i) => i['type'] == 'food')
                      .map((i) => _buildItemRow(i, Colors.orange)),
                  const SizedBox(height: 8),
                ],
                if (calc.combinedItems
                    .where((i) => i['type'] == 'drink')
                    .isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 8, horizontal: 16),
                    decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(
                      'Alcoholic Beverages (VAT @ 10% incl. — '
                      '₹${calc.alcoholicTotal.toStringAsFixed(2)})',
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade800),
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...calc.combinedItems
                      .where((i) => i['type'] == 'drink')
                      .map((i) => _buildItemRow(i, Colors.blue)),
                ],
                const SizedBox(height: 16),
                const Divider(thickness: 2),
                const SizedBox(height: 8),
                _buildSummaryRow(
                    'Food Total',
                    calc.actualFoodTotal + calc.nonAlcoholicTotal),
                _buildSummaryRow('Drinks Total', calc.alcoholicTotal),
                const Divider(thickness: 1),
                _buildSummaryRow('Subtotal', calc.combinedSubTotal),
                // AFTER
if (foodDiscountAmount > 0)
  _buildSummaryRow(
      isQRDiscount
          ? 'QR Discount (${foodDiscountType == 'percent' ? '${food_discount.toStringAsFixed(2)}%' : '₹${food_discount.toStringAsFixed(2)}'})'
          : foodDiscountType == 'percent'
              ? 'Food Discount (${food_discount.toStringAsFixed(2)}%)'
              : 'Food Discount (₹${food_discount.toStringAsFixed(2)})',
      -foodDiscountAmount),
if (drinkDiscountAmount > 0)
  _buildSummaryRow(
      isQRDiscount
          ? 'QR Discount - Drinks (${drinkDiscountType == 'percent' ? '${drink_discount.toStringAsFixed(2)}%' : '₹${drink_discount.toStringAsFixed(2)}'})'
          : drinkDiscountType == 'percent'
              ? 'Drink Discount (${drink_discount.toStringAsFixed(2)}%)'
              : 'Drink Discount (₹${drink_discount.toStringAsFixed(2)})',
      -drinkDiscountAmount),
                if (calc.serviceChargeAmount > 0)
                  _buildSummaryRow(
                      'Service (${widget.serviceCharge.toStringAsFixed(1)}%)',
                      calc.serviceChargeAmount),
                if (calc.cgst > 0)
                  _buildSummaryRow('CGST @ 2.5%', calc.cgst),
                if (calc.sgst > 0)
                  _buildSummaryRow('SGST @ 2.5%', calc.sgst),
                if (calc.vatAmount > 0)
                  _buildSummaryRow('VAT @ 10%', calc.vatAmount),
                if (calc.roundOffAmount != 0)
                  _buildSummaryRow('Round Off', calc.roundOffAmount),
                const SizedBox(height: 12),
                const Divider(thickness: 2),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isComplimentary
                        ? Colors.red.shade50
                        : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: isComplimentary
                            ? Colors.red.shade300
                            : Colors.green.shade300,
                        width: 2),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                          isComplimentary
                              ? 'COMPLIMENTARY BILL'
                              : 'GRAND TOTAL',
                          style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isComplimentary
                                  ? Colors.red.shade800
                                  : Colors.green.shade800)),
                      Text(
                          isComplimentary
                              ? '₹0.00'
                              : '₹${calc.grandTotalRounded.toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: isComplimentary
                                  ? Colors.red.shade800
                                  : Colors.green.shade800)),
                    ],
                  ),
                ),
                if (isComplimentary && complimentaryRemark.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.yellow.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.yellow.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Complimentary Reason:',
                            style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange.shade800)),
                        const SizedBox(height: 4),
                        Text(complimentaryRemark,
                            style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: Colors.orange.shade700)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemRow(Map<String, dynamic> item, Color color) {
    final name = item['name'];
    final qty = item['qty'];
    final price = (item['price'] as double?) ?? 0.0;
    final total = (item['totalAmount'] as double?) ?? price * qty;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Colors.yellow.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.yellow.shade200),
      ),
      child: Row(
        children: [
          Expanded(
              flex: 3,
              child: Row(children: [
                Icon(
                    item['originalType'] == 'drink'
                        ? Icons.local_drink
                        : Icons.restaurant,
                    size: 16,
                    color: Colors.blue.shade600),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(name,
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade800),
                        overflow: TextOverflow.ellipsis)),
              ])),
          Expanded(
              child: Text('$qty',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 14, color: Colors.grey.shade700))),
          Expanded(
              child: Text('₹${price.toStringAsFixed(2)}',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 14, color: Colors.grey.shade700))),
          Expanded(
              child: Text('₹${total.toStringAsFixed(2)}',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800))),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, double value,
      {bool isTotal = false}) {
    value = double.parse(value.toStringAsFixed(2));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: GoogleFonts.poppins(
                  fontSize: isTotal ? 16 : 14,
                  fontWeight:
                      isTotal ? FontWeight.w600 : FontWeight.w400)),
          Text('₹${value.toStringAsFixed(2)}',
              style: GoogleFonts.poppins(
                  fontSize: isTotal ? 16 : 14,
                  fontWeight:
                      isTotal ? FontWeight.bold : FontWeight.normal,
                  color: isTotal ? Colors.green[800] : Colors.grey[900])),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, double value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: Colors.grey.shade700)),
          Text('₹${value.toStringAsFixed(2)}',
              style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: color ?? Colors.grey.shade800)),
        ],
      ),
    );
  }

  // ─── Generate Bill ─────────────────────────────────────────────────────────
  Future<void> _generateBill(_BillCalc calc) async {
    try {
      final hasItems = _completeFoodOrders.isNotEmpty ||
          _completeDrinkOrders.isNotEmpty;

      if (!hasItems) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No completed items to bill.')));
        return;
      }

      setState(() => isLoading = true);

      final foodAfterDiscount = calc.actualFoodTotal - foodDiscountAmount;
      final alcoholicAfterDiscount = calc.alcoholicTotal - drinkDiscountAmount;
      final cgstSgstBase = foodAfterDiscount + calc.nonAlcoholicTotal;

      final discountData = {
        'food': {
          'type': foodDiscountType,
          'value': food_discount,
          'amount': foodDiscountAmount.toStringAsFixed(2),
        },
        'drinks': {
          'type': drinkDiscountType,
          'value': drink_discount,
          'amount': drinkDiscountAmount.toStringAsFixed(2),
        },
        'total': (foodDiscountAmount + drinkDiscountAmount).toStringAsFixed(2),
        'hasDiscount': isDiscountApplied,
      };

      final body = jsonEncode({
        'customer_name': 'abc',
        'customer_phoneNumber': '123',
        'discount': discountData,
        'userId': widget.userId,
        'serviceCharge': widget.serviceCharge,
        'vat': calc.vatAmount.toStringAsFixed(2),
        'cgst': calc.cgst.toStringAsFixed(2),
        'sgst': calc.sgst.toStringAsFixed(2),
        'roundOff': calc.roundOffAmount.toStringAsFixed(2),
        'payment_method': 'cash',
        'user_id': 2,
        'complimentary_remark': complimentaryRemark,
        'complimentary_password': complimentaryPassword,
        'isComplimentary': isComplimentary,
        'complimentary_profile_id': selectedProfileId,
      });

      final tableId = _source['id'];
      Uri url;
      http.Response response;

      if (billId != null) {
        url = Uri.parse('${dotenv.env['API_URL']}/tables/bills/update/$billId');
        response = await http.put(url,
            headers: {'Content-Type': 'application/json'}, body: body);
      } else {
        url = Uri.parse('${dotenv.env['API_URL']}/tables/$tableId/bill');
        response = await http.post(url,
            headers: {'Content-Type': 'application/json'}, body: body);
      }

      setState(() => isLoading = false);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        setState(() {
          billId = data['data']?['bill_id'] ?? data['bill_id'];
        });

        await fetchTableDetails();

        if (!hasItems) return;

        final bool hasFood = _completeFoodOrders.isNotEmpty;
        final bool hasDrinks = _completeDrinkOrders.isNotEmpty;

        if (hasFood && !hasDrinks) {
          print_service.triggerPrintWindow(_buildFoodBillHtml(billId!));
          return;
        }
        if (!hasFood && hasDrinks) {
          print_service.triggerPrintWindow(_buildDrinksBillHtml(billId!));
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(isComplimentary
                ? 'Complimentary bill generated!'
                : 'Bill generated!')));

        final selectedBillType = await showDialog<String>(
          context: context,
          builder: (context) => Dialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.receipt_long, size: 50, color: Color(0xFF3E2723)),
                  const SizedBox(height: 10),
                  const Text('Select Bill Type',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF3E2723))),
                  const SizedBox(height: 8),
                  const Text('Choose which bill you want to print',
                      style: TextStyle(fontSize: 16, color: Colors.black54),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 25),
                  _buildBillTypeButton(
                      icon: Icons.restaurant_menu,
                      label: 'Food Bill',
                      color: Colors.deepOrangeAccent,
                      onTap: () => Navigator.pop(context, 'food')),
                  const SizedBox(height: 15),
                  _buildBillTypeButton(
                      icon: Icons.local_bar,
                      label: 'Drinks Bill',
                      color: Colors.blueAccent,
                      onTap: () => Navigator.pop(context, 'drinks')),
                  const SizedBox(height: 15),
                  _buildBillTypeButton(
                      icon: Icons.receipt,
                      label: 'Combined Bill',
                      color: Colors.teal,
                      onTap: () => Navigator.pop(context, 'combined')),
                  const SizedBox(height: 25),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel',
                        style: TextStyle(
                            fontSize: 16,
                            color: Colors.redAccent,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
        );

        if (selectedBillType == null) return;
        final html = selectedBillType == 'food'
            ? _buildFoodBillHtml(billId!)
            : selectedBillType == 'drinks'
                ? _buildDrinksBillHtml(billId!)
                : _buildCombinedBillHtml(billId!);
        print_service.triggerPrintWindow(html);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error generating bill')));
      }
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Widget _buildBillTypeButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.5)),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 5, offset: Offset(0, 3))
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 10),
              Text(label,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: color)),
            ],
          ),
        ),
      ),
    );
  }

  // ─── HTML Bill Builders ────────────────────────────────────────────────────
  String get _line => '_________________________________';
  String get _footer => '''
    <pre style="font-size:22px;text-align:center;margin:0;padding:0;line-height:1;">$_line</pre>
    <div style="text-align:center;">
      <strong>Thank you for dining with us!</strong><br>
      <span>GSTIN: 27AAJFF0784D1ZH | VAT TIN: 27162432717V | FSSAI: 11524022000259</span><br>
      <strong>Unit of Fortune Hospitality</strong>
    </div>
  ''';

  String _headerHtml(int billId) => '''
    <div style="text-align:center;">
      <strong style="font-size:30px;">5K Family Resto & Bar</strong><br>
      <span style="font-size:20px;">Opp: Nayara Petrol Pump, Near Green Leaf Hotel, Nevali, 421503</span><br>
    </div>
    <pre style="font-size:22px;text-align:center;">$_line</pre>
    <table style="width:100%;font-size:21px;">
      <tr>
        <td>Date: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}</td>
        <td style="text-align:right;">Time: ${DateFormat('hh:mm a').format(DateTime.now())}</td>
      </tr>
      <tr>
        <td>Cashier: ${widget.userName}</td>
        <td style="text-align:right;">Bill No.: $billId</td>
      </tr>
      <tr>
        <td>Captain: $captain</td>
        <td style="text-align:right;">Table: ${widget.section}-${widget.index + 1}</td>
      </tr>
    </table>
    <pre style="font-size:22px;text-align:center;">$_line</pre>
  ''';

  // ── FIX: complimentary banner now also appears at the TOP of the bill ──────
  String _complimentaryBannerHtml() {
    if (!isComplimentary) return '';
    return '''
      <div style="text-align:center;font-size:26px;font-weight:bold;
                  color:#cc0000;border:2px solid #cc0000;padding:6px;
                  margin-bottom:8px;">
        *** COMPLIMENTARY BILL ***
      </div>
      ${complimentaryRemark.isNotEmpty ? '<div style="text-align:center;font-size:21px;margin-bottom:8px;">Reason: $complimentaryRemark</div>' : ''}
    ''';
  }

  // Kept for backward compat (used at the bottom of bill too)
  String _complimentaryHtml() {
    if (!isComplimentary || complimentaryRemark.isEmpty) return '';
    return '''
      <pre style="font-size:24px;text-align:center;margin:4px 0;">$_line</pre>
      <div style="text-align:center;font-size:24px;font-weight:bold;">*** COMPLIMENTARY BILL ***</div>
      <div style="text-align:center;font-size:21px;margin-top:8px;">Reason: $complimentaryRemark</div>
    ''';
  }

  // ── FIX 1 & 2: taxes added to grand total; complimentary shows ₹0 ──────────
  String _buildFoodBillHtml(int billId) {
    final foodItems = _completeFoodOrders;
    final drinkItems = _completeDrinkOrders
        .where((i) => !_isDrinkAlcoholic(i))
        .toList();

    final gFood = _groupItems(foodItems, 'food');
    final gNonAlc = _groupItems(drinkItems, 'drink');

    final foodRows = _buildItemRows(gFood.values);
    final drinkRows = _buildItemRows(gNonAlc.values);

    final foodTotal =
        gFood.values.fold(0.0, (s, i) => s + (i['totalAmount'] as double));
    final nonAlcTotal =
        gNonAlc.values.fold(0.0, (s, i) => s + (i['totalAmount'] as double));
    final subtotal = foodTotal + nonAlcTotal;

    double discAmt = foodDiscountType == 'percent'
        ? foodTotal * (food_discount / 100)
        : food_discount.clamp(0, foodTotal);
    final foodAfterDiscount = foodTotal - discAmt;
    final cgstBase = foodAfterDiscount + nonAlcTotal;
    final cgst = cgstBase * 0.025;
    final sgst = cgstBase * 0.025;
    final afterDiscount = subtotal - discAmt;

    // ── FIX 1: include CGST + SGST in the final total ──────────────────────
    final total = afterDiscount + cgst + sgst;
    final rounded = isComplimentary ? 0.0 : total.roundToDouble();
    final roundOff = isComplimentary ? 0.0 : (rounded - total);

    final totalItems = gFood.values.fold(0, (s, i) => s + (i['qty'] as int)) +
        gNonAlc.values.fold(0, (s, i) => s + (i['qty'] as int));

    return '''
    <div style="font-family:Calibri,Arial,sans-serif;width:100%;font-size:22px;">
      ${_headerHtml(billId)}
      ${_complimentaryBannerHtml()}
      <table style="width:100%;border-collapse:collapse;font-size:21px;">
        <tr><th style="text-align:left;">Item</th><th>Qty</th><th>Price</th><th style="text-align:right;">Amt</th></tr>
        ${gFood.isNotEmpty ? '<tr><td colspan="4" style="font-weight:bold;">Food &amp; Non-Alcoholic</td></tr>$foodRows' : ''}
        ${drinkRows.isNotEmpty ? drinkRows : ''}
      </table>
      <pre style="font-size:22px;text-align:center;">$_line</pre>
      <table style="width:100%;font-size:21px;">
        <tr><td>Total Qty:</td><td style="text-align:right;">$totalItems</td></tr>
        <tr><td>Subtotal:</td><td style="text-align:right;">₹${subtotal.toStringAsFixed(2)}</td></tr>
${discAmt > 0 ? '<tr><td>${isQRDiscount ? 'QR Discount' : 'Food Discount'} (${foodDiscountType == 'percent' ? '${food_discount}%' : '₹${food_discount}'})</td><td style="text-align:right;">-₹${discAmt.toStringAsFixed(2)}</td></tr>' : ''}
        <tr><td>CGST (₹${cgstBase.toStringAsFixed(2)}) @2.5%</td><td style="text-align:right;">₹${cgst.toStringAsFixed(2)}</td></tr>
        <tr><td>SGST (₹${cgstBase.toStringAsFixed(2)}) @2.5%</td><td style="text-align:right;">₹${sgst.toStringAsFixed(2)}</td></tr>
        <tr><td>Round Off</td><td style="text-align:right;">₹${roundOff.toStringAsFixed(2)}</td></tr>
        <tr style="font-weight:bold;font-size:23px;">
          <td>${isComplimentary ? 'COMPLIMENTARY TOTAL:' : 'GRAND TOTAL:'}</td>
          <td style="text-align:right;">₹${rounded.toStringAsFixed(2)}</td>
        </tr>
      </table>
      ${_complimentaryHtml()}
      $_footer
    </div>''';
  }

  // ── FIX 1 & 2: taxes added to grand total; complimentary shows ₹0 ──────────
  String _buildDrinksBillHtml(int billId) {
    final alc = _completeDrinkOrders.where((i) => _isDrinkAlcoholic(i)).toList();
    final nonAlc =
        _completeDrinkOrders.where((i) => !_isDrinkAlcoholic(i)).toList();

    final gAlc = _groupItems(alc, 'drink');
    final gNonAlc = _groupItems(nonAlc, 'drink');

    final alcRows = _buildItemRows(gAlc.values);
    final nonAlcRows = _buildItemRows(gNonAlc.values);

    final alcTotal =
        gAlc.values.fold(0.0, (s, i) => s + (i['totalAmount'] as double));
    final nonAlcTotal =
        gNonAlc.values.fold(0.0, (s, i) => s + (i['totalAmount'] as double));
    final subtotal = alcTotal + nonAlcTotal;

    double drinkDiscAmt = drinkDiscountType == 'percent'
        ? alcTotal * (drink_discount / 100)
        : drink_discount.clamp(0, alcTotal);
    final alcAfterDiscount = alcTotal - drinkDiscAmt;
    final vat = alcAfterDiscount * 0.10;
    final cgst = nonAlcTotal * 0.025;
    final sgst = nonAlcTotal * 0.025;

    // ── FIX 1: include VAT + CGST + SGST in the final total ────────────────
    final total = alcAfterDiscount + nonAlcTotal + vat + cgst + sgst;
    final rounded = isComplimentary ? 0.0 : total.roundToDouble();
    final roundOff = isComplimentary ? 0.0 : (rounded - total);

    final totalItems = gAlc.values.fold(0, (s, i) => s + (i['qty'] as int)) +
        gNonAlc.values.fold(0, (s, i) => s + (i['qty'] as int));

    return '''
    <div style="font-family:Calibri,Arial,sans-serif;width:100%;font-size:22px;">
      ${_headerHtml(billId)}
      ${_complimentaryBannerHtml()}
      <table style="width:100%;border-collapse:collapse;font-size:21px;">
        <tr><th style="text-align:left;">Item</th><th>Qty</th><th>Price</th><th style="text-align:right;">Amt</th></tr>
        ${alcRows.isNotEmpty ? '<tr><td colspan="4" style="font-weight:bold;">Alcoholic Drinks</td></tr>$alcRows' : ''}
        ${nonAlcRows.isNotEmpty ? '<tr><td colspan="4" style="font-weight:bold;">Non-Alcoholic Drinks</td></tr>$nonAlcRows' : ''}
      </table>
      <pre style="font-size:22px;text-align:center;">$_line</pre>
      <table style="width:100%;font-size:21px;">
        <tr><td>Total Qty:</td><td style="text-align:right;">$totalItems</td></tr>
        <tr><td>Subtotal:</td><td style="text-align:right;">₹${subtotal.toStringAsFixed(2)}</td></tr>
        ${drinkDiscAmt > 0 ? '<tr><td>${isQRDiscount ? 'QR Discount' : 'Drink Discount'} (${drinkDiscountType == 'percent' ? '${drink_discount}%' : '₹${drink_discount}'})</td><td style="text-align:right;">-₹${drinkDiscAmt.toStringAsFixed(2)}</td></tr>' : ''}
        ${vat > 0 ? '<tr><td>VAT (₹${alcAfterDiscount.toStringAsFixed(2)}) @10%</td><td style="text-align:right;">₹${vat.toStringAsFixed(2)}</td></tr>' : ''}
        ${cgst > 0 ? '<tr><td>CGST (₹${nonAlcTotal.toStringAsFixed(2)}) @2.5%</td><td style="text-align:right;">₹${cgst.toStringAsFixed(2)}</td></tr>' : ''}
        ${sgst > 0 ? '<tr><td>SGST (₹${nonAlcTotal.toStringAsFixed(2)}) @2.5%</td><td style="text-align:right;">₹${sgst.toStringAsFixed(2)}</td></tr>' : ''}
        <tr><td>Round Off</td><td style="text-align:right;">₹${roundOff.toStringAsFixed(2)}</td></tr>
        <tr style="font-weight:bold;font-size:23px;">
          <td>${isComplimentary ? 'COMPLIMENTARY TOTAL:' : 'GRAND TOTAL:'}</td>
          <td style="text-align:right;">₹${rounded.toStringAsFixed(2)}</td>
        </tr>
      </table>
      ${_complimentaryHtml()}
      $_footer
    </div>''';
  }

  // ── FIX 1 & 2: taxes added to grand total; complimentary shows ₹0 ──────────
  String _buildCombinedBillHtml(int billId) {
    final gFood = _groupItems(_completeFoodOrders, 'food');
    final gAlc = _groupItems(
        _completeDrinkOrders.where(_isDrinkAlcoholic).toList(), 'drink');
    final gNonAlc = _groupItems(
        _completeDrinkOrders.where((i) => !_isDrinkAlcoholic(i)).toList(),
        'drink');

    final foodRows = _buildItemRows(gFood.values);
    final alcRows = _buildItemRows(gAlc.values);
    final nonAlcRows = _buildItemRows(gNonAlc.values);

    final foodTotal =
        gFood.values.fold(0.0, (s, i) => s + (i['totalAmount'] as double));
    final alcTotal =
        gAlc.values.fold(0.0, (s, i) => s + (i['totalAmount'] as double));
    final nonAlcTotal =
        gNonAlc.values.fold(0.0, (s, i) => s + (i['totalAmount'] as double));

    double foodDiscAmt = foodDiscountType == 'percent'
        ? foodTotal * (food_discount / 100)
        : food_discount.clamp(0, foodTotal);
    double drinkDiscAmt = drinkDiscountType == 'percent'
        ? alcTotal * (drink_discount / 100)
        : drink_discount.clamp(0, alcTotal);

    final foodAfterDiscount = foodTotal - foodDiscAmt;
    final alcAfterDiscount = alcTotal - drinkDiscAmt;
    final cgstBase = foodAfterDiscount + nonAlcTotal;
    final cgst = cgstBase * 0.025;
    final sgst = cgstBase * 0.025;
    final vat = alcAfterDiscount * 0.10;

    // ── FIX 1: include CGST + SGST + VAT in the final total ────────────────
    final combined = foodAfterDiscount + alcAfterDiscount + nonAlcTotal + cgst + sgst + vat;
    final rounded = isComplimentary ? 0.0 : combined.roundToDouble();
    final roundOff = isComplimentary ? 0.0 : (rounded - combined);

    final totalItems = gFood.values.fold(0, (s, i) => s + (i['qty'] as int)) +
        gAlc.values.fold(0, (s, i) => s + (i['qty'] as int)) +
        gNonAlc.values.fold(0, (s, i) => s + (i['qty'] as int));

    return '''
    <div style="font-family:Calibri,Arial,sans-serif;width:100%;font-size:22px;">
      ${_headerHtml(billId)}
      ${_complimentaryBannerHtml()}
      <table style="width:100%;border-collapse:collapse;font-size:21px;">
        <tr><th style="text-align:left;">Item</th><th>Qty</th><th>Price</th><th style="text-align:right;">Amt</th></tr>
        ${foodRows.isNotEmpty ? '<tr><td colspan="4" style="font-weight:bold;">Food Items</td></tr>$foodRows' : ''}
        ${nonAlcRows.isNotEmpty ? '<tr><td colspan="4" style="font-weight:bold;">Non-Alcoholic Drinks</td></tr>$nonAlcRows' : ''}
        ${alcRows.isNotEmpty ? '<tr><td colspan="4" style="font-weight:bold;">Alcoholic Drinks</td></tr>$alcRows' : ''}
      </table>
      <pre style="font-size:22px;text-align:center;">$_line</pre>
      <table style="width:100%;font-size:21px;">
        <tr><td>Total Qty:</td><td style="text-align:right;">$totalItems</td></tr>
        <tr><td>Food Total:</td><td style="text-align:right;">₹${foodTotal.toStringAsFixed(2)}</td></tr>
        ${foodDiscAmt > 0 ? '<tr><td>${isQRDiscount ? 'QR Discount' : 'Food Discount'}</td><td style="text-align:right;">-₹${foodDiscAmt.toStringAsFixed(2)}</td></tr>' : ''}
        <tr><td>Non-Alcoholic Total:</td><td style="text-align:right;">₹${nonAlcTotal.toStringAsFixed(2)}</td></tr>
        <tr><td>Alcoholic Total:</td><td style="text-align:right;">₹${alcTotal.toStringAsFixed(2)}</td></tr>
        ${drinkDiscAmt > 0 ? '<tr><td>${isQRDiscount ? 'QR Discount - Drinks' : 'Drink Discount'}</td><td style="text-align:right;">-₹${drinkDiscAmt.toStringAsFixed(2)}</td></tr>' : ''}
        <tr><td>CGST (₹${cgstBase.toStringAsFixed(2)}) @2.5%</td><td style="text-align:right;">₹${cgst.toStringAsFixed(2)}</td></tr>
        <tr><td>SGST (₹${cgstBase.toStringAsFixed(2)}) @2.5%</td><td style="text-align:right;">₹${sgst.toStringAsFixed(2)}</td></tr>
        ${vat > 0 ? '<tr><td>VAT (₹${alcAfterDiscount.toStringAsFixed(2)}) @10%</td><td style="text-align:right;">₹${vat.toStringAsFixed(2)}</td></tr>' : ''}
        <tr><td>Round Off</td><td style="text-align:right;">₹${roundOff.toStringAsFixed(2)}</td></tr>
        <tr style="font-weight:bold;font-size:23px;">
          <td>${isComplimentary ? 'COMPLIMENTARY TOTAL:' : 'GRAND TOTAL:'}</td>
          <td style="text-align:right;">₹${rounded.toStringAsFixed(2)}</td>
        </tr>
      </table>
      ${_complimentaryHtml()}
      $_footer
    </div>''';
  }

  String _buildResettleBillHtml(
      int? billId, Map<String, double> paymentBreakdown, double tipAmount) {
    final calc = _compute();
    final gFood = _groupItems(_completeFoodOrders, 'food');
    final gDrink = _groupItems(_completeDrinkOrders, 'drink');
    final foodRows = _buildItemRows(gFood.values);
    final drinkRows = _buildItemRows(gDrink.values);

    String paymentSection = '';
    if (paymentBreakdown.isNotEmpty) {
      paymentSection =
          '<pre style="font-size:22px;text-align:center;margin:2px 0;">$_line</pre>'
          '<table style="width:100%;font-size:20px;">';
      paymentBreakdown.forEach((method, amount) {
        final m =
            method[0].toUpperCase() + method.substring(1).toLowerCase();
        paymentSection +=
            '<tr><td>$m:</td><td style="text-align:right;">₹${amount.toStringAsFixed(2)}</td></tr>';
      });
      if (tipAmount > 0) {
        paymentSection +=
            '<tr><td>Tip:</td><td style="text-align:right;">₹${tipAmount.toStringAsFixed(2)}</td></tr>';
      }
      paymentSection +=
          '</table><pre style="font-size:22px;text-align:center;margin:2px 0;">$_line</pre>';
    }

    final totalItems =
        gFood.values.fold(0, (s, i) => s + (i['qty'] as int)) +
        gDrink.values.fold(0, (s, i) => s + (i['qty'] as int));

    // ── FIX 2: complimentary shows ₹0 ──────────────────────────────────────
    final grandTotal = isComplimentary ? 0.0 : calc.grandTotalRounded;

    return '''
    <div style="font-family:Calibri,Arial,sans-serif;width:100%;font-size:20px;">
      ${_headerHtml(billId ?? 0)}
      ${_complimentaryBannerHtml()}
      <table style="width:100%;border-collapse:collapse;font-size:20px;">
        <tr><th style="text-align:left;">Item</th><th>Qty</th><th>Price</th><th style="text-align:right;">Amt</th></tr>
        ${foodRows.isNotEmpty ? '<tr><td colspan="4" style="font-weight:bold;">Food &amp; Non-Alcoholic</td></tr>$foodRows' : ''}
        ${drinkRows.isNotEmpty ? '<tr><td colspan="4" style="font-weight:bold;">Drinks</td></tr>$drinkRows' : ''}
      </table>
      <pre style="font-size:22px;text-align:center;margin:2px 0;">$_line</pre>
      <table style="width:100%;font-size:20px;">
        <tr><td>Total Qty:</td><td style="text-align:right;">$totalItems</td></tr>
        ${calc.serviceChargeAmount > 0 ? '<tr><td>Service (${widget.serviceCharge}%)</td><td style="text-align:right;">₹${calc.serviceChargeAmount.toStringAsFixed(2)}</td></tr>' : ''}
        ${calc.cgst > 0 ? '<tr><td>CGST @2.5%</td><td style="text-align:right;">₹${calc.cgst.toStringAsFixed(2)}</td></tr>' : ''}
        ${calc.sgst > 0 ? '<tr><td>SGST @2.5%</td><td style="text-align:right;">₹${calc.sgst.toStringAsFixed(2)}</td></tr>' : ''}
        ${calc.vatAmount > 0 ? '<tr><td>VAT @10%</td><td style="text-align:right;">₹${calc.vatAmount.toStringAsFixed(2)}</td></tr>' : ''}
        <tr><td>Round Off</td><td style="text-align:right;">₹${calc.roundOffAmount.toStringAsFixed(2)}</td></tr>
        <tr style="font-weight:bold;font-size:22px;">
          <td>${isComplimentary ? 'COMPLIMENTARY TOTAL:' : 'GRAND TOTAL:'}</td>
          <td style="text-align:right;">₹${grandTotal.toStringAsFixed(2)}</td>
        </tr>
      </table>
      ${_complimentaryHtml()}
      $paymentSection
      $_footer
    </div>''';
  }

  String _buildItemRows(Iterable<Map<String, dynamic>> items) {
    return items.map((item) {
      final name = item['name'];
      final qty = item['qty'];
      final price = (item['price'] as double?) ?? 0.0;
      final total = (item['totalAmount'] as double?) ?? price * qty;
      return '''
        <tr>
          <td>$name</td>
          <td style="text-align:center;">$qty</td>
          <td style="text-align:center;">${price.toStringAsFixed(2)}</td>
          <td style="text-align:right;">${total.toStringAsFixed(2)}</td>
        </tr>''';
    }).join();
  }

  // ─── Settle bill ───────────────────────────────────────────────────────────
  Future<void> _settleUpBill(
    BuildContext context,
    double tipAmount,
    Map<String, double> paymentBreakdown,
  ) async {
    try {
      if (!context.mounted) return;
      if (billId == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Error: No bill ID! Generate the bill first.')));
        return;
      }

      final activePayments =
          paymentBreakdown.entries.where((e) => e.value > 0).length;
      if (activePayments > 1) {
        final html =
            _buildResettleBillHtml(billId, paymentBreakdown, tipAmount);
        print_service.triggerPrintWindow(html);
      }

      final url = Uri.parse(
          '${dotenv.env['API_URL']}/tables/bills/$billId/settle');
      final body = jsonEncode({
        'tip_amount': tipAmount,
        'payment_breakdown': paymentBreakdown,
        'complimentary': isComplimentary,
        'complimentary_remark': complimentaryRemark,
        'complimentary_password': complimentaryPassword,
      });

      final response = await http.post(url,
          headers: {'Content-Type': 'application/json'}, body: body);

      if (response.statusCode == 200) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(isComplimentary
                  ? 'Complimentary bill settled!'
                  : 'Bill settled!')));
          Navigator.pop(context);
          Navigator.pop(context);
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to settle: ${response.body}')));
        }
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // ─── Complimentary dialog ──────────────────────────────────────────────────
  void _showComplimentaryDialog() {
    final remarkController = TextEditingController();
    final passwordController = TextEditingController();
    String? localSelectedProfileId = selectedProfileId;
    final refreshNotifier = ValueNotifier<bool>(false);

    if (complimentaryProfiles.isEmpty && !isLoadingProfiles) {
      fetchComplimentaryProfiles()
          .then((_) => refreshNotifier.value = !refreshNotifier.value);
    }

    showDialog(
      context: context,
      builder: (ctx) => ValueListenableBuilder<bool>(
        valueListenable: refreshNotifier,
        builder: (_, __, ___) => StatefulBuilder(
          builder: (context, setDialogState) => Dialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: Colors.white,
            child: Container(
              width: 400,
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                        child: Text('Complimentary Bill',
                            style: GoogleFonts.poppins(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: Colors.red.shade700))),
                    const SizedBox(height: 20),
                    if (isLoadingProfiles)
                      Center(
                          child: LoadingAnimationWidget.staggeredDotsWave(
                              color: Colors.red.shade600, size: 30))
                    else if (complimentaryProfiles.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.orange.shade200)),
                        child: Row(children: [
                          Icon(Icons.warning, color: Colors.orange.shade700),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text('No profiles available.',
                                  style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      color: Colors.orange.shade700))),
                        ]),
                      )
                    else
                      DropdownButtonFormField<String>(
                        value: localSelectedProfileId,
                        decoration: InputDecoration(
                          prefixIcon: Icon(Icons.person,
                              color: Colors.red.shade600),
                          labelText: 'Select Profile *',
                          filled: true,
                          fillColor: Colors.grey[100],
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none),
                        ),
                        items: complimentaryProfiles
                            .map((p) => DropdownMenuItem<String>(
                                  value: p['id'],
                                  child: Text(p['name']!,
                                      style:
                                          GoogleFonts.poppins(fontSize: 14)),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setDialogState(() => localSelectedProfileId = v),
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: remarkController,
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.comment,
                            color: Colors.red.shade600),
                        labelText: 'Remark *',
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        prefixIcon:
                            Icon(Icons.lock, color: Colors.red.shade600),
                        labelText: 'Manager Password *',
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            setState(() {
                              isComplimentary = false;
                              selectedProfileId = null;
                            });
                            Navigator.pop(ctx);
                          },
                          child: Text('Cancel',
                              style:
                                  TextStyle(color: Colors.grey.shade600)),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade600,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10))),
                          onPressed: complimentaryProfiles.isEmpty
                              ? null
                              : () {
                                  if (localSelectedProfileId == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content:
                                                Text('Please select a profile')));
                                    return;
                                  }
                                  if (remarkController.text.trim().isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content:
                                                Text('Remark is required')));
                                    return;
                                  }
                                  if (passwordController.text.trim().isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content:
                                                Text('Password is required')));
                                    return;
                                  }
                                  setState(() {
                                    isComplimentary = true;
                                    selectedProfileId =
                                        localSelectedProfileId;
                                    complimentaryRemark =
                                        remarkController.text.trim();
                                    complimentaryPassword =
                                        passwordController.text.trim();
                                  });
                                  Navigator.pop(ctx);
                                },
                          child: const Text('Confirm'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Payment dialog ────────────────────────────────────────────────────────
  void _showPaymentDialog(BuildContext context, int totalAmount) {
    final amountController = TextEditingController();
    final tipController = TextEditingController();
    final cashController = TextEditingController();
    final cardController = TextEditingController();
    final upiController = TextEditingController();
    final tipOtherController = TextEditingController();
    String selectedPaymentMethod = 'Cash';
    String? amountValidationMessage;
    String? tipValidationMessage;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Colors.white,
          child: Container(
            width: 500,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                    child: Text('Settle Payment',
                        style: GoogleFonts.poppins(
                            fontSize: 20, fontWeight: FontWeight.w600))),
                const SizedBox(height: 10),
                Center(
                    child: Text('Bill Total: ₹$totalAmount',
                        style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[700]))),
                const SizedBox(height: 20),
                Text('Payment Method',
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700])),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: ['Cash', 'Card', 'UPI', 'Other'].map((method) {
                    final isSelected = selectedPaymentMethod == method;
                    return ChoiceChip(
                      label: Text(method),
                      selected: isSelected,
                      onSelected: (_) =>
                          setState(() => selectedPaymentMethod = method),
                      selectedColor: Colors.teal.shade600,
                      backgroundColor: Colors.grey[200],
                      labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w500),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                if (selectedPaymentMethod != 'Other') ...[
                  _paymentInput('Amount', amountController, Icons.attach_money,
                      hint: 'Expected: ₹$totalAmount', onChanged: (v) {
                    int inputAmount = int.tryParse(v) ?? 0;
                    setState(() {
                      int tip = 0;
                      if (inputAmount > totalAmount) {
                        tip = inputAmount - totalAmount;
                        inputAmount = totalAmount;
                        amountController.text = inputAmount.toString();
                        amountController.selection = TextSelection.fromPosition(
                            TextPosition(
                                offset: amountController.text.length));
                      }
                      tipController.text = tip.toString();
                      amountValidationMessage = inputAmount < totalAmount
                          ? 'Amount is ₹${totalAmount - inputAmount} less than bill total'
                          : null;
                      tipValidationMessage =
                          tip > 500 ? 'Tip is greater than ₹500!' : null;
                    });
                  }),
                  if (amountValidationMessage != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(amountValidationMessage!,
                            style: TextStyle(
                                color: Colors.orange.shade700,
                                fontSize: 12))),
                  const SizedBox(height: 12),
                  _paymentInput(
                      'Tip (optional)', tipController, Icons.card_giftcard),
                  if (tipValidationMessage != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(tipValidationMessage!,
                            style: TextStyle(
                                color: Colors.red.shade700, fontSize: 12))),
                ] else ...[
                  Row(children: [
                    Expanded(
                        child: _paymentInput('Cash', cashController,
                            Icons.attach_money, onChanged: (_) {
                      setState(() {
                        _updateOtherTip(totalAmount, cashController,
                            cardController, upiController, tipOtherController,
                            (msg) => tipValidationMessage = msg);
                      });
                    })),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _paymentInput('Card', cardController,
                            Icons.attach_money, onChanged: (_) {
                      setState(() {
                        _updateOtherTip(totalAmount, cashController,
                            cardController, upiController, tipOtherController,
                            (msg) => tipValidationMessage = msg);
                      });
                    })),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _paymentInput('UPI', upiController,
                            Icons.attach_money, onChanged: (_) {
                      setState(() {
                        _updateOtherTip(totalAmount, cashController,
                            cardController, upiController, tipOtherController,
                            (msg) => tipValidationMessage = msg);
                      });
                    })),
                  ]),
                  const SizedBox(height: 12),
                  _paymentInput('Tip (optional)', tipOtherController,
                      Icons.card_giftcard),
                  if (tipValidationMessage != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(tipValidationMessage!,
                            style: TextStyle(
                                color: Colors.red.shade700, fontSize: 12))),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel')),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal.shade600,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12)),
                      onPressed: () async {
                        Map<String, double> breakdown = {};
                        int tipAmount = 0;

                        if (selectedPaymentMethod != 'Other') {
                          int amount =
                              int.tryParse(amountController.text) ?? 0;
                          tipAmount =
                              int.tryParse(tipController.text) ?? 0;
                          if (amount < totalAmount) {
                            showDialog(
                                context: context,
                                builder: (_) => AlertDialog(
                                      title:
                                          const Text('Insufficient Amount'),
                                      content: Text(
                                          'Amount is ₹${totalAmount - amount} less than total.'),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text('OK'))
                                      ],
                                    ));
                            return;
                          }
                          breakdown = {
                            selectedPaymentMethod.toLowerCase():
                                amount.toDouble()
                          };
                        } else {
                          int cash =
                              int.tryParse(cashController.text) ?? 0;
                          int card =
                              int.tryParse(cardController.text) ?? 0;
                          int upi =
                              int.tryParse(upiController.text) ?? 0;
                          tipAmount =
                              int.tryParse(tipOtherController.text) ?? 0;
                          if (cash + card + upi < totalAmount) {
                            showDialog(
                                context: context,
                                builder: (_) => AlertDialog(
                                      title:
                                          const Text('Insufficient Amount'),
                                      content: Text(
                                          'Total entered is ₹${totalAmount - (cash + card + upi)} less.'),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text('OK'))
                                      ],
                                    ));
                            return;
                          }
                          if (cash > 0) breakdown['cash'] = cash.toDouble();
                          if (card > 0) breakdown['card'] = card.toDouble();
                          if (upi > 0) breakdown['upi'] = upi.toDouble();
                        }

                        await _settleUpBill(
                            context, tipAmount.toDouble(), breakdown);
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: const Text('Confirm'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _paymentInput( 
    String label,
    TextEditingController controller,
    IconData icon, {
    String? hint,
    Function(String)? onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      onChanged: onChanged,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.teal),
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      ),
    );
  }

  void _updateOtherTip(
    int totalAmount,
    TextEditingController cashCtrl,
    TextEditingController cardCtrl,
    TextEditingController upiCtrl,
    TextEditingController tipCtrl,
    void Function(String?) onTipWarning,
  ) {
    int cash = int.tryParse(cashCtrl.text) ?? 0;
    int card = int.tryParse(cardCtrl.text) ?? 0;
    int upi = int.tryParse(upiCtrl.text) ?? 0;
    int total = cash + card + upi;
    int tip = 0;
    if (total > totalAmount) {
      tip = total - totalAmount;
      int diff = total - totalAmount;
      if (cash > 0) {
        int r = diff <= cash ? diff : cash;
        cash -= r;
        diff -= r;
        cashCtrl.text = cash.toString();
      }
      if (diff > 0 && card > 0) {
        int r = diff <= card ? diff : card;
        card -= r;
        diff -= r;
        cardCtrl.text = card.toString();
      }
      if (diff > 0 && upi > 0) {
        int r = diff <= upi ? diff : upi;
        upi -= r;
        upiCtrl.text = upi.toString();
      }
    }
    tipCtrl.text = tip.toString();
    onTipWarning(tip > 50 ? 'Tip is greater than ₹50!' : null);
  }
}

// ─── Data class for bill calculations ─────────────────────────────────────────
class _BillCalc {
  final List<Map<String, dynamic>> combinedItems;
  final List<Map<String, dynamic>> foodItems;
  final List<Map<String, dynamic>> nonAlcoholicDrinks;
  final List<Map<String, dynamic>> alcoholicDrinks;
  final double actualFoodTotal;
  final double nonAlcoholicTotal;
  final double alcoholicTotal;
  final double combinedSubTotal;
  final double discountAmount;
  final double subtotalAfterDiscount;
  final double cgst;
  final double sgst;
  final double vatAmount;
  final double serviceChargeAmount;
  final double grandTotalRounded;
  final double roundOffAmount;

  const _BillCalc({
    required this.combinedItems,
    required this.foodItems,
    required this.nonAlcoholicDrinks,
    required this.alcoholicDrinks,
    required this.actualFoodTotal,
    required this.nonAlcoholicTotal,
    required this.alcoholicTotal,
    required this.combinedSubTotal,
    required this.discountAmount,
    required this.subtotalAfterDiscount,
    required this.cgst,
    required this.sgst,
    required this.vatAmount,
    required this.serviceChargeAmount,
    required this.grandTotalRounded,
    required this.roundOffAmount,
  });
}