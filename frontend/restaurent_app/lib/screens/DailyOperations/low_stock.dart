import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';

class LowStockPage extends StatefulWidget {
  const LowStockPage({super.key});

  @override
  State<LowStockPage> createState() => _LowStockPageState();
}

class _LowStockPageState extends State<LowStockPage> with SingleTickerProviderStateMixin {
  List<dynamic> outOfStockItems = [];
  List<dynamic> lowStockItems = [];
  List<dynamic> drinksOutOfStockItems = [];
  List<dynamic> drinksLowStockItems = [];
  bool isLoading = true;
  late TabController _tabController;

  final Color bgColor = const Color(0xFFF4F5F9);
  final Color cardColor = Colors.white;
  final Color redColor = const Color(0xFFFF4D6D);
  final Color orangeColor = const Color(0xFFFF9F43);
  final Color greenColor = const Color(0xFF26D87C);
  final Color blueColor = const Color(0xFF4361EE);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    fetchStockStatus();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> fetchStockStatus() async {
    try {
      final response = await http.get(Uri.parse('${dotenv.env['API_URL']}/admin/lowStock'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          outOfStockItems = data['outOfStockItems'] ?? [];
          lowStockItems = data['lowStockItems'] ?? [];
          drinksOutOfStockItems = data['drinksOutOfStockItems'] ?? [];
          drinksLowStockItems = data['drinkslowStockItems'] ?? [];
          isLoading = false;
        });
      } else {
        throw Exception("Failed to load stock data");
      }
    } catch (e) {
      debugPrint("Error: $e");
      setState(() => isLoading = false);
    }
  }

  int get totalOutOfStock => outOfStockItems.length + drinksOutOfStockItems.length;
  int get totalLowStock => lowStockItems.length + drinksLowStockItems.length;
  int get totalDrinksOut => drinksOutOfStockItems.length;
  int get totalItems => totalOutOfStock + totalLowStock;

  List<dynamic> get allOutOfStock => [...outOfStockItems, ...drinksOutOfStockItems];
  List<dynamic> get allLowStock => [...lowStockItems, ...drinksLowStockItems];

  List<dynamic> get lowestQuantityItems {
    final all = [
      ...outOfStockItems,
      ...lowStockItems,
      ...drinksOutOfStockItems,
      ...drinksLowStockItems,
    ];
    all.sort((a, b) => (a['quantity'] ?? 0).compareTo(b['quantity'] ?? 0));
    return all.take(6).toList();
  }

  int get maxQuantityInLowest {
    if (lowestQuantityItems.isEmpty) return 1;
    final max = lowestQuantityItems.map((e) => (e['quantity'] ?? 0) as int).reduce((a, b) => a > b ? a : b);
    return max == 0 ? 1 : max;
  }

  Color _itemColor(dynamic item) {
    if (outOfStockItems.contains(item) || drinksOutOfStockItems.contains(item)) return redColor;
    if (lowStockItems.contains(item)) return orangeColor;
    return orangeColor.withOpacity(0.85);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          'Stock Insights',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.black87),
            onPressed: () {},
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionLabel('KEY METRICS'),
                  const SizedBox(height: 10),
                  _buildMetricCard(
                    label: 'Out of Stock',
                    count: totalOutOfStock,
                    color: redColor,
                    trendLabel: '▼ 2%',
                    trendUp: false,
                    fraction: totalItems == 0 ? 0.0 : totalOutOfStock / totalItems,
                  ),
                  const SizedBox(height: 10),
                  _buildMetricCard(
                    label: 'Low Stock',
                    count: totalLowStock,
                    color: orangeColor,
                    trendLabel: '▼ 5%',
                    trendUp: false,
                    fraction: totalItems == 0 ? 0.0 : totalLowStock / totalItems,
                  ),
                  const SizedBox(height: 10),
                  _buildMetricCard(
                    label: 'Drinks Out',
                    count: totalDrinksOut,
                    color: greenColor,
                    trendLabel: '▲ 1%',
                    trendUp: true,
                    fraction: totalItems == 0 ? 0.0 : totalDrinksOut / totalItems,
                  ),
                  const SizedBox(height: 24),

                  // Stock Distribution
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionLabel('STOCK DISTRIBUTION'),
                      TextButton(
                        onPressed: () {},
                        child: Text(
                          'View Categories',
                          style: GoogleFonts.poppins(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: blueColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildDistributionCard(),
                  const SizedBox(height: 24),

                  // Lowest Quantity Items
                  _buildSectionLabel('LOWEST QUANTITY ITEMS'),
                  const SizedBox(height: 10),
                  _buildLowestQuantityCard(),
                  const SizedBox(height: 24),

                  // Item Lists with tabs
                  _buildTabSection(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.poppins(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: Colors.grey[500],
      ),
    );
  }

  Widget _buildMetricCard({
    required String label,
    required int count,
    required Color color,
    required String trendLabel,
    required bool trendUp,
    required double fraction,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
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
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[600],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (trendUp ? greenColor : redColor).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  trendLabel,
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: trendUp ? greenColor : redColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$count',
            style: GoogleFonts.poppins(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: color.withOpacity(0.12),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDistributionCard() {
    final total = totalItems;
    final outFrac = total == 0 ? 0.0 : totalOutOfStock / total;
    final lowFrac = total == 0 ? 0.0 : totalLowStock / total;
    final optFrac = (1 - outFrac - lowFrac).clamp(0.0, 1.0);
    final optimalCount = (optFrac * total).round();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: CustomPaint(
              painter: _DonutChartPainter(
                sections: [
                  _DonutSection(optFrac, blueColor),
                  _DonutSection(lowFrac, orangeColor),
                  _DonutSection(outFrac, redColor),
                ],
                centerText: '$total',
                centerSubText: 'TOTAL SKU',
              ),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLegendItem(blueColor, 'Optimal', '${(optFrac * 100).toStringAsFixed(0)}%'),
                const SizedBox(height: 10),
                _buildLegendItem(orangeColor, 'Low Stock', '${(lowFrac * 100).toStringAsFixed(0)}%'),
                const SizedBox(height: 10),
                _buildLegendItem(redColor, 'Out of Stock', '${(outFrac * 100).toStringAsFixed(0)}%'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label, String value) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.poppins(fontSize: 13, color: Colors.black87),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildLowestQuantityCard() {
    if (lowestQuantityItems.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text('No items', style: GoogleFonts.poppins(color: Colors.grey)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: lowestQuantityItems.map((item) {
          final name = item['itemName'] ?? 'Unnamed';
          final qty = (item['quantity'] ?? 0) as int;
          final unit = item['unit'] ?? '';
          final color = _itemColor(item);
          final frac = (qty / maxQuantityInLowest).clamp(0.0, 1.0);

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text(
                    name,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 5,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: frac,
                      minHeight: 10,
                      backgroundColor: color.withOpacity(0.12),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 64,
                  child: Text(
                    '$qty ${unit.isEmpty ? 'units' : unit}',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTabSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: TabBar(
            controller: _tabController,
            labelColor: blueColor,
            unselectedLabelColor: Colors.grey[500],
            indicatorColor: blueColor,
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorWeight: 2.5,
            labelStyle: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: GoogleFonts.poppins(fontSize: 13),
            tabs: [
              Tab(text: 'Out of Stock (${allOutOfStock.length})'),
              Tab(text: 'Low Stock (${allLowStock.length})'),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 400,
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildItemList(allOutOfStock, redColor),
              _buildItemList(allLowStock, orangeColor),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildItemList(List<dynamic> items, Color color) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 48, color: greenColor),
            const SizedBox(height: 12),
            Text(
              'All good here!',
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      physics: const BouncingScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _buildItemTile(items[index], color),
    );
  }

  Widget _buildItemTile(dynamic item, Color color) {
    final name = item['itemName'] ?? 'Unnamed';
    final qty = (item['quantity'] ?? 0) as int;
    final unit = item['unit'] ?? '';
    final minQty = item['minimum_quantity'] ?? item['minimumQuantity'] ?? '-';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icon container
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F2F8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              children: [
                Center(
                  child: Icon(
                    Icons.inventory_2_outlined,
                    size: 22,
                    color: Colors.grey[500],
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Min Qty: $minQty ${unit.isNotEmpty ? unit : 'units'}',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
          Text(
            qty == 0
                ? '0 Unit'
                : '$qty ${unit.isEmpty ? 'Units' : unit}',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// Custom donut chart painter
class _DonutSection {
  final double fraction;
  final Color color;
  const _DonutSection(this.fraction, this.color);
}

class _DonutChartPainter extends CustomPainter {
  final List<_DonutSection> sections;
  final String centerText;
  final String centerSubText;

  _DonutChartPainter({
    required this.sections,
    required this.centerText,
    required this.centerSubText,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const strokeWidth = 14.0;
    final rect = Rect.fromCircle(center: center, radius: radius - strokeWidth / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    double startAngle = -pi / 2;
    const gapAngle = 0.06;

    for (final section in sections) {
      if (section.fraction <= 0) continue;
      final sweepAngle = section.fraction * 2 * pi - gapAngle;
      paint.color = section.color;
      canvas.drawArc(rect, startAngle, sweepAngle.clamp(0.01, 2 * pi), false, paint);
      startAngle += section.fraction * 2 * pi;
    }

    // Center text
    final textPainter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$centerText\n',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 20,
              color: Colors.black87,
              fontFamily: 'Poppins',
            ),
          ),
          TextSpan(
            text: centerSubText,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 9,
              color: Color(0xFF9E9E9E),
              letterSpacing: 0.5,
              fontFamily: 'Poppins',
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
