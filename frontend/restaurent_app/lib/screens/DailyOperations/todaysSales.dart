import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';

// ─────────────────────────────────────────────
// DATA MODELS (unchanged)
// ─────────────────────────────────────────────

class SalesSummary {
  final double totalSales;
  final double totalCash;
  final double totalCard;
  final double totalUPI;
  final double totalTip;
  final double gst;
  final double vat;
  final double totalTax;
  final double totalComplimentaryAmount;

  SalesSummary({
    required this.totalSales,
    required this.totalCash,
    required this.totalCard,
    required this.totalUPI,
    required this.totalTip,
    required this.gst,
    required this.vat,
    required this.totalTax,
    required this.totalComplimentaryAmount,
  });

  factory SalesSummary.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    return SalesSummary(
      totalSales: parseDouble(json['totalSales']),
      totalCash: parseDouble(json['totalCash']),
      totalCard: parseDouble(json['totalCard']),
      totalUPI: parseDouble(json['totalUPI']),
      totalTip: parseDouble(json['totalTip']),
      gst: parseDouble(json['totalGST']),
      vat: parseDouble(json['totalVAT']),
      totalTax: parseDouble(json['totalTax']),
      totalComplimentaryAmount: parseDouble(json['totalComplimentaryAmount']),
    );
  }
}

class SalesData {
  final int totalSales;
  final int estimatedSales;
  SalesData({required this.totalSales, required this.estimatedSales});
}

class OrderStats {
  final int numberOfOrders;
  final double averageOrderValue;
  OrderStats({required this.numberOfOrders, required this.averageOrderValue});

  factory OrderStats.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic value) {
      if (value == null) return 0;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0;
      return 0;
    }
    return OrderStats(
      numberOfOrders: json['numberOfOrders'] ?? 0,
      averageOrderValue: parseDouble(json['averageOrderValue']),
    );
  }
}

class CustomerStats {
  final int numberOfCustomers;
  CustomerStats({required this.numberOfCustomers});

  factory CustomerStats.fromJson(Map<String, dynamic> json) {
    return CustomerStats(numberOfCustomers: json['numberOfCustomers'] ?? 0);
  }
}

class Item {
  final int menuId;
  final String name;
  final int quantitySold;
  final String percentage;

  Item({
    required this.menuId,
    required this.name,
    required this.quantitySold,
    required this.percentage,
  });

  factory Item.fromJson(Map<String, dynamic> json) {
    return Item(
      menuId: json['menuId'],
      name: json['name'],
      quantitySold: json['quantitySold'],
      percentage: json['percentage'],
    );
  }
}

// ─────────────────────────────────────────────
// DESIGN TOKENS
// ─────────────────────────────────────────────

class _AppTheme {
  static const Color bg = Color(0xFFF5F5F7);
  static const Color surface = Colors.white;
  static const Color ink = Color(0xFF0D0D0D);
  static const Color inkMuted = Color(0xFF6E6E73);
  static const Color inkFaint = Color(0xFFAEAEB2);
  static const Color border = Color(0xFFE5E5EA);
  static const Color accent = Color(0xFF0A84FF);

  // Payment method colours
  static const Color cash = Color(0xFF30D158);
  static const Color card = Color(0xFF0A84FF);
  static const Color upi = Color(0xFFFF9F0A);
  static const Color tip = Color(0xFFFF375F);

  // Tax colours
  static const Color gst = Color(0xFF5E5CE6);
  static const Color vat = Color(0xFF64D2FF);
  static const Color tax = Color(0xFF30D158);

  // Chart gradient
  static const Color chartTop = Color(0xFF0A84FF);
  static const Color chartBottom = Color(0xFF5AC8FA);
}

TextStyle _label({double size = 13, Color? color, FontWeight? weight}) =>
    GoogleFonts.dmSans(
      fontSize: size,
      color: color ?? _AppTheme.inkMuted,
      fontWeight: weight ?? FontWeight.w400,
      letterSpacing: -0.1,
    );

