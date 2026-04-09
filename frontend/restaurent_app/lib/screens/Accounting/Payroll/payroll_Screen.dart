import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'editPayroll_Screen.dart';

class PayrollListScreen extends StatefulWidget {
  const PayrollListScreen({Key? key}) : super(key: key);

  @override
  State<PayrollListScreen> createState() => _PayrollListScreenState();
}

class _PayrollListScreenState extends State<PayrollListScreen> {
  String selectedMonth = DateFormat('yyyy-MM').format(DateTime.now());
  TextEditingController searchController = TextEditingController();
  List payrollList = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchPayrolls();
  }

  Future<void> fetchPayrolls() async {
    setState(() => isLoading = true);
    final url = Uri.parse('${dotenv.env['API_URL']}/payroll'); 
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        setState(() {
          payrollList = data;
          isLoading = false;
        });
      } else {
        throw Exception("Failed to load payrolls");
      }
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredList = payrollList.where((item) {
      final name = (item['employee']?['name'] ?? '').toLowerCase();
      final search = searchController.text.toLowerCase();
      final monthMatches = item['month'] == selectedMonth;
      final nameMatches = name.contains(search);
      return monthMatches && nameMatches;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Text(
          "Payroll Table View",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Colors.black87,
            fontSize: 20,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12.withOpacity(0.05),
                          blurRadius: 6,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedMonth,
                        isExpanded: true,
                        items: List.generate(12, (index) {
                          final date = DateTime(DateTime.now().year, index + 1);
                          final formatted = DateFormat('yyyy-MM').format(date);
                          return DropdownMenuItem(
                            value: formatted,
                            child: Text(formatted, style: GoogleFonts.poppins(fontSize: 14)),
                          );
                        }),
                        onChanged: (val) {
                          setState(() {
                            selectedMonth = val!;
                          });
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
  child: Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black12.withOpacity(0.05),
          blurRadius: 6,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: TextField(
      controller: searchController,
      onChanged: (_) => setState(() {}),
      style: GoogleFonts.poppins(fontSize: 13, height: 1.2),
      decoration: InputDecoration(
        hintText: "Search Employee",
        hintStyle: GoogleFonts.poppins(fontSize: 13),
        prefixIcon: const Icon(Icons.search),
        prefixIconConstraints: const BoxConstraints(
          minHeight: 24,
          minWidth: 40,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        border: InputBorder.none,
      ),
    ),
  ),
),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowColor: MaterialStateColor.resolveWith((_) => Colors.grey.shade100),
                          dataRowColor: MaterialStateColor.resolveWith((states) =>
                              states.contains(MaterialState.selected)
                                  ? Colors.blue.withOpacity(0.1)
                                  : Colors.white),
                          columnSpacing: 24,
                          columns: [
                            DataColumn(
                              label: Text("Employee",
                                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                            ),
                            DataColumn(
                              label: Text("Email",
                                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                            ),
                            DataColumn(
                              label: Text("Net Salary",
                                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                            ),
                            DataColumn(
                              label: Text("Status",
                                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                            ),
                            DataColumn(
                              label: Text("Actions",
                                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                            ),
                          ],
                          rows: filteredList.map((item) {
                            final employee = item['employee'] ?? {};
                            final isPaid = item['payment_status'] == 'Paid';
                            return DataRow(cells: [
                              DataCell(Text(employee['name'] ?? 'N/A', style: GoogleFonts.poppins(fontSize: 11))),
                              DataCell(Text(employee['email'] ?? '', style: GoogleFonts.poppins(fontSize: 11))),
                              DataCell(Text("₹${(item['net_salary'] ?? 0).toStringAsFixed(2)}", style: GoogleFonts.poppins(fontSize: 11))),
                              DataCell(Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isPaid ? Colors.green.shade100 : Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  item['payment_status'] ?? '',
                                  style: GoogleFonts.poppins(
                                    color: isPaid ? Colors.green.shade800 : Colors.orange.shade800,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                                ),
                              )),
                              DataCell(
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blue),
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (_) => EditPayrollDialog(
                                        payrollData: item,
                                        onSave: (updatedData) {
                                          // TODO: Implement API update logic
                                          print("Updated data: $updatedData");
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ]);
                          }).toList(),
                        ),
                      ),
                    ),
            )
          ],
        ),
      ),
    );
  }
}
