import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;

class ProfitLossScreen extends StatefulWidget {
  const ProfitLossScreen({super.key});

  @override
  State<ProfitLossScreen> createState() => _ProfitLossScreenState();
}

class _ProfitLossScreenState extends State<ProfitLossScreen> {
  final bool useDummyData = false;
  List<Map<String, dynamic>> allData = [];
  List<Map<String, dynamic>> filteredData = [];
  String? selectedYear;
  String? selectedMonth;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  void loadData() async {
    if (useDummyData) {
      allData = [
        {
          "date": "2025-01",
          "total_sales": 80000,
          "total_expenses": 12000,
          "purchase_amount": 15000,
          "payroll_amount": 25000,
          "profit": 28000,
          "status": "Profit"
        },
        {
          "date": "2025-02",
          "total_sales": 60000,
          "total_expenses": 20000,
          "purchase_amount": 10000,
          "payroll_amount": 22000,
          "profit": 8000,
          "status": "Profit"
        },
        {
          "date": "2025-03",
          "total_sales": 50000,
          "total_expenses": 22000,
          "purchase_amount": 18000,
          "payroll_amount": 22000,
          "profit": -12000,
          "status": "Loss"
        },
      ];
    } else {
      try {
        final res = await http.get(Uri.parse("${dotenv.env['API_URL']}/profit-loss"));
        if (res.statusCode == 200) {
          final List<dynamic> responseData = jsonDecode(res.body);
          print(responseData);
          allData = responseData.map((e) => e as Map<String, dynamic>).toList();
        }
      } catch (e) {
        print("Error fetching data: $e");
      }
    }
    setState(() {
      filteredData = [...allData];
    });
  }

  List<String> getAvailableYears() {
    return allData.map((e) => e['date'].toString().split('-')[0]).toSet().toList();
  }

  List<String> months = List.generate(12, (index) => (index + 1).toString().padLeft(2, '0'));

  void applyFilters() {
    setState(() {
      filteredData = allData.where((item) {
        final parts = item['date'].toString().split('-');
        final yearMatch = selectedYear == null || parts[0] == selectedYear;
        final monthMatch = selectedMonth == null || parts[1] == selectedMonth;
        return yearMatch && monthMatch;
      }).toList();
    });
  }

  void resetFilters() {
    setState(() {
      selectedYear = null;
      selectedMonth = null;
      filteredData = [...allData];
    });
  }

  String formatMonth(String date) {
    try {
      final parsed = DateFormat('yyyy-MM').parse(date);
      return DateFormat('MMMM yyyy').format(parsed);
    } catch (_) {
      return date;
    }
  }

  Widget buildRow(String label, dynamic value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[700])),
          Text('₹${(value ?? 0).toStringAsFixed(2)}',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: valueColor ?? Colors.black,
              )),
        ],
      ),
    );
  }

  Widget buildCard(Map item) {
    final profit = double.tryParse(item['profit'].toString()) ?? 0;
    final isProfit = item['status'].toString().toLowerCase() == 'profit';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x11000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(formatMonth(item['date']),
              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isProfit ? Colors.green[100] : Colors.red[100],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              item['status'],
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isProfit ? Colors.green[700] : Colors.red[700]),
            ),
          ),
          const SizedBox(height: 12),
          buildRow("Total Sales", item['total_sales']),
          buildRow("Expenses", item['total_expenses']),
          buildRow("Purchases", item['purchase_amount']),
          buildRow("Payroll", item['payroll_amount']),
          const Divider(height: 24),
          buildRow("Net ${item['status']}", profit, valueColor: isProfit ? Colors.green : Colors.red),
        ],
      ),
    );
  }

  Widget buildFilters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: selectedYear,
              decoration: const InputDecoration(labelText: "Year"),
              items: getAvailableYears()
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (val) => setState(() => selectedYear = val),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: selectedMonth,
              decoration: const InputDecoration(labelText: "Month"),
              items: months
                  .map((e) => DropdownMenuItem(
                        value: e,
                        child: Text(DateFormat.MMMM().format(DateTime(0, int.parse(e)))),
                      ))
                  .toList(),
              onChanged: (val) => setState(() => selectedMonth = val),
            ),
          ),
          IconButton(onPressed: applyFilters, icon: const Icon(Icons.search, color: Colors.blueAccent)),
          IconButton(onPressed: resetFilters, icon: const Icon(Icons.refresh, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget buildExportButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ElevatedButton.icon(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Exported as PDF (placeholder)'))),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text("PDF"),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Exported as Excel (placeholder)'))),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            icon: const Icon(Icons.table_chart),
            label: const Text("Excel"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: Text('Profit & Loss', style: GoogleFonts.poppins(color: Colors.black, fontWeight: FontWeight.w600)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Column(
        children: [
          buildFilters(),
          buildExportButtons(),
          Expanded(
            child: filteredData.isEmpty
                ? const Center(child: Text("No records found"))
                : ListView.builder(
                    itemCount: filteredData.length,
                    itemBuilder: (_, index) => buildCard(filteredData[index]),
                  ),
          ),
        ],
      ),
    );
  }
}
