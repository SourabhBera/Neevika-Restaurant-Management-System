import 'dart:convert';
import 'dart:io';
import 'package:Neevika/screens/Accounting/Expense/EditExpense_Screen.dart';
import 'package:Neevika/widgets/sidebar.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';



class ExpenseScreen extends StatefulWidget {
  const ExpenseScreen({super.key});

  @override
  State<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends State<ExpenseScreen> {
  List expenses = [];
  DateTime? fromDate;
  DateTime? toDate;

  final String baseUrl = "${dotenv.env['API_URL']}/accounting/expense";

  Future<void> fetchExpenses() async {
    String url = baseUrl;
    if (fromDate != null && toDate != null) {
      String from = fromDate!.toIso8601String().split('T')[0];
      String to = toDate!.toIso8601String().split('T')[0];
      url = "$baseUrl?from=$from&to=$to";
    }

    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        setState(() => expenses = jsonDecode(res.body));
      }
    } catch (e) {
      print("Error fetching expenses: $e");
    }
  }

  Future<void> downloadImage(BuildContext context, String imageUrl) async {
    try {
    // Request permission ONLY for Android 12 and below (SDK <= 32)
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = androidInfo.version.sdkInt;

    bool hasPermission = true;
    if (sdkInt <= 32) {
      final status = await Permission.storage.status;
      if (!status.isGranted) {
        final result = await Permission.storage.request();
        hasPermission = result.isGranted;
      } else {
        hasPermission = true;
      }
    }

    if (!hasPermission) {
      throw Exception('Storage permission not granted');
    }

      final response = await http.get(Uri.parse(imageUrl));

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        
        // ✅ Use app-specific Downloads directory
        final dir = await getExternalStorageDirectory();
        final downloadsDir = Directory("${dir!.path}/downloads");

        if (!downloadsDir.existsSync()) {
          downloadsDir.createSync(recursive: true);
        }

        final filePath = '${downloadsDir.path}/downloaded_image_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final file = File(filePath);
        await file.writeAsBytes(bytes);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Image downloaded to: $filePath")),
        );

        OpenFile.open(filePath);
      } else {
        throw Exception('Failed to download image. Status: ${response.statusCode}');
      }
    } catch (e) {
      print("Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Download failed: $e")),
      );
    }
  }

  Future<void> showExpenseDetails(Map<String, dynamic> expense) async {
    await showDialog(
      context: context,
      builder: (_) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Expense Details",
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1C1917),
                    ),
                  ),
                  const SizedBox(height: 12),

                  _detailRow("Title", expense['type']),
                  _detailRow("Amount", "₹${expense['amount']}"),
                  _detailRow("Date", DateFormat('dd MMM yyyy').format(DateTime.parse(expense['date'] ?? ''))),
                  _detailRow("Description", expense['description'] ?? "-"),
                  _detailRow("Payment Method", expense['payment_method'] ?? "-"),
                  _detailRow("Payment Status", expense['payment_status'] ?? "-"),

                  const SizedBox(height: 20),

                  Container(
                    height: 180,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F0F0),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Stack(
                      children: [
                        expense['receipt_image_path'] != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  "http://13.60.15.89:3000${expense['receipt_image_path']}",
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) => Center(
                                    child: Text(
                                      "Failed to load image",
                                      style: GoogleFonts.poppins(fontSize: 14, color: Colors.redAccent),
                                    ),
                                  ),
                                ),
                              )
                            : Center(
                                child: Text(
                                  "No Receipt Uploaded",
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: const Color(0xFF78726D),
                                  ),
                                ),
                              ),

                        if (expense['receipt_image_path'] != null)
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: GestureDetector(
                              onTap: () {
                                downloadImage(context, "http://13.60.15.89:3000${expense['receipt_image_path']}");
                              },
                              child: CircleAvatar(
                                backgroundColor: const Color(0xFFF89F3F),
                                radius: 16,
                                child: Icon(
                                  Icons.download,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          "Close",
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            color: const Color(0xFF78726D),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF89F3F),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          "Edit",
                          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        onPressed: () async {
                          Navigator.pop(context);
                          final updated = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EditExpensePage(expense: expense),
                            ),
                          );
                          if (updated == true) fetchExpenses();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "$label: ",
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: const Color(0xFF3E3E3E),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w400,
                fontSize: 12,
                color: const Color(0xFF6E6E6E),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    fetchExpenses();
  }

  @override
  Widget build(BuildContext context) {
   return WillPopScope(
    onWillPop: () async => false, // Disable back button
    child: Scaffold(
    backgroundColor: const Color(0xFFF8F5F2),
    drawer: const Sidebar(),
      appBar: AppBar(
        title: Text(
          "Expense Management",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 20,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFFF89F3F),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.pushNamed(context, '/add-expense').then((_) => fetchExpenses()),
        backgroundColor: const Color(0xFFF89F3F),
        child: const Icon(Icons.add, size: 28),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            _buildFilterRow(),
            const SizedBox(height: 14),
            Expanded(
              child: Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 3,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: MaterialStateColor.resolveWith((_) => const Color(0xFFF5F5F5)),
                    columnSpacing: 24,
                    dataRowHeight: 56,
                    columns: [
                      DataColumn(
                          label: Text(
                        "Date",
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 12),
                      )),
                      DataColumn(
                          label: Text(
                        "Title",
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 12),
                      )),
                      DataColumn(
                          label: Text(
                        "Amount",
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 12),
                      )),
                      DataColumn(
                          label: Text(
                        "Status",
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 12),
                      )),
                    ],
                    rows: expenses.map((e) {
                      return DataRow(
                        cells: [
                          DataCell(
                            InkWell(
                              onTap: () => showExpenseDetails(e),
                              child: Text(
                                DateFormat('dd MMM yyyy').format(DateTime.parse(e['date'] ?? '')),
                                style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF4A4A4A)),
                              ),
                            ),
                          ),
                          DataCell(
                            InkWell(
                              onTap: () => showExpenseDetails(e),
                              child: Text(
                                e['type'] ?? '',
                                style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF4A4A4A)),
                              ),
                            ),
                          ),
                          DataCell(
                            InkWell(
                              onTap: () => showExpenseDetails(e),
                              child: Text(
                                "₹${e['amount']}",
                                style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF4A4A4A)),
                              ),
                            ),
                          ),
                          DataCell(
                            InkWell(
                              onTap: () => showExpenseDetails(e),
                              child: Text(
                                e['payment_status'] ?? '-',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: (e['payment_status'] == 'Paid') ? Colors.green : Colors.red,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
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

  Widget _buildFilterRow() {
    return Row(
      children: [
        _buildDateButton("From", fromDate, (date) => setState(() => fromDate = date)),
        const SizedBox(width: 12),
        _buildDateButton("To", toDate, (date) => setState(() => toDate = date)),
        IconButton(
          icon: const Icon(Icons.search, color: Color(0xFFF89F3F)),
          onPressed: fetchExpenses,
          tooltip: 'Filter expenses',
        ),
      ],
    );
  }

  Widget _buildDateButton(String label, DateTime? selectedDate, void Function(DateTime) onPick) {
    return Expanded(
      child: TextButton.icon(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 10),
          backgroundColor: const Color(0xFFF5F5F5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.date_range, color: Color(0xFFF89F3F)),
        label: Text(
          selectedDate != null ? DateFormat('yyyy-MM-dd').format(selectedDate) : label,
          style: GoogleFonts.poppins(color: const Color(0xFF4A4A4A), fontWeight: FontWeight.w500),
        ),
        onPressed: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: selectedDate ?? DateTime.now(),
            firstDate: DateTime(2023),
            lastDate: DateTime(2100),
            builder: (context, child) {
              return Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: const ColorScheme.light(
                    primary: Color(0xFFF89F3F), // header background color
                    onPrimary: Colors.white, // header text color
                    onSurface: Colors.black, // body text color
                  ),
                  textButtonTheme: TextButtonThemeData(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFF89F3F), // button text color
                    ),
                  ),
                ),
                child: child!,
              );
            },
          );
          if (picked != null) onPick(picked);
        },
      ),
    );
  }
}
