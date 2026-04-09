// Keep existing imports
import 'package:Neevika/screens/DailyOperations/low_stock.dart';
import 'package:Neevika/screens/DailyOperations/running_orders.dart';
import 'package:Neevika/screens/DailyOperations/todaysSales.dart';
import 'package:Neevika/screens/Tables/TablesScreen.dart';
import 'package:Neevika/widgets/sidebar.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/intl.dart';

// ─────────────────────────────────────────────
// DESIGN TOKENS (shared with TodaysSalesDashboard)
// ─────────────────────────────────────────────

class _T {
  static const Color bg = Color(0xFFF5F5F7);
  static const Color surface = Colors.white;
  static const Color ink = Color(0xFF0D0D0D);
  static const Color inkMuted = Color(0xFF6E6E73);
  static const Color inkFaint = Color(0xFFAEAEB2);
  static const Color border = Color(0xFFE5E5EA);
  static const Color accent = Color(0xFF0A84FF);
  static const Color green = Color(0xFF30D158);
  static const Color red = Color(0xFFFF375F);
  static const Color amber = Color(0xFFFF9F0A);
  static const Color purple = Color(0xFF5E5CE6);
}

TextStyle _label({double size = 13, Color? color, FontWeight? weight}) =>
    GoogleFonts.dmSans(
      fontSize: size,
      color: color ?? _T.inkMuted,
      fontWeight: weight ?? FontWeight.w400,
      letterSpacing: -0.1,
    );

TextStyle _mono({double size = 16, Color? color, FontWeight? weight}) =>
    GoogleFonts.dmMono(
      fontSize: size,
      color: color ?? _T.ink,
      fontWeight: weight ?? FontWeight.w500,
    );

TextStyle _heading({double size = 16, Color? color}) => GoogleFonts.dmSans(
      fontSize: size,
      color: color ?? _T.ink,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
    );

// ─────────────────────────────────────────────
// SERVICE (unchanged logic)
// ─────────────────────────────────────────────

