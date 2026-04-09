import 'package:flutter/foundation.dart' show kIsWeb;
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

class BillDetailsPage extends StatefulWidget {
  final int billId;
  final String? billNumber;

  const BillDetailsPage({super.key, required this.billId, this.billNumber});

  @override
  State<BillDetailsPage> createState() => _BillDetailsPageState();
}

class _BillDetailsPageState extends State<BillDetailsPage> {
  bool isLoading = true;
  Map<String, dynamic>? billData;
  String errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchBillDetails();
  }

  Future<void> _fetchBillDetails() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = '';
      });

      final response = await http.get(
        Uri.parse('${dotenv.env['API_URL']}/tables/bills/${widget.billId}'),
        headers: {"Content-Type": "application/json"},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          billData = data['data'] ?? data;
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = 'Failed to load bill details: ${response.statusCode}';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Error loading bill details: $e';
        isLoading = false;
      });
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  ITEM EXTRACTION  (mirrors GenerateBillPage._groupItems logic)
  // ─────────────────────────────────────────────────────────────

  /// Splits order_details into three buckets:
  ///   • foodItems          – type==food  OR  type==drink && !applyVAT
  ///   • alcoholicItems     – type==drink && applyVAT==true
  ///   • (non-alcoholic drinks are folded into foodItems bucket)
  ///
  /// We determine "alcoholic" by checking:
  ///   1. order_detail has explicit applyVAT field  (rare, future-proof)
  ///   2. Otherwise fall back to the bill-level vat_amount > 0 heuristic
  ///      and a simple category/name check.
  ///
  /// NOTE: The API response currently doesn't expose applyVAT per item, so
  /// we use the same convention as GenerateBillPage: items whose stored
  /// totalAmount contributes to vat_amount are marked alcoholic.  Since we
  /// can't reliably know which drink items are alcoholic from the flat list,
  /// we mark all type==drink items as alcoholic UNLESS the bill's vat_amount
  /// is 0 (meaning no VAT was charged at all).
  List<Map<String, dynamic>> _extractFoodItems() {
    final orderDetails = billData?['order_details'] ?? [];
    final List<Map<String, dynamic>> items = [];

    for (var item in orderDetails) {
      final String rawType = item['type'] ?? 'food';
      if (rawType != 'food') continue;

      items.add({
        'name': item['item'] ?? 'Unknown Item',
        'qty': (item['quantity'] as num?)?.toInt() ?? 0,
        'price': double.tryParse(item['pricePerUnit']?.toString() ?? '0') ?? 0.0,
        'total': double.tryParse(item['totalAmount']?.toString() ?? '0') ?? 0.0,
        'type': 'food',
        'category': item['category'] ?? 'N/A',
      });
    }
    return items;
  }

  List<Map<String, dynamic>> _extractAlcoholicItems() {
    final orderDetails = billData?['order_details'] ?? [];
    final vatAmount =
        double.tryParse(billData?['vat_amount']?.toString() ?? '0') ?? 0.0;
    final List<Map<String, dynamic>> items = [];

    for (var item in orderDetails) {
      final String rawType = item['type'] ?? 'food';
      if (rawType != 'drink') continue;

      // If the bill has no VAT, treat all drinks as non-alcoholic (food bucket).
      // If applyVAT field is present, honour it; otherwise default to true when vat>0.
      bool isAlcoholic;
      if (item.containsKey('applyVAT')) {
        final raw = item['applyVAT'];
        isAlcoholic = raw == true || raw == 'true' || raw == 1;
      } else {
        isAlcoholic = vatAmount > 0;
      }

      if (!isAlcoholic) continue;

      items.add({
        'name': item['item'] ?? 'Unknown Item',
        'qty': (item['quantity'] as num?)?.toInt() ?? 0,
        'price': double.tryParse(item['pricePerUnit']?.toString() ?? '0') ?? 0.0,
        'total': double.tryParse(item['totalAmount']?.toString() ?? '0') ?? 0.0,
        'type': 'drink',
        'category': item['category'] ?? 'N/A',
      });
    }
    return items;
  }

  List<Map<String, dynamic>> _extractNonAlcoholicDrinkItems() {
    final orderDetails = billData?['order_details'] ?? [];
    final vatAmount =
        double.tryParse(billData?['vat_amount']?.toString() ?? '0') ?? 0.0;
    final List<Map<String, dynamic>> items = [];

    for (var item in orderDetails) {
      final String rawType = item['type'] ?? 'food';
      if (rawType != 'drink') continue;

      bool isAlcoholic;
      if (item.containsKey('applyVAT')) {
        final raw = item['applyVAT'];
        isAlcoholic = raw == true || raw == 'true' || raw == 1;
      } else {
        isAlcoholic = vatAmount > 0;
      }

      if (isAlcoholic) continue;

      items.add({
        'name': item['item'] ?? 'Unknown Item',
        'qty': (item['quantity'] as num?)?.toInt() ?? 0,
        'price': double.tryParse(item['pricePerUnit']?.toString() ?? '0') ?? 0.0,
        'total': double.tryParse(item['totalAmount']?.toString() ?? '0') ?? 0.0,
        'type': 'food', // treated as food for tax purposes
        'category': item['category'] ?? 'N/A',
      });
    }
    return items;
  }

  // ─────────────────────────────────────────────────────────────
  //  TOTALS  (use stored API values – single source of truth)
  // ─────────────────────────────────────────────────────────────
  Map<String, double> _buildCalculations() {
    final totalAmount =
        double.tryParse(billData?['total_amount']?.toString() ?? '0') ?? 0.0;
    final discountAmount =
        double.tryParse(billData?['discount_amount']?.toString() ?? '0') ?? 0.0;
    final serviceChargeAmount =
        double.tryParse(billData?['service_charge_amount']?.toString() ?? '0') ??
            0.0;
    final taxAmount =
        double.tryParse(billData?['tax_amount']?.toString() ?? '0') ?? 0.0;
    final vatAmount =
        double.tryParse(billData?['vat_amount']?.toString() ?? '0') ?? 0.0;
    final finalAmount =
        double.tryParse(billData?['final_amount']?.toString() ?? '0') ?? 0.0;
    final roundOff =
        double.tryParse(billData?['round_off']?.toString() ?? '0') ?? 0.0;

    final cgst = taxAmount / 2;
    final sgst = taxAmount / 2;

    return {
      'subtotal': totalAmount,
      'discount': discountAmount,
      'serviceCharge': serviceChargeAmount,
      'tax': taxAmount,
      'cgst': cgst,
      'sgst': sgst,
      'vat': vatAmount,
      'roundOff': roundOff,
      'grandTotal': finalAmount,
    };
  }

  // ─────────────────────────────────────────────────────────────
  //  HELPERS
  // ─────────────────────────────────────────────────────────────
  String _getBillStatus() {
    final isLocked = billData?['is_locked'];
    if (isLocked == true || isLocked == 1 || isLocked == 'true') {
      return 'Locked';
    }
    return 'Active';
  }

  bool _isComplimentary() {
    final raw = billData?['complimentary'] ??
        billData?['isComplimentary'] ??
        billData?['isCompliemntary'];
    if (raw == null) return false;
    if (raw is bool) return raw;
    if (raw is num) return raw == 1;
    if (raw is String) {
      final l = raw.toLowerCase();
      return l == 'true' || l == '1' || l == 'yes';
    }
    return false;
  }

  String _formatDate1(dynamic dateTimeInput, {required String mode}) {
    if (dateTimeInput == null) return '';
    DateTime utcDateTime;
    if (dateTimeInput is String) {
      utcDateTime = DateTime.parse(dateTimeInput).toUtc();
    } else if (dateTimeInput is DateTime) {
      utcDateTime = dateTimeInput.toUtc();
    } else {
      return '';
    }
    final ist = utcDateTime.add(const Duration(hours: 5, minutes: 30));
    if (mode == 'date') {
      return '${ist.day.toString().padLeft(2, '0')}-${ist.month.toString().padLeft(2, '0')}-${ist.year}';
    } else if (mode == 'time') {
      final hour = ist.hour % 12 == 0 ? 12 : ist.hour % 12;
      final minute = ist.minute.toString().padLeft(2, '0');
      final period = ist.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $period';
    }
    return ist.toString();
  }

  // ─────────────────────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: Text(
          "Bill Details ${widget.billNumber != null ? '- #${widget.billNumber}' : '- #${widget.billId}'}",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchBillDetails,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: isLoading
          ? Center(
              child: LoadingAnimationWidget.staggeredDotsWave(
                color: Colors.teal,
                size: 50,
              ),
            )
          : errorMessage.isNotEmpty
              ? _buildErrorWidget()
              : billData == null
                  ? _buildNoBillDataWidget()
                  : _buildBillContent(),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
            const SizedBox(height: 16),
            Text(
              'Error Loading Bill',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.red.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _fetchBillDetails,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoBillDataWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No Bill Data Found',
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  MAIN CONTENT  (two-column layout)
  // ─────────────────────────────────────────────────────────────
  Widget _buildBillContent() {
    final foodItems = _extractFoodItems();
    final nonAlcoholicDrinks = _extractNonAlcoholicDrinkItems();
    final alcoholicItems = _extractAlcoholicItems();
    final calculations = _buildCalculations();
    final isComplimentary = _isComplimentary();

    // Items that fall under CGST/SGST: food + non-alcoholic drinks
    final cgstItems = [...foodItems, ...nonAlcoholicDrinks];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── LEFT: Bill Preview ──────────────────────────────────
        Expanded(
          flex: 3,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _buildBillPreviewCard(
              cgstItems: cgstItems,
              alcoholicItems: alcoholicItems,
              foodItems: foodItems,
              nonAlcoholicDrinks: nonAlcoholicDrinks,
              calculations: calculations,
              isComplimentary: isComplimentary,
            ),
          ),
        ),

        // ── RIGHT: Info + Actions ──────────────────────────────
        Container(
          width: 380,
          color: Colors.white,
          child: Column(
            children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.teal.shade600,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Bill Information',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Bill ID: ${widget.billId}',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
              // Scrollable panel
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildInfoCard(),
                      const SizedBox(height: 16),
                      _buildPaymentSummaryCard(calculations, isComplimentary),
                      const SizedBox(height: 16),
                      _buildActionButtons(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  LEFT CARD: Bill Preview (mirrors GenerateBillPage layout)
  // ─────────────────────────────────────────────────────────────
  Widget _buildBillPreviewCard({
    required List<Map<String, dynamic>> cgstItems,
    required List<Map<String, dynamic>> alcoholicItems,
    required List<Map<String, dynamic>> foodItems,
    required List<Map<String, dynamic>> nonAlcoholicDrinks,
    required Map<String, double> calculations,
    required bool isComplimentary,
  }) {
    final complimentaryRemark = billData?['complimentary_remark'] ?? billData?['remark'] ?? '';

    // Totals for section headers
    final foodAndNonAlcoholicTotal = cgstItems.fold(0.0, (s, i) => s + (i['total'] as double));
    final alcoholicTotal = alcoholicItems.fold(0.0, (s, i) => s + (i['total'] as double));

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Card Header ──────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isComplimentary ? Colors.red.shade600 : Colors.teal.shade600,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      isComplimentary ? Icons.card_giftcard : Icons.receipt_long,
                      color: Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      isComplimentary ? 'Complimentary Bill' : 'Bill Receipt',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _getBillStatus(),
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '5K Family Resto & Bar',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Bill #${widget.billId} • ${_formatDate1(billData?['createdAt'], mode: 'date')}',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),

          // ── Card Body ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Order Items',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 12),

                // ── Table header row ─────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(flex: 3, child: Text('Item', style: _headerTextStyle())),
                      Expanded(
                        child: Text('Qty', textAlign: TextAlign.center, style: _headerTextStyle()),
                      ),
                      Expanded(
                        child: Text('Price', textAlign: TextAlign.center, style: _headerTextStyle()),
                      ),
                      Expanded(
                        child: Text('Total', textAlign: TextAlign.right, style: _headerTextStyle()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // ── Food & Non-Alcoholic Section ─────────────
                if (cgstItems.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Food & Beverages (CGST+SGST @2.5% each — ₹${foodAndNonAlcoholicTotal.toStringAsFixed(2)})',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...cgstItems.map((item) => _buildItemRow(item, isAlcoholic: false)),
                  const SizedBox(height: 8),
                ],

                // ── Alcoholic Drinks Section ─────────────────
                if (alcoholicItems.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Alcoholic Beverages (VAT @ 10% — ₹${alcoholicTotal.toStringAsFixed(2)})',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue.shade800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...alcoholicItems.map((item) => _buildItemRow(item, isAlcoholic: true)),
                ],

                const SizedBox(height: 16),
                const Divider(thickness: 2),
                const SizedBox(height: 8),

                // ── Summary rows ─────────────────────────────
                _buildSummaryRow(
                  'Food & Beverages Total',
                  foodAndNonAlcoholicTotal,
                  color: Colors.teal,
                ),
                if (alcoholicTotal > 0)
                  _buildSummaryRow(
                    'Alcoholic Drinks Total',
                    alcoholicTotal,
                    color: Colors.deepPurple,
                  ),

                const Divider(thickness: 1, height: 16),
                _buildSummaryRow('Subtotal', calculations['subtotal'] ?? 0),

                if ((calculations['discount'] ?? 0) > 0) ...[
                  _buildSummaryRow(
                    'Discount',
                    -(calculations['discount'] ?? 0),
                    color: Colors.orange,
                  ),
                ],

                if ((calculations['serviceCharge'] ?? 0) > 0)
                  _buildSummaryRow('Service Charge', calculations['serviceCharge'] ?? 0),

                if ((calculations['cgst'] ?? 0) > 0)
                  _buildSummaryRow('CGST @ 2.5%', calculations['cgst'] ?? 0),
                if ((calculations['sgst'] ?? 0) > 0)
                  _buildSummaryRow('SGST @ 2.5%', calculations['sgst'] ?? 0),
                if ((calculations['vat'] ?? 0) > 0)
                  _buildSummaryRow('VAT @ 10%', calculations['vat'] ?? 0),
                if ((calculations['roundOff'] ?? 0) != 0)
                  _buildSummaryRow('Round Off', calculations['roundOff'] ?? 0),

                const SizedBox(height: 12),
                const Divider(thickness: 2),
                const SizedBox(height: 8),

                // ── Grand Total ──────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isComplimentary ? Colors.red.shade50 : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isComplimentary ? Colors.red.shade300 : Colors.green.shade300,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isComplimentary ? 'COMPLIMENTARY BILL' : 'GRAND TOTAL',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isComplimentary
                              ? Colors.red.shade800
                              : Colors.green.shade800,
                        ),
                      ),
                      Text(
                        isComplimentary
                            ? '₹0.00'
                            : '₹${(calculations['grandTotal'] ?? 0).toStringAsFixed(2)}',
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isComplimentary
                              ? Colors.red.shade800
                              : Colors.green.shade800,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Complimentary remark ─────────────────────
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
                        Text(
                          'Complimentary Reason:',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange.shade800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          complimentaryRemark,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: Colors.orange.shade700,
                          ),
                        ),
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

  // ─────────────────────────────────────────────────────────────
  //  ITEM ROW  (identical style to GenerateBillPage)
  // ─────────────────────────────────────────────────────────────
  Widget _buildItemRow(Map<String, dynamic> item, {required bool isAlcoholic}) {
    final name = item['name'] ?? 'Unknown Item';
    final qty = item['qty'] ?? 0;
    final price = (item['price'] as double?) ?? 0.0;
    final total = (item['total'] as double?) ?? (qty * price);

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
          // Name + icon
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Icon(
                  isAlcoholic ? Icons.local_bar : Icons.restaurant,
                  size: 16,
                  color: isAlcoholic ? Colors.blue.shade600 : Colors.orange.shade600,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // Qty
          Expanded(
            child: Text(
              qty.toString(),
              textAlign: TextAlign.center,
              style: _itemTextStyle(),
            ),
          ),
          // Price
          Expanded(
            child: Text(
              '₹${price.toStringAsFixed(2)}',
              textAlign: TextAlign.center,
              style: _itemTextStyle(),
            ),
          ),
          // Total
          Expanded(
            child: Text(
              '₹${total.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, double value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: Colors.grey.shade700,
            ),
          ),
          Text(
            '₹${value.toStringAsFixed(2)}',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color ?? Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  RIGHT PANEL CARDS
  // ─────────────────────────────────────────────────────────────
  Widget _buildInfoCard() {
    final cashierName =
        billData?['waiter']?['name']?.toString().split(' ')[0] ?? 'N/A';
    final tableDisplay = billData?['table']?['display_number'] ??
        billData?['display_number'] ??
        billData?['table_number'] ??
        'N/A';
    final sectionName = billData?['table']?['section']?['name'] ??
        billData?['section_name'] ??
        '';

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info, color: Colors.blue.shade600, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Bill Details',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow('Bill Date', _formatDate1(billData?['createdAt'], mode: 'date')),
            _buildInfoRow(
              'Table',
              sectionName.isNotEmpty ? '$sectionName - $tableDisplay' : 'Table $tableDisplay',
            ),
            _buildInfoRow('Waiter Name', cashierName),
            _buildInfoRow('Generated At', _formatDate1(billData?['generated_at'], mode: 'time')),
            _buildInfoRow('Bill Time', _formatDate1(billData?['time_of_bill'], mode: 'time')),
            _buildInfoRow('Status', _getBillStatus()),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentSummaryCard(Map<String, double> calculations, bool isComplimentary) {
    final tipAmount = (billData?['tip_amount'] as num?)?.toDouble() ?? 0.0;
    final paymentBreakdown = billData?['payment_breakdown'] as Map<String, dynamic>?;

    // Discount display
    final discountAmount = calculations['discount'] ?? 0.0;
    final subtotal = calculations['subtotal'] ?? 0.0;
    final foodDiscountPct =
        subtotal > 0 ? (discountAmount / subtotal) * 100 : 0.0;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.payment, color: Colors.green.shade600, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Payment Information',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow('Subtotal', '₹${(calculations['subtotal'] ?? 0).toStringAsFixed(2)}'),
            if (discountAmount > 0) ...[
              _buildInfoRow(
                'Discount (${foodDiscountPct.toStringAsFixed(1)}%)',
                '-₹${discountAmount.toStringAsFixed(2)}',
              ),
            ],
            if ((calculations['serviceCharge'] ?? 0) > 0)
              _buildInfoRow(
                'Service Charge',
                '₹${(calculations['serviceCharge'] ?? 0).toStringAsFixed(2)}',
              ),
            _buildInfoRow('CGST (2.5%)', '₹${(calculations['cgst'] ?? 0).toStringAsFixed(2)}'),
            _buildInfoRow('SGST (2.5%)', '₹${(calculations['sgst'] ?? 0).toStringAsFixed(2)}'),
            if ((calculations['vat'] ?? 0) > 0)
              _buildInfoRow('VAT (10%)', '₹${(calculations['vat'] ?? 0).toStringAsFixed(2)}'),
            if ((calculations['roundOff'] ?? 0) != 0)
              _buildInfoRow('Round Off', '₹${(calculations['roundOff'] ?? 0).toStringAsFixed(2)}'),
            const Divider(height: 16),
            _buildInfoRow(
              isComplimentary ? 'Complimentary Total' : 'Final Amount',
              isComplimentary ? '₹0.00' : '₹${(calculations['grandTotal'] ?? 0).toStringAsFixed(2)}',
            ),
            if (tipAmount > 0)
              _buildInfoRow('Tip', '₹${tipAmount.toStringAsFixed(2)}'),

            // Payment breakdown chips
            if (paymentBreakdown != null && paymentBreakdown.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Payment Breakdown',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: paymentBreakdown.entries
                    .where((e) {
                      final v = (e.value is num)
                          ? (e.value as num).toDouble()
                          : double.tryParse(e.value.toString()) ?? 0.0;
                      return v > 0;
                    })
                    .map((e) {
                      final v = (e.value is num)
                          ? (e.value as num).toDouble()
                          : double.tryParse(e.value.toString()) ?? 0.0;
                      return Chip(
                        label: Text(
                          '${e.key.toUpperCase()}: ₹${v.toStringAsFixed(0)}',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.teal.shade800,
                          ),
                        ),
                        backgroundColor: Colors.teal.shade50,
                        side: BorderSide(color: Colors.teal.shade200),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      );
                    })
                    .toList(),
              ),
            ],

            const SizedBox(height: 4),
            _buildInfoRow('Locked', billData?['is_locked'] == true ? 'Yes' : 'No'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  ACTION BUTTONS
  // ─────────────────────────────────────────────────────────────
  Widget _buildActionButtons() {
    final isLockedRaw = billData?['is_locked'];
    bool isLocked = false;
    if (isLockedRaw is bool) isLocked = isLockedRaw;
    else if (isLockedRaw is String) isLocked = isLockedRaw.toLowerCase() == 'true' || isLockedRaw == '1';
    else if (isLockedRaw is num) isLocked = isLockedRaw == 1;

    final isComplimentary = _isComplimentary();
    final bool canResettle = !isLocked && !isComplimentary;

    final String tooltipMessage = isComplimentary
        ? 'Complimentary bills cannot be resettled'
        : (isLocked ? 'Bill is locked / already settled' : 'Resettle this bill');

    return Column(
      children: [
        ElevatedButton.icon(
          onPressed: () {
            final html = _buildCombinedBillHtml();
            print_service.triggerPrintWindow(html);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Printing bill...'),
                duration: Duration(seconds: 2),
              ),
            );
          },
          icon: const Icon(Icons.print, size: 18),
          label: Text(
            'Print Bill',
            style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue.shade600,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 48),
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),
        Tooltip(
          message: tooltipMessage,
          child: ElevatedButton.icon(
            onPressed: canResettle ? () => _showResettleDialog(context) : null,
            icon: const Icon(Icons.sync, size: 18),
            label: Text(
              'Resettle Bill',
              style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: canResettle ? Colors.orange.shade600 : Colors.grey.shade300,
              foregroundColor: canResettle ? Colors.white : Colors.grey.shade700,
              minimumSize: const Size(double.infinity, 48),
              elevation: canResettle ? 3 : 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  RESETTLE DIALOG
  // ─────────────────────────────────────────────────────────────
  void _showResettleDialog(BuildContext context) {
    final finalAmount = billData?['final_amount'] ?? 0.0;
    final int totalAmount = (finalAmount is num)
        ? (finalAmount as num).round()
        : int.tryParse(finalAmount.toString()) ?? 0;

    final isComplimentary = _isComplimentary();

    if (isComplimentary) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.card_giftcard, color: Colors.red.shade600),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Resettle Complimentary Bill',
                  style: GoogleFonts.poppins(fontSize: 18),
                ),
              ),
            ],
          ),
          content: Text(
            'This bill is marked as complimentary. Do you want to resettle it?',
            style: GoogleFonts.poppins(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _resettleBill({'complimentary': 0}, 0);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirm Resettle'),
            ),
          ],
        ),
      );
      return;
    }

    TextEditingController amountController = TextEditingController();
    TextEditingController tipController = TextEditingController();
    TextEditingController cashController = TextEditingController();
    TextEditingController cardController = TextEditingController();
    TextEditingController upiController = TextEditingController();
    TextEditingController tipOtherController = TextEditingController();

    String selectedPaymentMethod = 'Cash';
    String? amountValidationMessage;
    String? tipValidationMessage;

    void updateOtherTip(StateSetter setState) {
      int cash = int.tryParse(cashController.text) ?? 0;
      int card = int.tryParse(cardController.text) ?? 0;
      int upi = int.tryParse(upiController.text) ?? 0;
      int totalEntered = cash + card + upi;
      int tip = 0;
      if (totalEntered > totalAmount) {
        tip = totalEntered - totalAmount;
        int diff = totalEntered - totalAmount;
        if (cash > 0) { int r = diff <= cash ? diff : cash; cash -= r; diff -= r; cashController.text = cash.toString(); }
        if (diff > 0 && card > 0) { int r = diff <= card ? diff : card; card -= r; diff -= r; cardController.text = card.toString(); }
        if (diff > 0 && upi > 0) { int r = diff <= upi ? diff : upi; upi -= r; upiController.text = upi.toString(); }
      }
      tipOtherController.text = tip.toString();
      tipValidationMessage = tip > 50 ? 'Tip is greater than ₹50!' : null;
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (builderContext, setState) {
            return Dialog(
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
                      child: Text(
                        'Resettle Bill Payment',
                        style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: Text(
                        'Bill Total: ₹$totalAmount',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Payment Method',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
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
                          onSelected: (_) => setState(() => selectedPaymentMethod = method),
                          selectedColor: Colors.teal.shade600,
                          backgroundColor: Colors.grey[200],
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w500,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    if (selectedPaymentMethod != 'Other') ...[
                      _buildDialogInput(
                        'Amount',
                        amountController,
                        Icons.attach_money,
                        hint: 'Expected: ₹$totalAmount',
                        onChanged: (value) {
                          int inputAmount = int.tryParse(value) ?? 0;
                          setState(() {
                            int tip = 0;
                            if (inputAmount > totalAmount) {
                              tip = inputAmount - totalAmount;
                              inputAmount = totalAmount;
                              amountController.text = inputAmount.toString();
                              amountController.selection = TextSelection.fromPosition(
                                  TextPosition(offset: amountController.text.length));
                            }
                            tipController.text = tip.toString();
                            amountValidationMessage = inputAmount < totalAmount
                                ? 'Amount is ₹${totalAmount - inputAmount} less than bill total'
                                : null;
                            tipValidationMessage = tip > 50 ? 'Tip is greater than ₹50!' : null;
                          });
                        },
                      ),
                      if (amountValidationMessage != null) ...[
                        const SizedBox(height: 4),
                        Text(amountValidationMessage!, style: TextStyle(color: Colors.orange.shade700, fontSize: 12)),
                      ],
                      const SizedBox(height: 12),
                      _buildDialogInput('Tip (optional)', tipController, Icons.card_giftcard),
                      if (tipValidationMessage != null) ...[
                        const SizedBox(height: 4),
                        Text(tipValidationMessage!, style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
                      ],
                    ] else ...[
                      Row(
                        children: [
                          Expanded(child: _buildDialogInput('Cash', cashController, Icons.attach_money, onChanged: (_) => setState(() => updateOtherTip(setState)))),
                          const SizedBox(width: 12),
                          Expanded(child: _buildDialogInput('Card', cardController, Icons.attach_money, onChanged: (_) => setState(() => updateOtherTip(setState)))),
                          const SizedBox(width: 12),
                          Expanded(child: _buildDialogInput('UPI', upiController, Icons.attach_money, onChanged: (_) => setState(() => updateOtherTip(setState)))),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildDialogInput('Tip (optional)', tipOtherController, Icons.card_giftcard),
                      if (tipValidationMessage != null) ...[
                        const SizedBox(height: 4),
                        Text(tipValidationMessage!, style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
                      ],
                    ],

                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal.shade600,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                          onPressed: () async {
                            Map<String, double> paymentBreakdown = {};
                            int tipAmount = 0;

                            if (selectedPaymentMethod != 'Other') {
                              int amount = int.tryParse(amountController.text) ?? 0;
                              tipAmount = int.tryParse(tipController.text) ?? 0;

                              if (amount < totalAmount) {
                                showDialog(
                                  context: builderContext,
                                  builder: (ac) => AlertDialog(
                                    title: const Text('Insufficient Amount'),
                                    content: Text('Entered amount is ₹${totalAmount - amount} less than the bill total.'),
                                    actions: [TextButton(onPressed: () => Navigator.pop(ac), child: const Text('OK'))],
                                  ),
                                );
                                return;
                              }
                              if (tipAmount > 50) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tip amount cannot exceed ₹50!')));
                                return;
                              }
                              paymentBreakdown = {selectedPaymentMethod.toLowerCase(): amount.toDouble()};
                              await _resettleBill(paymentBreakdown, tipAmount.toDouble());
                            } else {
                              int cash = int.tryParse(cashController.text) ?? 0;
                              int card = int.tryParse(cardController.text) ?? 0;
                              int upi = int.tryParse(upiController.text) ?? 0;
                              tipAmount = int.tryParse(tipOtherController.text) ?? 0;
                              int totalEntered = cash + card + upi;

                              if (totalEntered < totalAmount) {
                                showDialog(
                                  context: builderContext,
                                  builder: (ac) => AlertDialog(
                                    title: const Text('Insufficient Amount'),
                                    content: Text('Entered amount is ₹${totalAmount - totalEntered} less than the bill total.'),
                                    actions: [TextButton(onPressed: () => Navigator.pop(ac), child: const Text('OK'))],
                                  ),
                                );
                                return;
                              }
                              if (tipAmount > 50) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tip amount cannot exceed ₹50!')));
                                return;
                              }
                              if (cash > 0) paymentBreakdown['cash'] = cash.toDouble();
                              if (card > 0) paymentBreakdown['card'] = card.toDouble();
                              if (upi > 0) paymentBreakdown['upi'] = upi.toDouble();
                              await _resettleBill(paymentBreakdown, tipAmount.toDouble());
                            }

                            if (dialogContext.mounted) Navigator.pop(dialogContext);
                          },
                          child: const Text('Confirm'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDialogInput(
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
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  API CALLS
  // ─────────────────────────────────────────────────────────────
  Future<void> _resettleBill(Map<String, dynamic> paymentBreakdown, double tipAmount) async {
    try {
      final body = {
        'tip_amount': tipAmount,
        'payment_breakdown': paymentBreakdown,
      };
      final url = Uri.parse('${dotenv.env['API_URL']}/tables/bills/${widget.billId}/settle');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bill resettled successfully!')),
          );
          await _fetchBillDetails();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to resettle bill: ${response.body}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error resettling bill: $e')),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  PRINT HTML
  // ─────────────────────────────────────────────────────────────
  String _buildCombinedBillHtml() {
    final foodItems = _extractFoodItems();
    final nonAlcoholicDrinks = _extractNonAlcoholicDrinkItems();
    final alcoholicItems = _extractAlcoholicItems();
    final calculations = _buildCalculations();
    final isComplimentary = _isComplimentary();

    final cgstItems = [...foodItems, ...nonAlcoholicDrinks];
    final discountAmount = calculations['discount'] ?? 0.0;
    final subtotal = calculations['subtotal'] ?? 0.0;
    final foodDiscountPct = subtotal > 0 ? (discountAmount / subtotal) * 100 : 0.0;

    String buildItemRows(List<Map<String, dynamic>> list) {
      return list.map((item) {
        final name = item['name'];
        final qty = item['qty'];
        final price = (item['price'] as double).toStringAsFixed(2);
        final total = (item['total'] as double).toStringAsFixed(2);
        return '''
        <tr>
          <td style="font-size:24.5px;word-wrap:break-word;">$name</td>
          <td style="font-size:24.5px;text-align:center;">$qty</td>
          <td style="font-size:24.5px;text-align:center;">$price</td>
          <td style="font-size:24.5px;text-align:right;">$total</td>
        </tr>
      ''';
      }).join();
    }

    final String line = '_________________________________';
    final cashierName =
        billData?['waiter']?['name']?.toString().split(' ')[0] ?? 'N/A';
    final tableDisplay = billData?['table']?['display_number'] ??
        billData?['display_number'] ??
        billData?['table_number'] ??
        'N/A';
    final sectionName = billData?['table']?['section']?['name'] ?? billData?['section_name'] ?? '';

    return '''
  <div style="font-family: Calibri, Arial, sans-serif; width: 100%; margin:0; padding:0;">
    <div style="text-align:center;">
      <strong style="font-size:30px;">5K Family Resto & Bar</strong><br>
      <span style="font-size:22.5px;">opp: Nayara petrol pump, Near Green Leaf Hotel, Badlapur pipeline rd, Nevali, 421503</span><br>
    </div>
    <pre style="font-size:24px;text-align:center;margin:0;">$line</pre>

    <table style="width:100%;font-size:23px;margin:0;padding:0;">
      <tr>
        <td>Date: ${_formatDate1(billData?['createdAt'], mode: 'date')}</td>
        <td style="text-align:right;">Time: ${_formatDate1(billData?['createdAt'], mode: 'time')}</td>
      </tr>
      <tr>
        <td>Cashier: $cashierName</td>
        <td style="text-align:right;">Bill No.: ${widget.billNumber ?? widget.billId}</td>
      </tr>
      <tr>
        <td>Table: ${sectionName.isNotEmpty ? '$sectionName-$tableDisplay' : tableDisplay}</td>
      </tr>
    </table>
    <pre style="font-size:28px;text-align:center;margin:0;">$line</pre>

    <table style="width:100%;border-collapse:collapse;font-size:23.5px;margin:0;padding:0;">
      <thead>
        <tr>
          <th style="text-align:left;">Item</th>
          <th style="text-align:center;">Qty.</th>
          <th style="text-align:center;">Price</th>
          <th style="text-align:right;">Amount</th>
        </tr>
      </thead>
      <tbody style="font-size:24px;">
        ${cgstItems.isNotEmpty ? '''
          <tr>
            <td colspan="4" style="font-weight:bold;font-size:24px;text-align:left;">
              <pre style="font-size:24px;text-align:center;margin:0;">$line</pre>
              Food & Beverages
            </td>
          </tr>
          ${buildItemRows(cgstItems)}
        ''' : ''}

        ${alcoholicItems.isNotEmpty ? '''
          <tr>
            <td colspan="4"><pre style="font-size:24px;text-align:center;margin:4px 0;">$line</pre></td>
          </tr>
          <tr>
            <td colspan="4" style="font-weight:bold;font-size:24px;text-align:left;">Alcoholic Beverages</td>
          </tr>
          ${buildItemRows(alcoholicItems)}
        ''' : ''}
      </tbody>
    </table>

    <pre style="font-size:24px;text-align:center;margin:4px 0;">$line</pre>

    <table style="width:100%;font-size:23.5px;margin:0;padding:0;">
      <tr><td>Subtotal:</td><td style="text-align:right;">₹${(calculations['subtotal'] ?? 0).toStringAsFixed(2)}</td></tr>
      ${discountAmount > 0 ? '<tr style="font-size:21.5px;"><td>Discount (${foodDiscountPct.toStringAsFixed(1)}%):</td><td style="text-align:right;">-₹${discountAmount.toStringAsFixed(2)}</td></tr>' : ''}
      ${(calculations['serviceCharge'] ?? 0) > 0 ? '<tr style="font-size:21.5px;"><td>Service Charge:</td><td style="text-align:right;">₹${(calculations['serviceCharge'] ?? 0).toStringAsFixed(2)}</td></tr>' : ''}
      <tr style="font-size:21.5px;"><td>CGST @ 2.5%:</td><td style="text-align:right;">₹${(calculations['cgst'] ?? 0).toStringAsFixed(2)}</td></tr>
      <tr style="font-size:21.5px;"><td>SGST @ 2.5%:</td><td style="text-align:right;">₹${(calculations['sgst'] ?? 0).toStringAsFixed(2)}</td></tr>
      ${(calculations['vat'] ?? 0) > 0 ? '<tr style="font-size:21.5px;"><td>VAT @ 10%:</td><td style="text-align:right;">₹${(calculations['vat'] ?? 0).toStringAsFixed(2)}</td></tr>' : ''}
      ${(calculations['roundOff'] ?? 0) != 0 ? '<tr style="font-size:19.5px;"><td>Round Off:</td><td style="text-align:right;">₹${(calculations['roundOff'] ?? 0).toStringAsFixed(2)}</td></tr>' : ''}
      <tr style="font-weight:bold; font-size:25px;"><td>${isComplimentary ? 'COMPLIMENTARY TOTAL:' : 'GRAND TOTAL:'}</td><td style="text-align:right;">₹${isComplimentary ? '0.00' : (calculations['grandTotal'] ?? 0).toStringAsFixed(2)}</td></tr>
    </table>
    <pre style="font-size:32px;text-align:center;margin:4px 0;">$line</pre>

    <div style="text-align:center;font-size:23px;">
      Thanks for dining with us!<br>
      <strong style="margin-bottom:5px;">UNIT OF FORTUNE HOSPITALITY</strong><br>
      <span style="font-size:21.4px;">GSTIN: 27AAJFF0784D1ZH</span><br>
      <span style="font-size:21.4px;">VAT TIN: 27162432717V</span><br>
      <span style="font-size:21.4px;">FSSAI: 11524022000259</span><br>
    </div>
  </div>
  ''';
  }

  // ─────────────────────────────────────────────────────────────
  //  TEXT STYLES
  // ─────────────────────────────────────────────────────────────
  TextStyle _headerTextStyle() => GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade700,
      );

  TextStyle _itemTextStyle() => GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Colors.grey.shade700,
      );
}