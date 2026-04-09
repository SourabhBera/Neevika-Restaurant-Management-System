import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/intl.dart';

class CanceledDrinksOrdersScreen extends StatefulWidget {
  @override
  _CanceledOrdersScreenState createState() => _CanceledOrdersScreenState();
}

class OrderTimer extends StatefulWidget {
  final String createdAt;

  const OrderTimer({super.key, required this.createdAt});

  @override
  State<OrderTimer> createState() => _OrderTimerState();
}

class _OrderTimerState extends State<OrderTimer> {
  late DateTime createdAtTime;
  late Duration elapsed;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    createdAtTime = DateTime.parse(widget.createdAt);
    elapsed = DateTime.now().difference(createdAtTime);

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        elapsed = DateTime.now().difference(createdAtTime);
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return "$hours:$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _formatDuration(elapsed),
      style: GoogleFonts.poppins(
        color: Colors.white,
        fontWeight: FontWeight.w500,
        fontSize: 13,
      ),
    );
  }
}

class _CanceledOrdersScreenState extends State<CanceledDrinksOrdersScreen> {
  List<Map<String, dynamic>> canceledOrders = [];
  bool isLoading = true;

  // Fetch canceled orders from the API
  Future<void> _fetchCanceledOrders() async {
    try {
      final response = await http.get(
        Uri.parse('${dotenv.env['API_URL']}/canceledDrinkOrders'),
      );
      debugPrint("Drinks data: $response");
      if (response.statusCode == 200) {
        // Decode the response body into a map
        final Map<String, dynamic> decodedData = json.decode(response.body);

        // Extract the 'data' field, which contains the list of canceled orders
        final List<dynamic> data = decodedData['data'];

        setState(() {
          // Convert the list into a list of maps
          canceledOrders = List<Map<String, dynamic>>.from(data);
          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load canceled orders.')),
        );
      }
    } catch (e) {
      print('Error: $e');
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error fetching data: $e')));
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchCanceledOrders();
  }

  // Status color helper
  Color _getStatusColor(String status) {
    switch (status) {
      case 'Cancelled':
        return Colors.red[700]!;
      case 'Pending':
        return Colors.orange[700]!;
      default:
        return Colors.green[700]!;
    }
  }

  Widget _buildOrderCard(Map<String, dynamic> order, int index) {
    final statusColor = _getStatusColor(
      order["status"] ?? "",
    ); // Consider removing status if it's not part of the API
    final menu = order['menu'] ?? {};
    final user = order['user'] ?? {};

    // Extract relevant fields
    final tableNumber = order['restaurent_table_number'] ?? 'Unknown';
    final section_number = order['section_number'] ?? 'Unknown';
    final userName = user['name'] ?? 'Unknown User';
    final itemName =
        menu['name'] ?? 'No Drink'; // Assuming you want to show the drink name
    final price = menu['price'] ?? '0';
    final quantity = order['count']?.toString() ?? '1'; // If count exists
    final createdAtRaw = order['createdAt'];
    String formattedDate = 'Unknown time';

    if (createdAtRaw != null) {
      final parsedDate = DateTime.parse(createdAtRaw);
      formattedDate = DateFormat('dd/MM/yy hh:mma').format(parsedDate);
    }

    return InkWell(
      onTap: () {
        // You can handle tapping the order card here
      },
      borderRadius: BorderRadius.circular(12),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 15, horizontal: 8),
        color: const Color.fromARGB(255, 245, 243, 240),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top: Order ID, Table Number, User, Price
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      "${index + 1} • $section_number / Table $tableNumber", // numbering starts from 1
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  Text(
                    "₹ $price",
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Colors.red[700],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Server & Time (user and createdAt)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(userName, style: GoogleFonts.poppins(fontSize: 12)),
                  Text(
                    formattedDate,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Drink Name & Quantity
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.fastfood, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$itemName',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'x$quantity',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child:
                      (order["status"] == null || order["status"] == "Unknown")
                          ? OrderTimer(createdAt: order["createdAt"])
                          : Text(
                            order["status"],
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Canceled Drink Orders'),
        backgroundColor: Colors.red[700],
      ),
      body:
          isLoading
              ? Center(child: CircularProgressIndicator())
              : canceledOrders.isEmpty
              ? Center(child: Text('No canceled orders found'))
              : ListView.builder(
                itemCount: canceledOrders.length,
                itemBuilder: (context, index) {
                  return _buildOrderCard(canceledOrders[index], index);
                },
              ),
    );
  }
}