class DashboardService {
  Future<Map<String, dynamic>> fetchTodaySales() async {
    final response = await http.get(
      Uri.parse('${dotenv.env['API_URL']}/admin/todaySales'),
    );
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> fetchSalesOverview(String option) async {
    final uri = Uri.parse(
        '${dotenv.env['API_URL']}/admin/last7daysSales?option=$option');
    final response = await http.get(uri);
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> fetchTables() async {
    final response =
        await http.get(Uri.parse('${dotenv.env['API_URL']}/admin/tables'));
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> fetchOrders() async {
    final response =
        await http.get(Uri.parse('${dotenv.env['API_URL']}/admin/orders'));
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> fetchLowStock() async {
    final response =
        await http.get(Uri.parse('${dotenv.env['API_URL']}/admin/lowStock'));
    return jsonDecode(response.body);
  }
}

// ─────────────────────────────────────────────
// DASHBOARD SCREEN
// ─────────────────────────────────────────────

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DashboardService _service = DashboardService();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  Map<String, dynamic>? todaySales;
  Map<String, dynamic>? salesOverview;
  Map<String, dynamic>? tables;
  Map<String, dynamic>? orders;
  Map<String, dynamic>? lowStock;
  bool isLoading = true;
  bool isChartLoading = false;
  double? todayVsYesterdayGrowth;
  String? _selectedDropdownValue;
  String? chartRangeLabel;

  final Map<String, String> _options = {
    'Today': 'today',
    'Yesterday': 'yesterday',
    'Last 7 days': 'last7days',
    'Last 30 days': 'last30days',
    'This Month': 'thisMonth',
    'Last Month': 'lastMonth',
  };
  String _selectedOptionLabel = 'Today';
  String _selectedOptionValue = 'today';

  @override
  void initState() {
    super.initState();
    _fetchAll(initialOption: _selectedOptionValue);
  }

  Map<String, double> _aggregateTotalsByDate(List<dynamic> breakdown) {
    final Map<String, double> map = {};
    for (final item in breakdown) {
      try {
        final String date = item['date'] as String;
        final double val = (item['total'] as num).toDouble();
        map[date] = (map[date] ?? 0.0) + val;
      } catch (_) {}
    }
    return map;
  }

  String _shortMonth(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[(month - 1).clamp(0, 11)];
  }

  String _formatFullDateStr(String isoDate) {
    try {
      final d = DateTime.parse(isoDate).toLocal();
      return '${d.day.toString().padLeft(2, '0')} ${_shortMonth(d.month)} ${d.year}';
    } catch (_) {
      return isoDate;
    }
  }

  double? _computeGrowth(List<dynamic> breakdown) {
    if (breakdown.isEmpty) return null;
    final totalsByDate = _aggregateTotalsByDate(breakdown);
    final sorted = totalsByDate.keys.toList()..sort();
    if (sorted.length < 2) return null;
    final todayT = totalsByDate[sorted.last] ?? 0.0;
    final yestT = totalsByDate[sorted[sorted.length - 2]] ?? 0.0;
    if (yestT == 0) return todayT == 0 ? 0.0 : 100.0;
    return ((todayT - yestT) / yestT) * 100.0;
  }

  String? _computeRangeLabel(List<dynamic> breakdown) {
    try {
      if (breakdown.isEmpty || !breakdown[0].containsKey('date')) return null;
      final dates = breakdown.map<String>((e) => e['date'] as String).toList()
        ..sort();
      return '${_formatFullDateStr(dates.first)}  —  ${_formatFullDateStr(dates.last)}';
    } catch (_) {
      return null;
    }
  }

  Future<void> _fetchAll({required String initialOption}) async {
    setState(() {
      isLoading = true;
      isChartLoading = true;
    });
    try {
      final results = await Future.wait([
        _service.fetchTodaySales(),
        _service.fetchSalesOverview(initialOption),
        _service.fetchTables(),
        _service.fetchOrders(),
        _service.fetchLowStock(),
      ]);
      final breakdown =
          (results[1]['dailyBreakdown'] ?? []) as List<dynamic>;
      if (!mounted) return;
      setState(() {
        todaySales = results[0];
        salesOverview = results[1];
        tables = results[2];
        orders = results[3];
        lowStock = results[4];
        isLoading = false;
        isChartLoading = false;
        todayVsYesterdayGrowth = _computeGrowth(breakdown);
        chartRangeLabel = _computeRangeLabel(breakdown);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        isChartLoading = false;
      });
    }
  }

  Future<void> _onPeriodChanged(String? newLabel) async {
    if (newLabel == null) return;
    final newValue = _options[newLabel]!;
    setState(() {
      _selectedOptionLabel = newLabel;
      _selectedOptionValue = newValue;
      isChartLoading = true;
    });
    try {
      final data = await _service.fetchSalesOverview(newValue);
      final breakdown = (data['dailyBreakdown'] ?? []) as List<dynamic>;
      if (!mounted) return;
      setState(() {
        salesOverview = data;
        todayVsYesterdayGrowth = _computeGrowth(breakdown);
        isChartLoading = false;
        chartRangeLabel = _computeRangeLabel(breakdown);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => isChartLoading = false);
    }
  }

  // ── BUILD ──────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final double? todaySalesVal = todaySales?['totalSales'] != null
        ? (todaySales!['totalSales'] as num).toDouble()
        : null;
    final double? estimateSalesVal = todaySales?['estimatedSales'] != null
        ? (todaySales!['estimatedSales'] as num).toDouble()
        : null;
    final double? totalEstimate =
        (todaySalesVal ?? 0) + (estimateSalesVal ?? 0);

    final double? salesOverviewTotal = salesOverview?['totalSales'] != null
        ? (salesOverview!['totalSales'] as num).toDouble()
        : null;

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: _T.bg,
        drawer: const Sidebar(),
        body: SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── HEADER ──────────────────────────────
              SliverToBoxAdapter(
                child: _buildHeader(),
              ),

              // ── REVENUE HERO CARD ────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: _RevenueHeroCard(
                    salesValue: todaySalesVal,
                    estimateValue: estimateSalesVal,
                    growth: todayVsYesterdayGrowth,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => TodaysSalesDashboard()),
                    ),
                  ),
                ),
              ),

              // ── METRIC CARDS ─────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: _MetricGrid(
                    tables: tables,
                    orders: orders,
                    lowStock: lowStock,
                    context: context,
                  ),
                ),
              ),

              // ── SALES OVERVIEW HEADER ────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
                  child: _SectionRow(
                    title: 'Sales Overview',
                    trailing: _PeriodDropdown(
                      options: _options,
                      selectedLabel: _selectedDropdownValue ?? _selectedOptionLabel,
                      onChanged: (val) {
                        setState(() => _selectedDropdownValue = val);
                        _onPeriodChanged(val);
                      },
                    ),
                  ),
                ),
              ),

              // ── SALES OVERVIEW CARD ───────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _SalesOverviewCard(
                    selectedOptionLabel: _selectedDropdownValue ?? _selectedOptionLabel,
                    salesOverviewTotal: salesOverviewTotal,
                    estimateSalesVal: estimateSalesVal,
                    chartRangeLabel: chartRangeLabel,
                    isChartLoading: isChartLoading,
                    chartWidget: isChartLoading
                        ? const SizedBox(
                            height: 220,
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : _SalesBarChart(
                            salesOverview: salesOverview,
                            shortMonth: _shortMonth,
                          ),
                  ),
                ),
              ),

              // ── EXPENSES ──────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: _buildExpensesCard(),
                ),
              ),

              // ── ORDER DISTRIBUTION ───────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
                  child: Text('Order Distribution', style: _heading()),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _T.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: _T.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const PieChartSample2(),
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        ),
      ),
    );
  }

  // ── HEADER ──────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          // Hamburger / drawer button
          GestureDetector(
            onTap: () => _scaffoldKey.currentState?.openDrawer(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _T.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _T.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.menu_rounded,
                size: 20,
                color: _T.ink,
              ),
            ),
          ),

          const SizedBox(width: 14),

          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('EEEE, d MMM yyyy').format(DateTime.now()),
                  style: _label(size: 11, color: _T.inkFaint),
                ),
                const SizedBox(height: 1),
                Text('Dashboard', style: _heading(size: 20)),
              ],
            ),
          ),

          // Refresh button
          GestureDetector(
            onTap: () => _fetchAll(initialOption: _selectedOptionValue),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _T.ink,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: _T.ink.withOpacity(0.18),
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
    );
  }

  // ── EXPENSES CARD ──────────────────────────────

  Widget _buildExpensesCard() {
    final expenses = [
      {'label': 'Electricity', 'value': '₹0', 'icon': Icons.bolt_rounded},
      {
        'label': 'Petty Cash',
        'value': '₹0',
        'icon': Icons.account_balance_wallet_rounded
      },
      {'label': 'Advertisement', 'value': '₹0', 'icon': Icons.campaign_rounded},
      {'label': 'Other', 'value': '₹0', 'icon': Icons.more_horiz_rounded},
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _T.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _T.border),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: _T.amber.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(Icons.receipt_long_rounded,
                        size: 15, color: _T.amber),
                  ),
                  const SizedBox(width: 10),
                  Text('Expenses', style: _heading(size: 15)),
                ],
              ),
              Text('₹0', style: _mono(size: 15, color: _T.amber, weight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 18),
          ...expenses.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    Icon(e['icon'] as IconData,
                        size: 16, color: _T.inkFaint),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(e['label'] as String,
                            style: _label(size: 13, color: _T.ink))),
                    Text(e['value'] as String,
                        style: _mono(size: 13, weight: FontWeight.w600)),
                  ],
                ),
              )),
          Divider(height: 20, color: _T.border),
          GestureDetector(
            onTap: () => debugPrint('View expenses clicked'),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('View all',
                    style: _label(
                        size: 13,
                        color: _T.accent,
                        weight: FontWeight.w600)),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward_ios_rounded,
                    size: 11, color: _T.accent),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// REVENUE HERO CARD
