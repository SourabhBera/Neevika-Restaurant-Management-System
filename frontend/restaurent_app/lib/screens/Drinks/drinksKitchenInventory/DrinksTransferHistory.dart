import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class DrinksTransferHistoryPage extends StatefulWidget {
  const DrinksTransferHistoryPage({super.key});

  @override
  _DrinksTransferHistoryPageState createState() => _DrinksTransferHistoryPageState();
}

class _DrinksTransferHistoryPageState extends State<DrinksTransferHistoryPage> {
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
            Text(
              'Transfer History',
              style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            Text(
              'Manage your Transfers',
              style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
        iconTheme: IconThemeData(color: Colors.black),
      ),
      body: FutureBuilder<List<TransferRecord>>(
        future: _transferHistory,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(child: Text('No transfer history available.'));
          }

          final history = snapshot.data!;

          return Align(
  alignment: Alignment.topCenter,
  child: SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          DataTable(
            headingRowColor: WidgetStateProperty.all(Colors.deepPurple.shade100),
            dataRowColor: WidgetStateProperty.all(Colors.white),
            columnSpacing: 24,
            columns: [
              DataColumn(
                label: Text('Date', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
              ),
              DataColumn(
                label: Text('Item', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
              ),
              DataColumn(
                label: Text('Qty', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
              ),
              DataColumn(
                label: Text('User', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
              ),
            ],
            rows: history.map((record) {
              return DataRow(cells: [
                DataCell(Text(formatDate(record.date), style: GoogleFonts.poppins())),
                DataCell(Text(record.itemName, style: GoogleFonts.poppins())),
                DataCell(Text('${record.quantity} ${record.unit}', style: GoogleFonts.poppins())),
                DataCell(Text(record.username.isEmpty ? 'Unknown' : record.username, style: GoogleFonts.poppins())),
              ]);
            }).toList(),
          ),
        ],
      ),
    ),
  ),
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
