import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class TransferHistoryPage extends StatefulWidget {
  const TransferHistoryPage({super.key});

  @override
  _TransferHistoryPageState createState() => _TransferHistoryPageState();
}

class _TransferHistoryPageState extends State<TransferHistoryPage> {
  late Future<List<TransferRecord>> _transferHistory;

  @override
  void initState() {
    super.initState();
    _transferHistory = fetchTransferHistory();
  }

  Future<List<TransferRecord>> fetchTransferHistory() async {
    final response = await http.get(Uri.parse('${dotenv.env['API_URL']}/kitchen-inventory/transfer-history'));

    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(response.body);
      return data.map((json) => TransferRecord.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load transfer history');
    }
  }

  String formatDate(String date) {
    final parsed = DateTime.tryParse(date);
    if (parsed == null) return date;
    return DateFormat.MMMd().format(parsed); // e.g., May 8
  }

  Widget _autoSizedText(String text) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: GoogleFonts.poppins(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Transfer History',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: FutureBuilder<List<TransferRecord>>(
        future: _transferHistory,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                'No transfer history available.',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          final history = snapshot.data!;

          return LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 600;

              if (isWide) {
                // Web/Tablet View
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Scrollbar(
                        thickness: 6,
                        radius: const Radius.circular(4),
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minWidth: 800),
                              child: DataTable(
                                headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                                headingTextStyle: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: Colors.black87,
                                ),
                                dataTextStyle: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w400,
                                  fontSize: 13,
                                  color: Colors.black87,
                                ),
                                columnSpacing: 24,
                                horizontalMargin: 24,
                                dividerThickness: 0.4,
                                border: TableBorder(
                                  horizontalInside: BorderSide(color: Colors.grey.shade200),
                                ),
                                columns: [
                                  DataColumn(label: _autoSizedText('Date')),
                                  DataColumn(label: _autoSizedText('Item')),
                                  DataColumn(label: _autoSizedText('Qty')),
                                  DataColumn(label: _autoSizedText('User')),
                                ],
                                rows: history.map((record) {
                                  return DataRow(
                                    cells: [
                                      DataCell(_autoSizedText(formatDate(record.date))),
                                      DataCell(_autoSizedText(record.itemName)),
                                      DataCell(_autoSizedText('${record.quantity} ${record.unit}')),
                                      DataCell(_autoSizedText(record.username.isEmpty ? 'Unknown' : record.username)),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              } else {
                // Mobile View
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    final record = history[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
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
                                record.itemName,
                                style: GoogleFonts.poppins(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                              Text(
                                formatDate(record.date),
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Qty: ${record.quantity} ${record.unit}',
                            style: GoogleFonts.poppins(fontSize: 14, color: Colors.black54),
                          ),
                          Text(
                            'User: ${record.username.isEmpty ? 'Unknown' : record.username}',
                            style: GoogleFonts.poppins(fontSize: 14, color: Colors.black54),
                          ),
                        ],
                      ),
                    );
                  },
                );
              }
            },
          );
        },
      ),
    );
  }
}

class TransferRecord {
  final String itemName;
  final int quantity;
  final String unit;
  final String username;
  final String date;

  TransferRecord({
    required this.itemName,
    required this.quantity,
    required this.unit,
    required this.username,
    required this.date,
  });

  factory TransferRecord.fromJson(Map<String, dynamic> json) {
    return TransferRecord(
      itemName: json['item_name'],
      quantity: json['quantity'],
      unit: json['unit'],
      username: json['username'],
      date: json['date'],
    );
  }
}
