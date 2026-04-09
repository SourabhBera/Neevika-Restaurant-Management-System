import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import '../../../utils/storage_helper.dart';

class DayWiseReportScreen extends StatefulWidget {
  const DayWiseReportScreen({super.key});

  @override
  State<DayWiseReportScreen> createState() => _DayWiseReportScreenState();
}

class _DayWiseReportScreenState extends State<DayWiseReportScreen> {
  Map<String, dynamic>? summary;
  Map<String, dynamic>? invoiceRange;
  bool isLoading = false;
  DateTime startDate = DateTime.now();
  DateTime endDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    fetchDayWiseReports();
  }

  String formatDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  Future<void> selectDate(BuildContext context, bool isStartDate) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStartDate ? startDate : endDate,
      firstDate: DateTime(2024, 1),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isStartDate) startDate = picked;
        else endDate = picked;
      });
      fetchDayWiseReports();
    }
  }

  Future<void> fetchDayWiseReports() async {
    setState(() => isLoading = true);

    final url = Uri.parse(
      '${dotenv.env['API_URL']}/other-reports/day-wise-report'
      '?startDate=${formatDate(startDate)}&endDate=${formatDate(endDate)}',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          summary = data['total'];
          print(summary);
          invoiceRange = summary!['invoiceRange'];
        });
      } else {
        setState(() {
          summary = null;
          invoiceRange = null;
        });
      }
    } catch (e) {
      print('Error fetching reports: $e');
      setState(() {
        summary = null;
        invoiceRange = null;
      });
    }

    setState(() => isLoading = false);
  }

  /// Downloads report in specified format (Excel or CSV)
  /// Uses scoped storage - no MANAGE_EXTERNAL_STORAGE permission needed
  /// Files automatically save to user-accessible Downloads folder
  Future<void> downloadReport(String format) async {
    final String formattedStart = formatDate(startDate);
    final String formattedEnd = formatDate(endDate);
    final url = Uri.parse(
      '${dotenv.env['API_URL']}/other-reports/day-wise-report/download?startDate=$formattedStart&endDate=$formattedEnd&exportType=$format',
    );

    try {
      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Downloading...'), duration: Duration(seconds: 1)),
      );

      // Fetch file bytes from backend
      final response = await http.get(url);
      if (response.statusCode != 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed. Status: ${response.statusCode}')),
        );
        return;
      }

      final bytes = response.bodyBytes;

      // Build filename
      final fileName = 'DayWiseReport_${formattedStart}_to_${formattedEnd}.$format';

      // Save to Downloads using scoped storage (Android 10+)
      final filePath = await StorageHelper.saveToDownloads(
        bytes: bytes,
        fileName: fileName,
        context: context,
      );

      if (filePath == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save file')),
        );
        return;
      }

      // Success
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloaded to: $filePath')),
      );
      debugPrint('File saved at: $filePath');

      // Try to open file
      try {
        await OpenFile.open(filePath);
      } catch (e) {
        debugPrint('OpenFile failed: $e');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File saved. Open it from your Downloads folder.')),
        );
      }
    } catch (e, st) {
      debugPrint('Download error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    }
  }


  TableRow buildRow(String label, String value) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8, left: 20),
          child: Text(label, style: GoogleFonts.poppins(fontSize: 13, color: Colors.black87)),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8, right: 20),
          child: Text(value,
              textAlign: TextAlign.right,
              style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }

  Widget buildReportCard() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Summary from ${DateFormat('dd MMM yyyy').format(startDate)} to ${DateFormat('dd MMM yyyy').format(endDate)}',
              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            
            const SizedBox(height: 16),
            Table(
              border: TableBorder.all(color: Colors.grey.shade300),
              columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(2)},
              children: [
                buildRow('Date', '${DateFormat('dd MMM yyyy').format(startDate)} - ${DateFormat('dd MMM yyyy').format(endDate)}'),
                buildRow('Orders Count', '${summary?['orderCount'] ?? '0'}'),
                buildRow('Invoice Range', '#${invoiceRange?['start'] ?? '-'} - #${invoiceRange?['end'] ?? '-'}'),
                buildRow('Sub Total', '₹${summary?['subTotal'] ?? '0.00'}'),
                buildRow('Discount', '₹${summary?['discount'] ?? '0.00'}'),
                buildRow('Service Charges', '₹${summary?['serviceCharges'] ?? '0.00'}'),
                buildRow('Tax', '₹${summary?['tax'] ?? '0.00'}'),
                buildRow('Round-off', '₹${summary?['roundOff'] ?? '0.00'}'),
                buildRow('Grand Total', '₹${summary?['grandTotal'] ?? '0.00'}'),
                buildRow('Net Sales', '₹${summary?['netSales'] ?? '0.00'}'),
                buildRow('Cash', '₹${summary?['cash'] ?? '0.00'}'),
                buildRow('Card', '₹${summary?['card'] ?? '0.00'}'),
                buildRow('UPI', '₹${summary?['upi'] ?? '0.00'}'),
              ],
            ),
          ],
        ),
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
        title: Text('Day Wise Report', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () => selectDate(context, true),
                  icon: const Icon(Icons.calendar_today_outlined, size: 16, color: Colors.black54),
                  label: Text(DateFormat('d MMM yyyy').format(startDate), style: GoogleFonts.poppins(fontSize: 13)),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.grey.shade200,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    alignment: Alignment.centerLeft,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => selectDate(context, false),
                  icon: const Icon(Icons.calendar_today_outlined, size: 16, color: Colors.black54),
                  label: Text(DateFormat('d MMM yyyy').format(endDate), style: GoogleFonts.poppins(fontSize: 13)),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.grey.shade200,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    alignment: Alignment.centerLeft,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => downloadReport('xlsx'),
                  icon: const Icon(Icons.table_chart),
                  label: const Text('Excel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => downloadReport('csv'),
                  icon: const Icon(Icons.file_copy),
                  label: const Text('CSV'),
                ),
              ],
            ),

            const SizedBox(height: 20),
            isLoading
                ? const Expanded(child: Center(child: CircularProgressIndicator()))
                : summary == null
                    ? const Expanded(child: Center(child: Text('No data available')))
                    : Expanded(child: buildReportCard()),
          ],
        ),
      ),
    );
  }
}