// ─────────────────────────────────────────────

class _RevenueHeroCard extends StatelessWidget {
  final double? salesValue;
  final double? estimateValue;
  final double? growth;
  final VoidCallback onTap;

  const _RevenueHeroCard({
    required this.salesValue,
    required this.estimateValue,
    required this.growth,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(
        locale: 'en_IN', symbol: '', decimalDigits: 0);
    final revenue =
        salesValue != null ? '₹${fmt.format(salesValue)}' : '₹0';
    final totalEst = (salesValue ?? 0) + (estimateValue ?? 0);
    final showEst =
        estimateValue != null && estimateValue! > 0 && totalEst != salesValue;

    final isUp = growth == null || growth! >= 0;
    final growthStr = growth != null
        ? '${isUp ? '↑' : '↓'} ${growth!.abs().toStringAsFixed(1)}% vs yesterday'
        : null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
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
                  child: const Icon(Icons.trending_up_rounded,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Text("Today's Revenue",
                    style: _label(
                        color: Colors.white.withOpacity(0.55),
                        size: 13,
                        weight: FontWeight.w500)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _T.green.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.circle, size: 6, color: _T.green),
                      const SizedBox(width: 4),
                      Text('Live',
                          style: _label(
                              size: 10,
                              color: _T.green,
                              weight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              revenue,
              style: GoogleFonts.dmMono(
                fontSize: 34,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -1.5,
              ),
            ),
            if (showEst) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 11, color: Color(0xFF64D2FF)),
                  const SizedBox(width: 4),
                  Text(
                    'Est. ₹${fmt.format(totalEst)} total',
                    style: _label(
                        color:
                            const Color(0xFF64D2FF).withOpacity(0.8),
                        size: 11),
                  ),
                ],
              ),
            ],
            if (growthStr != null) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (isUp ? _T.green : _T.red).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  growthStr,
                  style: _label(
                      size: 12,
                      color: isUp ? _T.green : _T.red,
                      weight: FontWeight.w600),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Text('Tap to view full report',
                    style: _label(
                        color: Colors.white.withOpacity(0.4), size: 11)),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward_ios_rounded,
                    size: 9, color: Colors.white.withOpacity(0.4)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// METRIC GRID (Tables / Orders / Stock)
// ─────────────────────────────────────────────

class _MetricGrid extends StatelessWidget {
  final Map<String, dynamic>? tables;
  final Map<String, dynamic>? orders;
  final Map<String, dynamic>? lowStock;
  final BuildContext context;

