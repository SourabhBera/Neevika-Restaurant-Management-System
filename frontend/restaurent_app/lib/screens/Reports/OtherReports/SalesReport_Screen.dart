// lib/screens/sales_report_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:open_file/open_file.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'download_helper_io.dart'
    if (dart.library.html) 'download_helper_web.dart' as download_helper;
import '../../../utils/storage_helper.dart';

class SalesReportScreen extends StatefulWidget {
  const SalesReportScreen({super.key});

  @override
  _SalesReportScreenState createState() => _SalesReportScreenState();
}

class _SalesReportScreenState extends State<SalesReportScreen> {
  List<Map<String, dynamic>> summaryData = [];

  DateTime startDate = DateTime.now();
  DateTime endDate = DateTime.now();
  String selectedStatus = 'all';
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    fetchSummaryData();
  }

  String formatDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  /// Robust numeric parser:
  /// - accepts num or numeric-string
  /// - strips currency symbols, commas, spaces
  /// - returns 0.0 on parse failure
  double parseNum(dynamic v) {
    try {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      var s = v.toString();
      // remove currency symbols, spaces, commas, and any characters except digits, dot, minus
      s = s.replaceAll(RegExp(r'[^\d\.\-]'), '');
      if (s.isEmpty) return 0.0;
      return double.tryParse(s) ?? 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  /// Pick a value from raw by trying many possible key variants, then fallback to nested maps.
  dynamic pickFromRaw(Map raw, List<String> keys) {
    for (final k in keys) {
      if (raw.containsKey(k)) return raw[k];
    }
    // try case-insensitive match
    for (final entry in raw.entries) {
      final key = entry.key.toString();
      for (final k in keys) {
        if (key.toLowerCase() == k.toLowerCase()) return entry.value;
      }
    }
    // try nested summary object e.g., raw['summary'] might itself be an object with those keys
    if (raw.containsKey('summary') && raw['summary'] is Map) {
      final nested = raw['summary'] as Map;
      for (final k in keys) {
        if (nested.containsKey(k)) return nested[k];
      }
      for (final entry in nested.entries) {
        for (final k in keys) {
          if (entry.key.toString().toLowerCase() == k.toLowerCase()) return entry.value;
        }
      }
    }
    // try top-level first list element if raw itself seems like wrapper: { summary: [ { ... } ] }
    if (raw.containsKey('summary') && raw['summary'] is List && (raw['summary'] as List).isNotEmpty) {
      final fst = (raw['summary'] as List)[0];
      if (fst is Map) {
        for (final k in keys) {
          if (fst.containsKey(k)) return fst[k];
        }
      }
    }
    return null;
  }

  Map<String, dynamic> normalizeSummaryRow(dynamic rawRow) {
    // rawRow might be Map or JSON string
    Map row;
    if (rawRow == null) {
      row = {};
    } else if (rawRow is Map<String, dynamic>) {
      row = rawRow;
    } else if (rawRow is Map) {
      row = Map<String, dynamic>.from(rawRow);
    } else if (rawRow is String) {
      try {
        final parsed = json.decode(rawRow);
        if (parsed is Map) row = Map<String, dynamic>.from(parsed);
        else row = {};
      } catch (_) {
        row = {};
      }
    } else {
      row = {};
    }

    // Extensive key variants to try for each metric
    final totalAmount = parseNum(pickFromRaw(row, ['totalAmount', 'total_amount', 'TotalAmount', 'subtotal', 'subTotal', 'sub_total', 'total']));
    final netSales = parseNum(pickFromRaw(row, ['netSales', 'net_sales', 'net', 'netSale', 'net_sales_amount']));
    final totalSales = parseNum(pickFromRaw(row, ['totalSales', 'grandTotal', 'grand_total', 'grandTotalAmount']));
    final totalDiscount = parseNum(pickFromRaw(row, ['totalDiscount', 'total_discount', 'discount']));
    final gst = parseNum(pickFromRaw(row, ['gst', 'GST', 'cgst_sgst', 'gst_amount', 'cgst']));
    final vat = parseNum(pickFromRaw(row, ['vat', 'VAT', 'vat_amount']));
    final roundOff = parseNum(pickFromRaw(row, ['roundOff', 'round_off']));
    final wavedOff = parseNum(pickFromRaw(row, ['wavedOff', 'waved_off', 'waivedOff', 'waived_off']));
    final cash = parseNum(pickFromRaw(row, ['cash', 'payments.cash', 'payments_cash']));
    final card = parseNum(pickFromRaw(row, ['card', 'payments.card', 'payments_card']));
    final upi = parseNum(pickFromRaw(row, ['upi', 'payments.upi', 'payments_upi']));
    final totalTips = parseNum(pickFromRaw(row, ['totalTips', 'tips', 'tip_amount', 'total_tips']));

    // totalBills robust
    final tbRaw = pickFromRaw(row, ['totalBills', 'total_bills', 'totalBillsCount', 'count']);
    final totalBills = (tbRaw == null) ? 0 : parseNum(tbRaw).toInt();

    // invoiceNos
    final invoiceNos = pickFromRaw(row, ['invoiceNos', 'invoiceNosRange', 'invoice_nos', 'invoice_range']) ?? row['invoiceNos'] ?? '';

    // Compute totalTax as GST + VAT
    final totalTax = gst + vat;

    // If everything numeric is zero, attach _raw for debugging (visible in console)
    final debugNeeded = (totalAmount == 0.0 && netSales == 0.0 && totalSales == 0.0);

    if (debugNeeded) {
      debugPrint('Normalized row produced zeros — raw row: $row');
    }

    return {
      'label': row['label'] ?? row['Label'] ?? '',
      'invoiceNos': invoiceNos,
      'totalBills': totalBills,
      'netSales': netSales,
      'totalAmount': totalAmount,
      'totalDiscount': totalDiscount,
      'gst': gst,
      'vat': vat,
      'totalTax': totalTax,
      'roundOff': roundOff,
      'wavedOff': wavedOff,
      'totalSales': totalSales,
      'cash': cash,
      'card': card,
      'upi': upi,
      'totalTips': totalTips,
      '_raw': row, // keep raw for debugging if you need it
    };
  }

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
          if (endDate.isBefore(startDate)) endDate = startDate;
        } else {
          endDate = picked;
          if (endDate.isBefore(startDate)) startDate = endDate;
        }
      });
      await fetchSummaryData();
    }
  }

  Future<void> fetchSummaryData() async {
    setState(() => isLoading = true);

    final apiBase = dotenv.env['API_URL'] ?? '';
    final url = Uri.parse(
      '$apiBase/other-reports/sales-reports/summary'
      '?startDate=${formatDate(startDate)}&endDate=${formatDate(endDate)}&status=$selectedStatus',
    );

    try {
      debugPrint("Fetching Sales Summary: $url");
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        debugPrint('Sales Summary raw payload: $decoded');

        final serverSummary = decoded['summary'];

        final List<Map<String, dynamic>> normalized = [];

        if (serverSummary is List) {
          for (final item in serverSummary) {
            normalized.add(normalizeSummaryRow(item));
          }
        } else if (serverSummary is Map) {
          normalized.add(normalizeSummaryRow(serverSummary));
        } else if (serverSummary == null && decoded is Map) {
          // fallback: maybe server returned summary fields at top-level
          normalized.add(normalizeSummaryRow(decoded));
        } else {
          // unknown shape — try to coerce
          try {
            final parsed = serverSummary is String ? json.decode(serverSummary) : serverSummary;
            if (parsed is List) {
              for (final item in parsed) normalized.add(normalizeSummaryRow(item));
            } else if (parsed is Map) {
              normalized.add(normalizeSummaryRow(parsed));
            }
          } catch (e) {
            debugPrint('Unable to coerce server summary shape: $e');
          }
        }

        // If normalized rows are all zeros, show first raw in a small snackbar for debugging (only in dev)
        if (normalized.every((r) => (r['totalAmount'] ?? 0) == 0.0)) {
          debugPrint('All normalized summary rows zero. First raw (if any): ${serverSummary is List && serverSummary.isNotEmpty ? serverSummary[0] : serverSummary}');
          // show lightweight debug notice (won't interrupt UX)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Warning: totals parsed as 0. Check server response (see logs).'), duration: Duration(seconds: 3)),
          );
        }

        setState(() {
          summaryData = normalized;
          isLoading = false;
        });
      } else {
        debugPrint('Failed to load summary: ${response.statusCode}');
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load data: ${response.statusCode}')),
        );
      }
    } catch (e, st) {
      debugPrint('fetchSummaryData error: $e\n$st');
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  /// Downloads the sales report and saves to public Downloads when possible.
  /// format: 'pdf' or 'xlsx' (we map 'xlsx' to exportType=excel)
  Future<void> downloadSalesReport(String format) async {
    final apiBase = dotenv.env['API_URL'] ?? '';
    final exportType = (format == 'xlsx' || format == 'excel') ? 'excel' : format;
    final url = Uri.parse(
      '$apiBase/other-reports/sales-reports/summary/download'
      '?startDate=${formatDate(startDate)}&endDate=${formatDate(endDate)}&status=$selectedStatus&exportType=$exportType',
    );

    try {
      // Show loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Downloading...'), duration: Duration(seconds: 1)),
        );
      }

      // Fetch bytes from backend
      final response = await http.get(url);
      if (response.statusCode != 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: ${response.statusCode}')),
        );
        return;
      }
      final bytes = response.bodyBytes;

      // Build filename in dd-MM-yy format
      final startStr = DateFormat('dd-MM-yy').format(startDate);
      final endStr = DateFormat('dd-MM-yy').format(endDate);
      final ext = exportType == 'excel' ? 'xlsx' : (exportType == 'csv' ? 'csv' : 'pdf');
      final filename = 'Sales-Report_${startStr}_$endStr.$ext';

      // -------- Web path --------
      if (kIsWeb) {
        await download_helper.saveFile(bytes, filename, StorageHelper.getMimeType(filename));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Downloaded (web): $filename')),
        );
        return;
      }

      // -------- Mobile/Desktop path (Android/iOS/Windows/macOS/Linux) --------
      // Uses scoped storage - no MANAGE_EXTERNAL_STORAGE permission needed
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
          'Sales Report',
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
            _buildStatusAndDownloadButtons(textTheme),
            const SizedBox(height: 20),
            if (isLoading)
              const Center(child: CircularProgressIndicator())
            else if (summaryData.isEmpty)
              const Center(child: Text('No sales data found.'))
            else
              _buildSummaryTable(textTheme),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRangePickers(TextTheme textTheme) {
    return Row(
      children: [
        Expanded(
          child: _datePickerButton("Start", startDate, () => selectDate(context, true)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _datePickerButton("End", endDate, () => selectDate(context, false)),
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
      icon: const Icon(Icons.calendar_today_outlined, size: 16, color: Colors.black54),
      label: Text(DateFormat('d MMM yyyy').format(date), style: GoogleFonts.poppins(fontSize: 13)),
    );
  }

  Widget _buildStatusAndDownloadButtons(TextTheme textTheme) {
    return Row(
      children: [
        Text('Status:', style: GoogleFonts.poppins(fontSize: 14)),
        const SizedBox(width: 10),
        DropdownButton<String>(
          value: selectedStatus,
          style: GoogleFonts.poppins(fontSize: 14, color: Colors.black87),
          borderRadius: BorderRadius.circular(10),
          underline: Container(height: 0),
          dropdownColor: Colors.white,
          items: ['all', 'success', 'complimentary', 'sales return'].map((status) {
            return DropdownMenuItem<String>(
              value: status,
              child: Text(status[0].toUpperCase() + status.substring(1)),
            );
          }).toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() => selectedStatus = value);
            fetchSummaryData();
          },
        ),
        const Spacer(),
        _downloadButton(Icons.picture_as_pdf, 'PDF', () => downloadSalesReport('pdf')),
        const SizedBox(width: 8),
        _downloadButton(Icons.table_chart, 'Excel', () => downloadSalesReport('xlsx')),
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
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: MaterialStateProperty.all(Colors.deepPurple.shade50),
          columns: [
            DataColumn(label: _headerCell('Taxable')),
            DataColumn(label: _headerCell('Invoice Nos.')),
            DataColumn(label: _headerCell('Total no. of bills')),
            DataColumn(label: _headerCell('Net Sales')),
            DataColumn(label: _headerCell('Total Amount')),
            DataColumn(label: _headerCell('Total Discount')),
            DataColumn(label: _headerCell('Total GST')),
            DataColumn(label: _headerCell('Total VAT')),
            DataColumn(label: _headerCell('Total Tax')), // GST + VAT
            DataColumn(label: _headerCell('Round Off')),
            DataColumn(label: _headerCell('Waived Off')),
            DataColumn(label: _headerCell('Total Sale')),
            DataColumn(label: _headerCell('Cash')),
            DataColumn(label: _headerCell('Card')),
            DataColumn(label: _headerCell('UPI')),
            DataColumn(label: _headerCell('Total Tips')),
          ],
          rows: summaryData.map((row) {
            String fmtNum(double v) => v.toStringAsFixed(2);

            return DataRow(cells: [
              DataCell(_dataText(row['label'] ?? '')),
              DataCell(_dataText((row['invoiceNos'] ?? '').toString())),
              DataCell(_dataText((row['totalBills'] ?? 0).toString())),
              DataCell(_dataText(fmtNum(row['netSales'] ?? 0.0))),
              DataCell(_dataText(fmtNum(row['totalAmount'] ?? 0.0))),
              DataCell(_dataText(fmtNum(row['totalDiscount'] ?? 0.0))),
              DataCell(_dataText(fmtNum(row['gst'] ?? 0.0))),
              DataCell(_dataText(fmtNum(row['vat'] ?? 0.0))),
              DataCell(_dataText(fmtNum(row['totalTax'] ?? 0.0))), // computed gst+vat
              DataCell(_dataText(fmtNum(row['roundOff'] ?? 0.0))),
              DataCell(_dataText(fmtNum(row['wavedOff'] ?? 0.0))),
              DataCell(_dataText(fmtNum(row['totalSales'] ?? 0.0))),
              DataCell(_dataText(fmtNum(row['cash'] ?? 0.0))),
              DataCell(_dataText(fmtNum(row['card'] ?? 0.0))),
              DataCell(_dataText(fmtNum(row['upi'] ?? 0.0))),
              DataCell(_dataText(fmtNum(row['totalTips'] ?? 0.0))),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _headerCell(String text) => Text(text, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600));

  Widget _dataText(String text) => Text(text, style: GoogleFonts.poppins(fontSize: 12));
}
