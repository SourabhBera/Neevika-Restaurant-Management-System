// lib/screens/item_wise_report_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import '../../../utils/storage_helper.dart';

class ItemWiseReportScreen extends StatefulWidget {
  const ItemWiseReportScreen({super.key});

  @override
  _ItemWiseReportScreenState createState() => _ItemWiseReportScreenState();
}

class _ItemWiseReportScreenState extends State<ItemWiseReportScreen> {
  List<Map<String, dynamic>> itemWiseData = [];
  List<Map<String, dynamic>> itemWiseSummary = [];

  DateTime startDate = DateTime.now();
  DateTime endDate = DateTime.now();
  String selectedType = 'all';
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    fetchItemWiseData();
  }

  String formatDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  double parseDouble(dynamic value) => double.tryParse(value?.toString() ?? '') ?? 0.0;

  Future<void> selectDate(BuildContext context, bool isStartDate) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStartDate ? startDate : endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        if (isStartDate) {
          startDate = picked;
          // keep endDate not earlier than startDate
          if (endDate.isBefore(startDate)) endDate = startDate;
        } else {
          endDate = picked;
          if (endDate.isBefore(startDate)) startDate = endDate;
        }
      });
      await fetchItemWiseData();
    }
  }

  Future<void> fetchItemWiseData() async {
    setState(() => isLoading = true);

    final apiBase = dotenv.env['API_URL'] ?? '';
    final url = Uri.parse(
      '$apiBase/other-reports/item-wise-report'
      '?startDate=${formatDate(startDate)}&endDate=${formatDate(endDate)}&foodType=$selectedType',
    );

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body) as Map<String, dynamic>;
        debugPrint('ItemWise response: $decoded');

        final serverData = decoded['data'];
        final serverSummary = decoded['summary'];

        setState(() {
          itemWiseData = serverData is List
              ? List<Map<String, dynamic>>.from(serverData.map((e) => Map<String, dynamic>.from(e)))
              : [];
          itemWiseSummary = serverSummary is List
              ? List<Map<String, dynamic>>.from(serverSummary.map((e) => Map<String, dynamic>.from(e)))
              : [];

          // Optional: stable sort by foodType (food first), then category then item
          if (selectedType == 'all' && itemWiseData.isNotEmpty) {
            itemWiseData.sort((a, b) {
              final af = (a['foodType'] ?? '').toString();
              final bf = (b['foodType'] ?? '').toString();
              if (af != bf) {
                if (af == 'food') return -1;
                if (bf == 'food') return 1;
              }
              final ac = (a['categoryName'] ?? '').toString().toLowerCase();
              final bc = (b['categoryName'] ?? '').toString().toLowerCase();
              final cmp = ac.compareTo(bc);
              if (cmp != 0) return cmp;
              final ai = (a['itemName'] ?? '').toString().toLowerCase();
              final bi = (b['itemName'] ?? '').toString().toLowerCase();
              return ai.compareTo(bi);
            });
          }

          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
        debugPrint('Failed to fetch. Status: ${response.statusCode}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load data: ${response.statusCode}')),
        );
      }
    } catch (e, st) {
      debugPrint('fetch error: $e\n$st');
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  /// Downloads report in specified format (PDF or Excel)
  /// Uses scoped storage - no MANAGE_EXTERNAL_STORAGE permission needed
  /// Files automatically save to user-accessible Downloads folder
  Future<void> downloadReport(String format) async {
    final apiBase = dotenv.env['API_URL'] ?? '';
    final exportType = (format == 'xlsx' || format == 'excel') ? 'excel' : format;
    final url = Uri.parse(
      '$apiBase/other-reports/item-wise-report/download'
      '?startDate=${formatDate(startDate)}&endDate=${formatDate(endDate)}&foodType=$selectedType&exportType=$exportType',
    );

    try {
      // Show loading indicator
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Downloading...'), duration: Duration(seconds: 1)),
      );

      // Fetch file bytes from backend
      final response = await http.get(url);
      if (response.statusCode != 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: ${response.statusCode}')),
        );
        return;
      }

      final bytes = response.bodyBytes;

      // Build filename
      final startStr = DateFormat('dd-MM-yy').format(startDate);
      final endStr = DateFormat('dd-MM-yy').format(endDate);
      final ext = exportType == 'excel' ? 'xlsx' : (exportType == 'csv' ? 'csv' : 'pdf');
      final filename = 'Item-Wise-Report_${startStr}_$endStr.$ext';

      // Save to Downloads using scoped storage (Android 10+)
      final filePath = await StorageHelper.saveToDownloads(
        bytes: bytes,
        fileName: filename,
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }




  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = GoogleFonts.poppinsTextTheme(theme.textTheme);

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: Text(
          'Item Wise Report',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDateRangePickers(textTheme),
            const SizedBox(height: 16),
            _buildFilterAndDownloadButtons(textTheme),
            const SizedBox(height: 20),
            _buildSummaryTable(textTheme),
            const SizedBox(height: 20),
            if (isLoading)
              const Center(child: CircularProgressIndicator())
            else if (itemWiseData.isEmpty)
              const Center(child: Text('No item data found.'))
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: _buildDataTable(textTheme),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRangePickers(TextTheme textTheme) {
    return Row(
      children: [
        Expanded(
          child: _datePickerButton(
            "Start",
            startDate,
            () => selectDate(context, true),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _datePickerButton(
            "End",
            endDate,
            () => selectDate(context, false),
          ),
        ),
      ],
    );
  }

  Widget _datePickerButton(String label, DateTime date, VoidCallback onPressed) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        foregroundColor: Colors.black87,
        backgroundColor: Colors.grey.shade100,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        alignment: Alignment.centerLeft,
      ),
      onPressed: onPressed,
      icon: const Icon(
        Icons.calendar_today_outlined,
        size: 16,
        color: Colors.black54,
      ),
      label: Text(
        DateFormat('d MMM yyyy').format(date),
        style: GoogleFonts.poppins(fontSize: 13),
      ),
    );
  }

  Widget _buildFilterAndDownloadButtons(TextTheme textTheme) {
    return Row(
      children: [
        Text('Type:', style: GoogleFonts.poppins(fontSize: 14)),
        const SizedBox(width: 10),
        DropdownButton<String>(
          value: selectedType,
          style: GoogleFonts.poppins(fontSize: 14, color: Colors.black87),
          borderRadius: BorderRadius.circular(10),
          underline: Container(height: 0),
          dropdownColor: Colors.white,
          items: ['all', 'food', 'drink'].map((type) {
            return DropdownMenuItem<String>(
              value: type,
              child: Text(type[0].toUpperCase() + type.substring(1)),
            );
          }).toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() => selectedType = value);
            fetchItemWiseData();
          },
        ),
        const Spacer(),
        // _downloadButton(
        //   Icons.picture_as_pdf,
        //   'PDF',
        //   () => downloadReport('pdf'),
        // ),
        // const SizedBox(width: 8),
        _downloadButton(
          Icons.table_chart,
          'Excel',
          () => downloadReport('excel'), // important: send 'excel' to backend
        ),
      ],
    );
  }

  Widget _downloadButton(IconData icon, String label, VoidCallback onPressed) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.deepPurple.shade400,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _buildSummaryTable(TextTheme textTheme) {
    if (itemWiseSummary.isEmpty) {
      return const SizedBox(); // or a placeholder
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: MaterialStateProperty.all(Colors.deepPurple.shade50),
          columns: [
            DataColumn(label: _headerCell('Label')),
            DataColumn(label: _headerCell('Qty')),
            DataColumn(label: _headerCell('Total Amount')),
            DataColumn(label: _headerCell('Tax')),
            DataColumn(label: _headerCell('Gross Sale')),
          ],
          rows: itemWiseSummary.map((row) {
            String formatNum(dynamic value) {
              if (value == null) return '0.00';
              return (value is num ? value : double.tryParse(value.toString()) ?? 0).toStringAsFixed(2);
            }

            return DataRow(
              cells: [
                DataCell(_dataText(row['label'] ?? '')),
                DataCell(_dataText(formatNum(row['totalQuantity']))),
                DataCell(_dataText('₹${formatNum(row['totalAmount'])}')),
                DataCell(_dataText('₹${formatNum(row['tax'])}')),
                DataCell(_dataText('₹${formatNum(row['grossSale'])}')),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildDataTable(TextTheme textTheme) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: MaterialStateProperty.all(Colors.deepPurple.shade50),
          dataRowColor: MaterialStateProperty.resolveWith(
            (states) => states.contains(MaterialState.selected) ? Colors.deepPurple.shade100 : Colors.white,
          ),
          columns: [
            DataColumn(label: _headerCell('Category')),
            DataColumn(label: _headerCell('Item')),
            DataColumn(label: _headerCell('Qty')),
            DataColumn(label: _headerCell('Price/Item')),
            DataColumn(label: _headerCell('Total Amount')),
            DataColumn(label: _headerCell('Discount')),
            DataColumn(label: _headerCell('Tax')),
            DataColumn(label: _headerCell('Gross Sale')),
          ],
          rows: itemWiseData.map((row) {
            String fmt(dynamic v) => (v == null) ? '0.00' : parseDouble(v).toStringAsFixed(2);

            return DataRow(
              cells: [
                DataCell(_dataText(row['categoryName']?.toString() ?? '')),
                DataCell(_dataText(row['itemName']?.toString() ?? '')),
                DataCell(_dataText((row['totalQuantity'] ?? 0).toString())),
                DataCell(_dataText('₹${fmt(row['pricePerItem'])}')),
                DataCell(_dataText('₹${fmt(row['totalAmount'])}')),
                DataCell(_dataText('₹${fmt(row['discount'])}')),
                DataCell(_dataText('₹${fmt(row['tax'])}')),
                DataCell(_dataText('₹${fmt(row['grossSale'])}')),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _headerCell(String text) => Text(
        text,
        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600),
      );

  Widget _dataText(String text) => Text(text, style: GoogleFonts.poppins(fontSize: 12));
}