  const _MetricGrid({
    required this.tables,
    required this.orders,
    required this.lowStock,
    required this.context,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      _MetricItem(
        label: 'Tables Occupied',
        value: tables != null
            ? '${tables!['occupied']}/${tables!['total']}'
            : '—',
        sub: tables != null && tables!['avgOccupiedMinutes'] != null && tables!['avgOccupiedMinutes'] > 0
            ? 'Avg: ${(tables!['avgOccupiedMinutes'] as num) >= 60 ? '${(tables!['avgOccupiedMinutes'] as num) ~/ 60}h ' : ''}${(tables!['avgOccupiedMinutes'] as num) % 60}m'
            : 'Currently occupied',
        icon: Icons.table_restaurant_rounded,
        iconColor: _T.accent,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => ViewTableScreen())),
      ),
      _MetricItem(
        label: 'Active Orders',
        value: orders != null ? '${orders!['total']}' : '—',
        sub: 'Orders in progress',
        icon: Icons.receipt_rounded,
        iconColor: _T.purple,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => RunningOrdersPage())),
      ),
      _MetricItem(
        label: 'Low Stock',
        value: lowStock != null ? '${lowStock!['totalAffected']}' : '—',
        sub: 'Items need restock',
        icon: Icons.inventory_2_rounded,
        iconColor: _T.red,
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => LowStockPage())),
      ),
    ];

    return Row(
      children: items.map((item) {
        final isLast = item == items.last;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: isLast ? 0 : 10),
            child: GestureDetector(
              onTap: item.onTap,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _T.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _T.border),
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
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: item.iconColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(item.icon,
                          size: 15, color: item.iconColor),
                    ),
                    const SizedBox(height: 10),
                    Text(item.value,
                        style: _mono(size: 20, weight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(item.label,
                        style: _label(size: 10),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _MetricItem {
  final String label, value, sub;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;
  const _MetricItem(
      {required this.label,
      required this.value,
      required this.sub,
      required this.icon,
      required this.iconColor,
      required this.onTap});
}

// ─────────────────────────────────────────────
// SECTION ROW HEADER
// ─────────────────────────────────────────────

class _SectionRow extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const _SectionRow({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: _heading())),
        if (trailing != null) trailing!,
      ],
    );
  }
}

