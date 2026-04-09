import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class RunningOrdersPage extends StatefulWidget {
  const RunningOrdersPage({super.key});

  @override
  State<RunningOrdersPage> createState() => _RunningOrdersPageState();
}

class _RunningOrdersPageState extends State<RunningOrdersPage> {
  List<dynamic> orders = [];
  bool isLoading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    fetchOrders();
  }

  Future<void> fetchOrders() async {
    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      final response =
          await http.get(Uri.parse('${dotenv.env['API_URL']}/orders/all-running'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final filtered = (data as List).where((order) {
          final status = order['status']?.toString().toLowerCase();
          return status == 'pending' || status == 'accepted';
        }).toList();

        setState(() {
          orders = filtered;
          isLoading = false;
        });
      } else {
        setState(() {
          error = 'Failed to load orders. Status: ${response.statusCode}';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        error = 'Error fetching orders: $e';
        isLoading = false;
      });
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange.shade700;
      case 'accepted':
        return Colors.green.shade600;
      default:
        return Colors.grey;
    }
  }

  Widget _buildStatusChip(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _getStatusColor(status),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.toUpperCase(),
        style: GoogleFonts.poppins(color: Colors.white, fontSize: 10),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F5F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F5F2),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 4),
            Text(
              'Running Orders',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 4),
          ],
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(
                  child: Text(error!,
                      style: GoogleFonts.poppins(color: Colors.red, fontSize: 14)))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    DataTable(
                      showCheckboxColumn: false,
                      headingRowColor:
                          WidgetStateProperty.all(Colors.deepPurple.shade50),
                      columnSpacing: 16,
                      dataRowHeight: 60,
                      headingTextStyle: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 10),
                      columns: [
                        DataColumn(label: Text('#', style: GoogleFonts.poppins(fontSize: 10))),
                        DataColumn(label: Text('Table', style: GoogleFonts.poppins(fontSize: 10))),
                        DataColumn(label: Text('Item', style: GoogleFonts.poppins(fontSize: 10))),
                        DataColumn(label: Text('Status', style: GoogleFonts.poppins(fontSize: 10))),
                        DataColumn(label: Text('Amount', style: GoogleFonts.poppins(fontSize: 10))),
                        DataColumn(label: Text('Time', style: GoogleFonts.poppins(fontSize: 10))),
                      ],
                      rows: orders.map((order) {
                        return DataRow(
                          cells: [
                            DataCell(Text(order['kotNumber'].toString(),
                                style: GoogleFonts.poppins(fontSize: 10))),
                            DataCell(Text(
                                "${order['section']?['name'] ?? 'N/A'}-T ${order['restaurent_table_number']?.toString() ?? 'N/A'}",
                                style: GoogleFonts.poppins(fontSize: 10))),
                            DataCell(Text(order['menu']?['name'] ?? order['item_desc'] ?? 'Item',
                                style: GoogleFonts.poppins(fontSize: 10))),
                            DataCell(_buildStatusChip(order['status'] ?? '')),
                            DataCell(Text(
                                '₹${order['amount'] ?? order['menu']?['price'] ?? 0}',
                                style: GoogleFonts.poppins(fontSize: 10))),
                            DataCell(
                              Text(
                                order['createdAt'] != null
                                    ? DateFormat('hh:mm a').format(DateTime.parse(order['createdAt']))
                                    : 'N/A',
                                style: GoogleFonts.poppins(fontSize: 10),
                              ),
                            ),
                          ],
                          onSelectChanged: (_) => _showOrderDetails(order),
                        );
                      }).toList(),
                    ),
                  ],
                ),
    );
  }

  void _showOrderDetails(dynamic order) {
  showDialog(
    context: context,
    builder: (_) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.receipt_long, color: Colors.deepPurple),
                  const SizedBox(width: 8),
                  Text(
                    'Order #${order['id']}',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _infoRow('Item', order['menu']?['name'] ?? order['item_desc']),
              _infoRow('Amount', '₹${order['amount']}'),
              _infoRow('Status', order['status']),
              _infoRow('Table', order['restaurent_table_number']?.toString()),
              _infoRow('Section', order['section']?['name']),
              _infoRow('Server', order['user']?['name']),
              _infoRow('Order Type', order['orderType']),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 18, color: Colors.deepPurple),
                  label: Text('Close', style: GoogleFonts.poppins(color: Colors.deepPurple)),
                ),
              )
            ],
          ),
        ),
      );
    },
  );
}

Widget _infoRow(String label, String? value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            '$label:',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w500, fontSize: 13),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value ?? 'N/A',
            style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade800),
          ),
        ),
      ],
    ),
  );
}
}