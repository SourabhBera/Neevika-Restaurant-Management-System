import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class MyOrdersScreen extends StatefulWidget {
  final String userId;
  const MyOrdersScreen({super.key, required this.userId});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  List<Map<String, dynamic>> allOrders = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchOrders();
  }

  Future<void> fetchOrders() async {
    final response = await http.get(Uri.parse('${dotenv.env['API_URL']}/auth/user_orders/${widget.userId}')); // Replace with real URL

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      // Step 1: normalize orders into a flat list with needed fields
      List<Map<String, dynamic>> flatOrders = [];

      for (var order in data['orders']) {
        // find kot number robustly (different APIs use different keys)
        final kotNumber = order['kotNumber'] ??
            order['kot_number'] ??
            order['kotNo'] ??
            order['kot'] ??
            order['kotno'] ??
            order['kot_no'] ??
            order['id']; // fallback to id if no kot provided

        // table number robust fallback
        final tableNum = order['restaurant_table_number'] ??
            order['restaurent_table_number'] ??
            order['table_number'] ??
            order['tableNo'] ??
            '';

        final sectionName = order['section'] != null && order['section']['name'] != null
            ? order['section']['name']
            : (order['section'] ?? '');

        final amountVal = (order['amount'] is int)
            ? (order['amount'] as int).toDouble()
            : (order['amount'] is double ? order['amount'] : 0.0);

        final itemName = order['drink'] != null
            ? order['drink']['name']
            : (order['menu'] != null ? order['menu']['name'] : (order['item_desc'] ?? 'Item'));

        final quantityVal = (order['quantity'] is int)
            ? order['quantity'] as int
            : int.tryParse(order['quantity']?.toString() ?? '1') ?? 1;

        flatOrders.add({
          'kotNumber': kotNumber.toString(),
          'id': order['id'],
          'type': order['drink'] != null ? 'drink' : 'food',
          'name': itemName,
          'quantity': quantityVal,
          'createdAt': order['createdAt'],
          'status': order['status'] ?? '',
          'table': tableNum.toString(),
          'amount': amountVal,
          'section': sectionName,
        });
      }

      // Step 2: group by kotNumber and aggregate items/amounts
      final Map<String, Map<String, dynamic>> grouped = {};

      for (var o in flatOrders) {
        final kot = o['kotNumber'] as String;
        if (!grouped.containsKey(kot)) {
          grouped[kot] = {
            'kotNumber': kot,
            'ids': <dynamic>[], // list of underlying order ids
            'items': <String, int>{},
            'createdAt': o['createdAt'],
            'status': o['status'],
            'table': o['table'],
            'section': o['section'],
            'amount': 0.0,
          };
        }

        // add id
        grouped[kot]!['ids'].add(o['id']);

        // aggregate item quantities
        final itemsMap = grouped[kot]!['items'] as Map<String, int>;
        final itemName = o['name'] as String;
        final qty = o['quantity'] as int;
        itemsMap[itemName] = (itemsMap[itemName] ?? 0) + qty;

        // sum amount
        grouped[kot]!['amount'] = (grouped[kot]!['amount'] as double) + (o['amount'] as double);

        // choose the earliest createdAt for display
        try {
          final currentCreated = DateTime.parse(grouped[kot]!['createdAt']);
          final candidate = DateTime.parse(o['createdAt']);
          if (candidate.isBefore(currentCreated)) {
            grouped[kot]!['createdAt'] = o['createdAt'];
          }
        } catch (_) {
          // ignore parse errors; keep existing createdAt if any
        }

        // prefer non-empty status (basic logic: if any item is 'pending' we can show that; simple override)
        final existingStatus = (grouped[kot]!['status'] ?? '').toString().toLowerCase();
        final newStatus = (o['status'] ?? '').toString().toLowerCase();
        if (existingStatus.isEmpty && newStatus.isNotEmpty) {
          grouped[kot]!['status'] = o['status'];
        } else if (existingStatus != newStatus && newStatus.isNotEmpty) {
          // simple rule: if any item is 'pending' -> show 'pending', else keep existing
          if (newStatus == 'pending') grouped[kot]!['status'] = o['status'];
        }
      }

      // Step 3: convert grouped map to list (preserve some ordering — by createdAt desc)
      List<Map<String, dynamic>> groupedList = grouped.values.toList();

      groupedList.sort((a, b) {
        try {
          final da = DateTime.parse(a['createdAt']);
          final db = DateTime.parse(b['createdAt']);
          return db.compareTo(da); // newest first
        } catch (_) {
          return 0;
        }
      });

      setState(() {
        allOrders = groupedList;
        isLoading = false;
      });
    } else {
      setState(() => isLoading = false);
    }
  }

  String _timeAgo(String dateStr) {
    try {
      final date = DateTime.parse(dateStr).toLocal();
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inMinutes < 1) return "Just now";
      if (diff.inMinutes < 60) return "${diff.inMinutes} mins ago";
      if (diff.inHours < 24) return "${diff.inHours} hours ago";
      return DateFormat('MMM dd, yyyy').format(date);
    } catch (_) {
      return dateStr;
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return const Color(0xFF2ECC71);
      case 'pending':
        return const Color(0xFF4D7CFE);
      case 'accepted':
        return const Color(0xFFF39C12);
      default:
        return Colors.grey;
    }
  }

  IconData _statusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Icons.check_circle_outline;
      case 'in progress':
        return Icons.access_time_rounded;
      case 'delayed':
        return Icons.warning_amber_rounded;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F5F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F5F2),
        elevation: 0,
        leading: BackButton(color: Colors.black87),
        title: Text(
          "My Orders",
          style: GoogleFonts.poppins(
            color: Colors.black87,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : allOrders.isEmpty
              ? Center(
                  child: Text(
                    'No Orders Available',
                    style: GoogleFonts.poppins(fontSize: 16, color: Colors.black54),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: ListView.separated(
                    itemCount: allOrders.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final order = allOrders[index];

                      // order['items'] is Map<String,int>
                      final Map<String, int> items = Map<String, int>.from(order['items'] ?? {});

                      return OrderCard(
                        tableNumber: order['table'] ?? '',
                        orderNumber: 'KOT-${order['kotNumber']}',
                        timeAgo: _timeAgo(order['createdAt'] ?? ''),
                        status: order['status'] ?? '',
                        statusColor: _statusColor((order['status'] ?? '').toString()),
                        statusIcon: _statusIcon((order['status'] ?? '').toString()),
                        items: items,
                        amount: (order['amount'] is double) ? order['amount'] : (order['amount']?.toDouble() ?? 0.0),
                        section: order['section'] ?? '',
                      );
                    },
                  ),
                ),
    );
  }
}

class OrderCard extends StatelessWidget {
  final String tableNumber;
  final String orderNumber;
  final String timeAgo;
  final String status;
  final Color statusColor;
  final IconData statusIcon;
  final Map<String, int> items;
  final double amount; // Ensuring that the amount is a double
  final String section; // Added section field

  const OrderCard({
    super.key,
    required this.tableNumber,
    required this.orderNumber,
    required this.timeAgo,
    required this.status,
    required this.statusColor,
    required this.statusIcon,
    required this.items,
    required this.amount,
    required this.section,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFEAEAEA)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: Table & status
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$section - Table $tableNumber',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(statusIcon, size: 14, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      status,
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$timeAgo • Order #$orderNumber',
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 10),
          ...items.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    entry.key,
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    'x${entry.value}',
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          // total amount row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total',
                style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              Text(
                '₹${amount.toStringAsFixed(2)}',
                style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
