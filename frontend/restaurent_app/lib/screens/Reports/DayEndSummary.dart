import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

class DayEndSummaryScreen extends StatefulWidget {
  const DayEndSummaryScreen({super.key});

  @override
  _DayEndSummaryScreenState createState() => _DayEndSummaryScreenState();
}

class _DayEndSummaryScreenState extends State<DayEndSummaryScreen> {
  List<Map<String, dynamic>> daySummaryData = [];
  late Future<void> _daySummaryFuture;
  TextEditingController searchController = TextEditingController();
  DateTime? startDate;
  DateTime? endDate;

  @override
  void initState() {
    super.initState();
    _daySummaryFuture = fetchDaySummaryData();
  }

  String formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('d MMM yyyy').format(date);
    } catch (_) {
      return dateString;
    }
  }

  String formatDateTime(dynamic dateValue) {
    if (dateValue == null) return "-";
    try {
      final date = DateTime.parse(dateValue.toString());
      return DateFormat('d MMM yyyy, hh:mm a').format(date);
    } catch (_) {
      return dateValue.toString();
    }
  }

  double parseDouble(dynamic value) {
    if (value == null) return 0.0;
    return double.tryParse(value.toString()) ?? 0.0;
  }

  List<Map<String, dynamic>> get filteredData {
    return daySummaryData.where((entry) {
      final matchesSearch =
          searchController.text.isEmpty ||
          formatDate(
            entry['date'],
          ).toLowerCase().contains(searchController.text.toLowerCase());

      final entryDate = DateTime.tryParse(entry['date']);
      final matchesStart =
          startDate == null ||
          (entryDate != null &&
              entryDate.isAfter(startDate!.subtract(const Duration(days: 1))));
      final matchesEnd =
          endDate == null ||
          (entryDate != null &&
              entryDate.isBefore(endDate!.add(const Duration(days: 1))));

      return matchesSearch && matchesStart && matchesEnd;
    }).toList();
  }

  Future<void> selectDate(BuildContext context, bool isStartDate) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isStartDate) {
          startDate = picked;
        } else {
          endDate = picked;
        }
      });
    }
  }

  Future<void> fetchDaySummaryData() async {
    final response = await http.get(
      Uri.parse('${dotenv.env['API_URL']}/admin/day-end-summary'),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load day summary data');
    }

    final decoded = json.decode(response.body);
    if (decoded is! Map || !decoded.containsKey('data')) {
      throw Exception('Invalid response structure');
    }

    final summaries = decoded['data'] as List<dynamic>;

    List<Map<String, dynamic>> parsed =
        summaries.map((summary) {
          return {
            'id': summary['id'],
            'date': summary['date'] ?? '',
            'orders': summary['orderCount'] ?? 0,
            'subTotal': parseDouble(summary['subTotal']),
            'discount': parseDouble(summary['discount']),
            'serviceCharges': parseDouble(summary['serviceCharges']),
            'tax': parseDouble(summary['tax']),
            'roundOff': parseDouble(summary['roundOff']),
            'grandTotal': parseDouble(summary['grandTotal']),
            'netSales': parseDouble(summary['netSales']),
            'cash': parseDouble(summary['cash']),
            'card': parseDouble(summary['card']),
            'upi': parseDouble(summary['upi']),
            'complimentary': summary['complimentary'] ?? 0,
            'totalBills': summary['totalBills'] ?? 0,
            'invoiceNo': summary['invoiceNo'] ?? "-",
            'updatedAt': summary['updatedAt'] ?? "",
            'grandTotalPercentType':
                summary['grandTotalPercentType'] ?? 'neutral',
            'grandTotalPercent': summary['grandTotalPercent'] ?? 0,
          };
        }).toList();

    for (int i = 0; i < parsed.length; i++) {
      parsed[i]['previousDayTotal'] =
          i < parsed.length - 1 ? parsed[i + 1]['grandTotal'] : 0.0;
    }

    setState(() {
      daySummaryData = parsed;
    });
  }

  Future<void> downloadSummary(
    BuildContext context,
    Map<String, dynamic> summary,
  ) async {
    final url = Uri.parse(
      '${dotenv.env['API_URL']}/admin/download-summary/${summary['date']}',
    );

    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      bool hasPermission = true;

      // Request appropriate permissions based on Android version
      if (sdkInt >= 33) {
        // Android 13+: Request MANAGE_EXTERNAL_STORAGE for Downloads folder access
        final status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          final result = await Permission.manageExternalStorage.request();
          hasPermission = result.isGranted;
        }
      } else if (sdkInt <= 32) {
        // Android 12 and below: Use standard storage permission
        final status = await Permission.storage.status;
        if (!status.isGranted) {
          final result = await Permission.storage.request();
          hasPermission = result.isGranted;
        }
      }

      if (!hasPermission) {
        throw Exception('Storage permission not granted');
      }

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;

        // Get the main Downloads folder (not app-specific storage)
        final dir = await getDownloadsDirectory();
        if (dir == null) {
          throw Exception('Downloads directory not available');
        }

        final fileName = 'DayEndSummary_${summary['date']}.xlsx';
        final filePath = '${dir.path}/$fileName';

        final file = File(filePath);
        await file.writeAsBytes(bytes);

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Downloaded to: $filePath")));

        OpenFile.open(filePath);
      } else {
        throw Exception('Download failed. Status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint("Download error: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Download failed: $e")));
    }
  }

  void showDaySummaryPopup(BuildContext context, Map<String, dynamic> summary) {
    final isPositive = summary['grandTotalPercentType'] == 'positive';
    final percent = summary['grandTotalPercent'];

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          insetPadding: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Summary for ${formatDate(summary['date'])}',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                        color: isPositive ? Colors.green : Colors.red,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        "$percent% ${isPositive ? 'higher' : 'lower'} than yesterday",
                        style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          color: isPositive ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Table(
                    border: TableBorder.all(color: Colors.grey.shade300),
                    columnWidths: const {
                      0: FlexColumnWidth(2),
                      1: FlexColumnWidth(2),
                    },
                    children: [
                      buildRow('Date', formatDate(summary['date'])),
                      buildRow(
                        'Last synced on',
                        formatDateTime(summary['updatedAt']),
                      ),
                      buildRow('Invoice No.', summary['invoiceNo'].toString()),
                      buildRow('Orders Count', '${summary['orders']}'),
                      buildRow('Complimentary', '${summary['complimentary']}'),
                      buildRow('Total Bills', '${summary['totalBills']}'),
                      buildRow(
                        'Sub Total',
                        '₹${summary['subTotal'].toStringAsFixed(2)}',
                      ),
                      buildRow(
                        'Discount',
                        '₹${summary['discount'].toStringAsFixed(2)}',
                      ),
                      buildRow(
                        'Service Charges',
                        '₹${summary['serviceCharges'].toStringAsFixed(2)}',
                      ),
                      buildRow('Tax', '₹${summary['tax'].toStringAsFixed(2)}'),
                      buildRow(
                        'Round-off',
                        '₹${summary['roundOff'].toStringAsFixed(2)}',
                      ),
                      buildRow(
                        'Grand Total',
                        '₹${summary['grandTotal'].toStringAsFixed(2)}',
                      ),
                      buildRow(
                        'Net Sales',
                        '₹${summary['netSales'].toStringAsFixed(2)}',
                      ),
                      buildRow(
                        'Cash',
                        '₹${summary['cash'].toStringAsFixed(2)}',
                      ),
                      buildRow(
                        'Card',
                        '₹${summary['card'].toStringAsFixed(2)}',
                      ),
                      buildRow('UPI', '₹${summary['upi'].toStringAsFixed(2)}'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: MediaQuery.of(context).size.width * 0.82,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF89F3F),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        "Close",
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  TableRow buildRow(String label, String value) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8, left: 20),
          child: Text(
            label,
            style: GoogleFonts.poppins(fontSize: 13, color: Colors.black87),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8, right: 20),
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F5F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F5F2),
        elevation: 0,
        title: Text(
          'Day End Summary',
          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => selectDate(context, true),
                    icon: const Icon(
                      Icons.calendar_today_outlined,
                      size: 16,
                      color: Colors.black54,
                    ),
                    label: Text(
                      startDate != null
                          ? DateFormat('d MMM yyyy').format(startDate!)
                          : 'Start Date',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: Colors.black87,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      backgroundColor: Colors.grey.shade200,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => selectDate(context, false),
                    icon: const Icon(
                      Icons.calendar_today_outlined,
                      size: 16,
                      color: Colors.black54,
                    ),
                    label: Text(
                      endDate != null
                          ? DateFormat('d MMM yyyy').format(endDate!)
                          : 'End Date',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: Colors.black87,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      backgroundColor: Colors.grey.shade200,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search by date...',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: Colors.grey.shade200,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              style: GoogleFonts.poppins(fontSize: 13),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<void>(
                future: _daySummaryFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: LoadingAnimationWidget.staggeredDotsWave(
                        color: Colors.deepPurple,
                        size: 50,
                      ),
                    );
                  } else if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  } else if (filteredData.isEmpty) {
                    return const Center(child: Text('No data available.'));
                  }

                  return SingleChildScrollView(
                    child: Center(
                      child: SizedBox(
                        width: MediaQuery.of(context).size.width * 0.90,
                        child: DataTable(
                          columnSpacing: 24,
                          headingRowColor: WidgetStateProperty.all(
                            Colors.deepPurple.shade100,
                          ),
                          columns: [
                            DataColumn(
                              label: Padding(
                                padding: const EdgeInsets.only(left: 12.0),
                                child: Text(
                                  'Date',
                                  style: GoogleFonts.poppins(fontSize: 11),
                                ),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Orders',
                                style: GoogleFonts.poppins(fontSize: 11),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Total',
                                style: GoogleFonts.poppins(fontSize: 11),
                              ),
                            ),
                            DataColumn(
                              label: Padding(
                                padding: const EdgeInsets.only(left: 24.0),
                                child: Text(
                                  'Actions',
                                  style: GoogleFonts.poppins(fontSize: 11),
                                ),
                              ),
                            ),
                          ],
                          rows:
                              filteredData.map((entry) {
                                return DataRow(
                                  cells: [
                                    DataCell(
                                      Text(
                                        formatDate(entry['date']),
                                        style: GoogleFonts.poppins(
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          left: 10.0,
                                        ),
                                        child: Text(
                                          entry['orders'].toString(),
                                          style: GoogleFonts.poppins(
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        '₹${entry['grandTotal'].toStringAsFixed(2)}',
                                        style: GoogleFonts.poppins(
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(
                                              LucideIcons.clipboardList,
                                              size: 18,
                                            ),
                                            tooltip: 'View Details',
                                            onPressed:
                                                () => showDaySummaryPopup(
                                                  context,
                                                  entry,
                                                ),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              LucideIcons.download,
                                              size: 18,
                                            ),
                                            tooltip: 'Download',
                                            onPressed:
                                                () => downloadSummary(
                                                  context,
                                                  entry,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