TextStyle _mono({double size = 16, Color? color, FontWeight? weight}) =>
    GoogleFonts.dmMono(
      fontSize: size,
      color: color ?? _AppTheme.ink,
      fontWeight: weight ?? FontWeight.w500,
    );

// ─────────────────────────────────────────────
// API HELPERS
// ─────────────────────────────────────────────

Future<SalesSummary> fetchSalesSummary() async {
  final url =
      Uri.parse('${dotenv.env['API_URL']}/admin/last7daysSales?option=today');
  final response = await http.get(url);
  if (response.statusCode == 200) {
    return SalesSummary.fromJson(json.decode(response.body));
  } else {
    throw Exception('Failed to load sales summary');
  }
}

// ─────────────────────────────────────────────
// MAIN SCREEN
// ─────────────────────────────────────────────

class TodaysSalesDashboard extends StatefulWidget {
  const TodaysSalesDashboard({super.key});

  @override
  State<TodaysSalesDashboard> createState() => _TodaysSalesDashboardState();
}

class _TodaysSalesDashboardState extends State<TodaysSalesDashboard> {
  late Future<List<Item>> _itemsFuture;
  late Future<SalesData> _todaySalesFuture;
  late Future<OrderStats> _orderStatsFuture;
  late Future<CustomerStats> _customerStatsFuture;
  late Future<SalesSummary> _salesSummaryFuture;
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    _itemsFuture = _fetchTopItems();
    _todaySalesFuture = _fetchTodaySales();
    _orderStatsFuture = _fetchOrderStats();
    _customerStatsFuture = _fetchCustomerStats();
    _salesSummaryFuture = fetchSalesSummary();
  }

  Future<List<Item>> _fetchTopItems() async {
    final response = await http.get(
        Uri.parse('${dotenv.env['API_URL']}/admin/topSelling-today'));
    if (response.statusCode == 200) {
      final jsonData = json.decode(response.body);
      final itemsJson = jsonData['items'];
      if (itemsJson == null || itemsJson is! List) return [];
      return itemsJson.map<Item>((item) => Item.fromJson(item)).toList();
    } else {
      throw Exception('Failed to load top items');
    }
  }

  Future<SalesData> _fetchTodaySales() async {
    try {
      final url = Uri.parse('${dotenv.env['API_URL']}/admin/todaySales');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        int parseInt(dynamic v) {
          if (v == null) return 0;
          if (v is int) return v;
          if (v is double) return v.toInt();
          if (v is String) return int.tryParse(v) ?? 0;
          return 0;
        }
        return SalesData(
          totalSales: parseInt(jsonData['totalSales']),
          estimatedSales: parseInt(jsonData['estimatedSales']),
        );
      } else {
        throw Exception('Failed to fetch today\'s sales');
      }
    } catch (_) {
      return SalesData(totalSales: 0, estimatedSales: 0);
    }
  }

  Future<OrderStats> _fetchOrderStats() async {
    final response = await http.get(
        Uri.parse('${dotenv.env['API_URL']}/admin/todays-Order-Stats'));
    if (response.statusCode == 200) {
      return OrderStats.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to load order stats');
    }
  }

  Future<CustomerStats> _fetchCustomerStats() async {
    final response = await http.get(
        Uri.parse('${dotenv.env['API_URL']}/admin/todays-Customer-Stats'));
    if (response.statusCode == 200) {
      return CustomerStats.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to load customer stats');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _AppTheme.bg,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── App Bar ───────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Row(
                  children: [
                    // Back button
                    GestureDetector(
                      onTap: () => Navigator.of(context).maybePop(),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _AppTheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _AppTheme.border),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 16,
                          color: _AppTheme.ink,
                        ),
                      ),
                    ),

                    const SizedBox(width: 14),

                    // Title group
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('EEEE, d MMM yyyy').format(DateTime.now()),
                            style: _label(size: 11, color: _AppTheme.inkFaint),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            "Today's Sales",
                            style: GoogleFonts.dmSans(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: _AppTheme.ink,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Refresh button
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _itemsFuture = _fetchTopItems();
                          _todaySalesFuture = _fetchTodaySales();
                          _orderStatsFuture = _fetchOrderStats();
                          _customerStatsFuture = _fetchCustomerStats();
                          _salesSummaryFuture = fetchSalesSummary();
                        });
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _AppTheme.ink,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: _AppTheme.ink.withOpacity(0.18),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.refresh_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── KPI Grid ──────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: _KpiGrid(
                  todaySalesFuture: _todaySalesFuture,
                  orderStatsFuture: _orderStatsFuture,
                  customerStatsFuture: _customerStatsFuture,
                  salesSummaryFuture: _salesSummaryFuture,
                ),
              ),
            ),

            // ── Hourly Sales ──────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                child: _SectionHeader(title: 'Hourly Sales'),
              ),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 12),
            ),
            const SliverToBoxAdapter(
              child: ScrollableHourlySalesChart(),
            ),

            // ── Payment Methods ───────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                child: _SectionHeader(title: 'Payment Breakdown'),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: _BreakdownCard(
                  future: _salesSummaryFuture,
                  rows: (s) => [
                    _BarRow(
                        label: 'Cash',
                        amount: s.totalCash,
                        max: s.totalSales,
                        color: _AppTheme.cash),
                    _BarRow(
                        label: 'Card',
                        amount: s.totalCard,
                        max: s.totalSales,
                        color: _AppTheme.card),
                    _BarRow(
                        label: 'UPI',
                        amount: s.totalUPI,
                        max: s.totalSales,
                        color: _AppTheme.upi),
                    _BarRow(
                        label: 'Tip',
                        amount: s.totalTip,
                        max: s.totalSales,
                        color: _AppTheme.tip),
                  ],
                ),
              ),
            ),

            // ── Tax Breakdown ─────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: _SectionHeader(title: 'Tax Breakdown'),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: _BreakdownCard(
                  future: _salesSummaryFuture,
                  rows: (s) => [
                    _BarRow(
                        label: 'GST',
                        amount: s.gst,
                        max: s.totalSales,
                        color: _AppTheme.gst),
                    _BarRow(
                        label: 'VAT',
                        amount: s.vat,
                        max: s.totalSales,
                        color: _AppTheme.vat),
                    _BarRow(
                        label: 'Total Tax',
                        amount: s.totalTax,
                        max: s.totalSales,
                        color: _AppTheme.tax),
                  ],
                ),
              ),
            ),

            // ── Top Items ─────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                child: _SectionHeader(title: 'Top Items'),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: FutureBuilder<List<Item>>(
                  future: _itemsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator());
                    } else if (snapshot.hasError ||
                        !snapshot.hasData ||
                        snapshot.data!.isEmpty) {
                      return Center(
                          child: Text('No items found',
                              style: _label()));
                    }
                    final items = snapshot.data!;
                    final visible =
                        _showAll ? items : items.take(5).toList();
                    return Column(
                      children: [
                        _ItemsCard(items: visible),
                        if (items.length > 5) ...[
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () =>
                                setState(() => _showAll = !_showAll),
                            child: Center(
                              child: Text(
                                _showAll ? 'Show less' : 'Show all',
                                style: _label(
                                    color: _AppTheme.accent,
                                    weight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ]
                      ],
                    );
                  },
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// KPI GRID
// ─────────────────────────────────────────────

class _KpiGrid extends StatelessWidget {
  final Future<SalesData> todaySalesFuture;
  final Future<OrderStats> orderStatsFuture;
  final Future<CustomerStats> customerStatsFuture;
  final Future<SalesSummary> salesSummaryFuture;

  const _KpiGrid({
    required this.todaySalesFuture,
    required this.orderStatsFuture,
    required this.customerStatsFuture,
    required this.salesSummaryFuture,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Full-width total sales card
        FutureBuilder<SalesData>(
          future: todaySalesFuture,
          builder: (context, snap) {
            final loading = snap.connectionState == ConnectionState.waiting;
            final sales = snap.data;
            return _HeroKpiCard(
              label: 'Total Revenue',
              value: loading
                  ? '—'
                  : '₹${NumberFormat('#,##0').format(sales?.totalSales ?? 0)}',
              sub: loading
                  ? null
                  : 'Est. ₹${NumberFormat('#,##0').format((sales?.estimatedSales ?? 0) + (sales?.totalSales ?? 0))}',
              icon: Icons.trending_up_rounded,
            );
          },
        ),

        const SizedBox(height: 10),

        // 2-column grid
        Row(
          children: [
            Expanded(
              child: FutureBuilder<OrderStats>(
                future: orderStatsFuture,
                builder: (context, snap) {
                  final loading =
                      snap.connectionState == ConnectionState.waiting;
                  return Column(
                    children: [
                      _SmallKpiCard(
                        label: 'Orders',
                        value:
                            loading ? '—' : '${snap.data?.numberOfOrders ?? 0}',
                        icon: Icons.receipt_long_rounded,
                        iconColor: _AppTheme.upi,
                      ),
                      const SizedBox(height: 10),
                      _SmallKpiCard(
                        label: 'Avg Order',
                        value: loading
                            ? '—'
                            : '₹${snap.data?.averageOrderValue.toStringAsFixed(0) ?? '0'}',
                        icon: Icons.bar_chart_rounded,
                        iconColor: _AppTheme.card,
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                children: [
                  FutureBuilder<CustomerStats>(
                    future: customerStatsFuture,
                    builder: (context, snap) {
                      final loading =
                          snap.connectionState == ConnectionState.waiting;
                      return _SmallKpiCard(
                        label: 'Customers',
                        value: loading
                            ? '—'
                            : '${snap.data?.numberOfCustomers ?? 0}',
                        icon: Icons.people_alt_rounded,
                        iconColor: _AppTheme.cash,
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  FutureBuilder<SalesSummary>(
                    future: salesSummaryFuture,
                    builder: (context, snap) {
                      final loading =
                          snap.connectionState == ConnectionState.waiting;
                      return _SmallKpiCard(
                        label: 'Complimentary',
                        value: loading
                            ? '—'
                            : '₹${NumberFormat('#,##0').format(snap.data?.totalComplimentaryAmount ?? 0)}',
                        icon: Icons.card_giftcard_rounded,
                        iconColor: _AppTheme.tip,
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HeroKpiCard extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final IconData icon;

  const _HeroKpiCard({
    required this.label,
    required this.value,
    this.sub,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F3460).withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Text(label,
                  style: _label(
                      color: Colors.white.withOpacity(0.55),
                      size: 13,
                      weight: FontWeight.w500)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF30D158).withOpacity(0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.arrow_upward_rounded,
                        size: 10, color: Color(0xFF30D158)),
                    const SizedBox(width: 3),
                    Text('Live',
                        style: _label(
                            size: 10,
                            color: const Color(0xFF30D158),
                            weight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: GoogleFonts.dmMono(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -1.5,
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 11, color: Color(0xFF64D2FF)),
                const SizedBox(width: 4),
                Text(
                  sub!,
                  style: _label(
                      color: const Color(0xFF64D2FF).withOpacity(0.8),
                      size: 11),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SmallKpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;

  const _SmallKpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: iconColor, size: 15),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(value, style: _mono(size: 20, weight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(label, style: _label(size: 11)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SECTION HEADER
// ─────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: GoogleFonts.dmSans(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: _AppTheme.ink,
        letterSpacing: -0.3,
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SCROLLABLE HOURLY SALES CHART
// ─────────────────────────────────────────────

class ScrollableHourlySalesChart extends StatefulWidget {
  const ScrollableHourlySalesChart({super.key});

  @override
  State<ScrollableHourlySalesChart> createState() =>
      _ScrollableHourlySalesChartState();
}

class _ScrollableHourlySalesChartState
    extends State<ScrollableHourlySalesChart> {
  List<Map<String, dynamic>> _hourlySales = [];
  bool _isLoading = true;
  int? _selectedIndex;

  // How wide each bar "slot" is — controls scrollability
  static const double _barSlotWidth = 56.0;
  static const double _chartHeight = 180.0;

  @override
  void initState() {
    super.initState();
    _fetchHourlySales();
  }

  Future<void> _fetchHourlySales() async {
    try {
      final response = await http.get(Uri.parse(
          '${dotenv.env['API_URL']}/admin/last7daysSales?option=today'));
      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        final List<dynamic> dailyBreakdown = jsonData['dailyBreakdown'];
        final processed = dailyBreakdown.map((entry) {
          return {
            'label': entry['timeSlot'] ?? '',
            'total': (entry['total'] as num?)?.toDouble() ?? 0.0,
          };
        }).toList();

        if (mounted) {
          setState(() {
            _hourlySales = processed;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_hourlySales.isEmpty) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Text('No hourly data available', style: _label()),
        ),
      );
    }

    final double maxSale = _hourlySales
        .map((e) => e['total'] as double)
        .fold(0.0, (a, b) => b > a ? b : a);

    final double stepSize = maxSale > 50000
        ? 20000
        : (maxSale > 20000 ? 10000 : (maxSale > 5000 ? 5000 : 1000));
    final double maxY = maxSale > 0
        ? ((maxSale / stepSize).ceil() * stepSize) + stepSize
        : stepSize * 2;

    // Total width required for bars
    final double totalChartWidth = _hourlySales.length * _barSlotWidth;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Selected tooltip
          AnimatedSize(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeInOut,
            child: _selectedIndex != null
                ? Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _AppTheme.ink,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: _AppTheme.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _hourlySales[_selectedIndex!]['label'],
                            style: _label(
                                weight: FontWeight.w600,
                                color: Colors.white,
                                size: 13),
                          ),
                        ),
                        Text(
                          '₹${NumberFormat('#,##0').format(_hourlySales[_selectedIndex!]['total'])}',
                          style: _label(
                              color: _AppTheme.accent,
                              weight: FontWeight.w700,
                              size: 13),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: () =>
                              setState(() => _selectedIndex = null),
                          child: const Icon(Icons.close_rounded,
                              size: 16, color: _AppTheme.inkFaint),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          // Scrollable chart area
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: SizedBox(
              width: totalChartWidth,
              height: _chartHeight,
              child: BarChart(
                BarChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: stepSize,
                    getDrawingHorizontalLine: (_) => const FlLine(
                      color: Color(0xFFEEEEEF),
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        interval: 1,
                        getTitlesWidget: (value, _) {
                          final i = value.toInt();
                          if (i >= 0 && i < _hourlySales.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                _hourlySales[i]['label'],
                                style: GoogleFonts.dmSans(
                                  fontSize: 9,
                                  color: _AppTheme.inkFaint,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: const Border(
                      bottom:
                          BorderSide(color: Color(0xFFEEEEEF), width: 1),
                    ),
                  ),
                  minY: 0,
                  maxY: maxY,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (_, __, ___, ____) => null,
                    ),
                    handleBuiltInTouches: true,
                    touchCallback: (FlTouchEvent event, BarTouchResponse? response) {
                      // Only respond to a definitive tap — not drag/hover events
                      if (event is! FlTapUpEvent && event is! FlPanEndEvent) {
                        return;
                      }
                      if (response == null || response.spot == null) {
                        if (_selectedIndex != null) {
                          setState(() {
                            _selectedIndex = null;
                          });
                        }
                        return;
                      }
                      final tapped = response.spot!.touchedBarGroupIndex;
                      setState(() {
                        _selectedIndex = _selectedIndex == tapped ? null : tapped;
                      });
                    },
                  ),
                  barGroups: List.generate(_hourlySales.length, (i) {
                    final val = _hourlySales[i]['total'] as double;
                    final isSelected = _selectedIndex == i;
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: val > 0 ? val : 0.4,
                          width: 28,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(6),
                            topRight: Radius.circular(6),
                          ),
                          gradient: LinearGradient(
                            colors: val > 0
                                ? isSelected
                                    ? [
                                        _AppTheme.accent,
                                        _AppTheme.accent.withOpacity(0.6),
                                      ]
                                    : [
                                        _AppTheme.chartTop.withOpacity(0.85),
                                        _AppTheme.chartBottom.withOpacity(0.4),
                                      ]
                                : [
                                    const Color(0xFFEEEEEF),
                                    const Color(0xFFEEEEEF),
                                  ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ),

          // Scroll hint
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.swipe_rounded,
                  size: 12, color: _AppTheme.inkFaint),
              const SizedBox(width: 4),
              Text('Scroll to see more',
                  style: _label(size: 10, color: _AppTheme.inkFaint)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// BREAKDOWN CARD (Payment / Tax)
// ─────────────────────────────────────────────

class _BreakdownCard extends StatelessWidget {
  final Future<SalesSummary> future;
  final List<_BarRow> Function(SalesSummary) rows;

  const _BreakdownCard({required this.future, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: FutureBuilder<SalesSummary>(
        future: future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || !snap.hasData) {
            return Center(child: Text('Could not load', style: _label()));
          }
          return Column(
            children:
                rows(snap.data!).map((r) => _BarRowWidget(row: r)).toList(),
          );
        },
      ),
    );
  }
}

class _BarRow {
  final String label;
  final double amount;
  final double max;
  final Color color;
  const _BarRow(
      {required this.label,
      required this.amount,
      required this.max,
      required this.color});
}

class _BarRowWidget extends StatelessWidget {
  final _BarRow row;
  const _BarRowWidget({required this.row});

  @override
  Widget build(BuildContext context) {
    final pct = row.max > 0 ? (row.amount / row.max).clamp(0.0, 1.0) : 0.0;
    final fmt = '₹${NumberFormat('#,##0').format(row.amount)}';
    final pctLabel = '${(pct * 100).toStringAsFixed(1)}%';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: row.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(row.label, style: _label(size: 13, weight: FontWeight.w500, color: _AppTheme.ink)),
                ],
              ),
              const Spacer(),
              Text(pctLabel, style: _label(size: 11, color: _AppTheme.inkFaint)),
              const SizedBox(width: 12),
              SizedBox(
                width: 80,
                child: Text(
                  fmt,
                  textAlign: TextAlign.right,
                  style: _mono(size: 13, weight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              children: [
                Container(height: 6, color: const Color(0xFFF0F0F2)),
                FractionallySizedBox(
                  widthFactor: pct,
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: row.color,
                      borderRadius: BorderRadius.circular(6),
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
}

// ─────────────────────────────────────────────
// TOP ITEMS CARD
// ─────────────────────────────────────────────

class _ItemsCard extends StatelessWidget {
  final List<Item> items;
  const _ItemsCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: items.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          final isLast = i == items.length - 1;
          return Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: i == 0
                            ? _AppTheme.ink
                            : const Color(0xFFF0F0F2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${i + 1}',
                        style: GoogleFonts.dmMono(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color:
                              i == 0 ? Colors.white : _AppTheme.inkMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item.name,
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _AppTheme.ink,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${item.quantitySold} sold',
                      style: _label(size: 12, color: _AppTheme.inkMuted),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F0F2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        item.percentage,
                        style: _label(
                            size: 11,
                            weight: FontWeight.w600,
                            color: _AppTheme.ink),
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLast)
                Divider(
                    height: 1,
                    thickness: 1,
                    color: _AppTheme.border,
                    indent: 56),
            ],
          );
        }).toList(),
      ),
    );
  }
}