// ─────────────────────────────────────────────
// PERIOD DROPDOWN
// ─────────────────────────────────────────────

class _PeriodDropdown extends StatelessWidget {
  final Map<String, String> options;
  final String selectedLabel;
  final ValueChanged<String?> onChanged;

  const _PeriodDropdown({
    required this.options,
    required this.selectedLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      decoration: BoxDecoration(
        color: _T.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _T.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedLabel,
          isDense: true,
          style: _label(size: 13, color: _T.ink, weight: FontWeight.w500),
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              size: 18, color: _T.inkMuted),
          items: options.keys
              .map((label) => DropdownMenuItem<String>(
                    value: label,
                    child: Text(label),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SALES OVERVIEW CARD
// ─────────────────────────────────────────────

class _SalesOverviewCard extends StatelessWidget {
  final String selectedOptionLabel;
  final double? salesOverviewTotal;
  final double? estimateSalesVal;
  final String? chartRangeLabel;
  final bool isChartLoading;
  final Widget chartWidget;

  const _SalesOverviewCard({
    required this.selectedOptionLabel,
    required this.salesOverviewTotal,
    required this.estimateSalesVal,
    required this.chartRangeLabel,
    required this.isChartLoading,
    required this.chartWidget,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(
        locale: 'en_IN', symbol: '', decimalDigits: 0);

    String salesTitle = selectedOptionLabel == 'Today'
        ? "Today's Sale"
        : selectedOptionLabel == 'Yesterday'
            ? "Yesterday's Sale"
            : "$selectedOptionLabel Sales";

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _T.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _T.border),
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
          // Date range subtitle
          if (chartRangeLabel != null)
            Text(chartRangeLabel!,
                style: _label(size: 11, color: _T.inkFaint)),

          // Total amount
          if (salesOverviewTotal != null) ...[
            const SizedBox(height: 12),
            Text(salesTitle, style: _label(size: 12)),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${fmt.format(salesOverviewTotal)}',
                  style: _mono(
                      size: 26,
                      weight: FontWeight.w700,
                      color: _T.green),
                ),
                if (selectedOptionLabel == 'Today' &&
                    estimateSalesVal != null &&
                    estimateSalesVal! > 0) ...[
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      'Est. ₹${fmt.format((salesOverviewTotal ?? 0) + estimateSalesVal!)}',
                      style:
                          _label(size: 12, color: _T.green.withOpacity(0.7)),
                    ),
                  ),
                ],
              ],
            ),
          ],

          const SizedBox(height: 16),
          chartWidget,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SALES BAR CHART (scrollable, self-contained state)
// ─────────────────────────────────────────────

class _SalesBarChart extends StatefulWidget {
  final Map<String, dynamic>? salesOverview;
  final String Function(int) shortMonth;

  const _SalesBarChart({
    required this.salesOverview,
    required this.shortMonth,
  });

  @override
  State<_SalesBarChart> createState() => _SalesBarChartState();
}

class _SalesBarChartState extends State<_SalesBarChart> {
  int? _selectedIndex;
  double? _selectedValue;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void didUpdateWidget(_SalesBarChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Clear selection when data changes (e.g. user picks a new period)
    if (oldWidget.salesOverview != widget.salesOverview) {
      setState(() {
        _selectedIndex = null;
        _selectedValue = null;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<dynamic> breakdown =
        widget.salesOverview?['dailyBreakdown'] ?? [];

    if (breakdown.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Text('No sales data available', style: _label()),
        ),
      );
    }

    final bool isTimeSlot =
        breakdown.isNotEmpty && breakdown[0].containsKey('timeSlot');

    final List<String> labels = breakdown.map<String>((day) {
      if (isTimeSlot) return (day['timeSlot'] as String?) ?? 'N/A';
      try {
        final date = DateTime.parse(day['date'] as String).toLocal();
        const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        return '${date.day.toString().padLeft(2, '0')} ${widget.shortMonth(date.month)}\n${days[date.weekday - 1]}';
      } catch (_) {
        return 'N/A';
      }
    }).toList();

    final double maxSale = breakdown
        .map((d) => (d['total'] as num).toDouble())
        .fold(0.0, (a, b) => b > a ? b : a);

    final double stepSize = maxSale > 50000
        ? 20000
        : (maxSale > 20000 ? 10000 : (maxSale > 5000 ? 5000 : 1000));
    final double maxY = maxSale > 0
        ? ((maxSale / stepSize).ceil() * stepSize) + stepSize
        : stepSize * 2;

    final double chartWidth = labels.length * 60.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Tooltip ──────────────────────────────
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
                    color: _T.ink,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                            color: _T.accent, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          labels[_selectedIndex!].replaceAll('\n', '  '),
                          style: _label(
                              color: Colors.white,
                              weight: FontWeight.w600,
                              size: 13),
                        ),
                      ),
                      Text(
                        '₹${NumberFormat('#,##0').format(_selectedValue ?? 0)}',
                        style: _label(
                            color: _T.accent,
                            weight: FontWeight.w700,
                            size: 13),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () => setState(() {
                          _selectedIndex = null;
                          _selectedValue = null;
                        }),
                        child: const Icon(Icons.close_rounded,
                            size: 16, color: _T.inkFaint),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),

        // ── Chart ─────────────────────────────────
        SizedBox(
          height: 220,
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: SizedBox(
              width: chartWidth,
              child: BarChart(
                BarChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: stepSize,
                    getDrawingHorizontalLine: (_) => const FlLine(
                        color: Color(0xFFEEEEEF), strokeWidth: 1),
                  ),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 42,
                        getTitlesWidget: (value, _) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= labels.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              labels[idx],
                              textAlign: TextAlign.center,
                              style: GoogleFonts.dmSans(
                                  fontSize: 9, color: _T.inkFaint),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: const Border(
                      bottom: BorderSide(color: Color(0xFFEEEEEF), width: 1),
                    ),
                  ),
                  minY: 0,
                  maxY: maxY,
                  barGroups: List.generate(breakdown.length, (i) {
                    final val = (breakdown[i]['total'] as num).toDouble();
                    final isSelected = _selectedIndex == i;
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: val > 0 ? val : stepSize * 0.02,
                          width: 30,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(6),
                            topRight: Radius.circular(6),
                          ),
                          gradient: LinearGradient(
                            colors: isSelected
                                ? [_T.accent, _T.accent.withOpacity(0.5)]
                                : [
                                    const Color(0xFF0A84FF).withOpacity(0.85),
                                    const Color(0xFF5AC8FA).withOpacity(0.4),
                                  ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ],
                    );
                  }),
                  barTouchData: BarTouchData(
                    enabled: true,
                    // Disable built-in fl_chart tooltip — we draw our own
                    touchTooltipData: BarTouchTooltipData(
                        getTooltipItem: (_, __, ___, ____) => null),
                    handleBuiltInTouches: true,
                    touchCallback: (FlTouchEvent event, BarTouchResponse? response) {
                      // Only act on a definitive tap/pointer-up, not drag events
                      if (event is! FlTapUpEvent && event is! FlPanEndEvent) {
                        return;
                      }
                      if (response == null || response.spot == null) {
                        // Tapped empty area — deselect
                        if (_selectedIndex != null) {
                          setState(() {
                            _selectedIndex = null;
                            _selectedValue = null;
                          });
                        }
                        return;
                      }
                      final idx = response.spot!.touchedBarGroupIndex;
                      final val = (breakdown[idx]['total'] as num).toDouble();
                      setState(() {
                        if (_selectedIndex == idx) {
                          // Same bar tapped again — toggle off
                          _selectedIndex = null;
                          _selectedValue = null;
                        } else {
                          _selectedIndex = idx;
                          _selectedValue = val;
                        }
                      });
                    },
                  ),
                ),
              ),
            ),
          ),
        ),

        // Swipe hint
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.swipe_rounded, size: 12, color: _T.inkFaint),
            const SizedBox(width: 4),
            Text('Scroll to explore',
                style: _label(size: 10, color: _T.inkFaint)),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// PIE CHART (Order Distribution)
// ─────────────────────────────────────────────

class PieChartSample2 extends StatefulWidget {
  const PieChartSample2({super.key});

  @override
  State<PieChartSample2> createState() => _PieChart2State();
}

class _PieChart2State extends State<PieChartSample2> {
  int touchedIndex = -1;
  List<Map<String, dynamic>> topItems = [];
  bool isLoading = true;

  final List<Color> sectionColors = [
    const Color(0xFF0A84FF),
    const Color(0xFF30D158),
    const Color(0xFF5E5CE6),
    const Color(0xFFFF9F0A),
    const Color(0xFFFF375F),
    const Color(0xFF64D2FF),
    const Color(0xFFFFD60A),
    const Color(0xFFBF5AF2),
    const Color(0xFF32D74B),
    const Color(0xFFFF6961),
  ];

  @override
  void initState() {
    super.initState();
    _fetchItems();
  }

  Future<void> _fetchItems() async {
    try {
      final response = await http.get(
          Uri.parse('${dotenv.env['API_URL']}/admin/topSelling-today'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['items'];
        if (items is List) {
          setState(() {
            topItems = List<Map<String, dynamic>>.from(items);
            isLoading = false;
          });
          return;
        }
      }
    } catch (_) {}
    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (topItems.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
            child: Text('No data available', style: _label())),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                pieTouchData: PieTouchData(
                  touchCallback: (event, resp) {
                    setState(() {
                      touchedIndex =
                          (!event.isInterestedForInteractions ||
                                  resp?.touchedSection == null)
                              ? -1
                              : resp!.touchedSection!.touchedSectionIndex;
                    });
                  },
                ),
                borderData: FlBorderData(show: false),
                sectionsSpace: 3,
                centerSpaceRadius: 48,
                sections: List.generate(topItems.length, (i) {
                  final item = topItems[i];
                  final isTouched = i == touchedIndex;
                  final pct = double.tryParse(
                          item['percentage'].replaceAll('%', '')) ??
                      0;
                  return PieChartSectionData(
                    color: sectionColors[i % sectionColors.length],
                    value: pct,
                    title: isTouched ? item['percentage'] : '',
                    radius: isTouched ? 58 : 46,
                    titleStyle: _mono(
                        size: 12,
                        color: Colors.white,
                        weight: FontWeight.w700),
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Legend
          Wrap(
            alignment: WrapAlignment.start,
            spacing: 12,
            runSpacing: 10,
            children: List.generate(topItems.length, (i) {
              final item = topItems[i];
              final color = sectionColors[i % sectionColors.length];
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${item['name']} (${item['percentage']})',
                    style: _label(size: 12),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}