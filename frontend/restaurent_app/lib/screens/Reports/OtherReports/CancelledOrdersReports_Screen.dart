// Reports/OtherReports/CancelledOrdersReports_Screen.dart

// lib/screens/cancelled_orders_report_screen.dart
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'download_helper_io.dart'
    if (dart.library.html) 'download_helper_web.dart' as download_helper;
import 'package:flutter/foundation.dart' show kIsWeb;

class CancelledOrdersReportScreen extends StatefulWidget {
  const CancelledOrdersReportScreen({super.key});

  @override
  State<CancelledOrdersReportScreen> createState() =>
      _CancelledOrdersReportScreenState();
}

class _CancelledOrdersReportScreenState
    extends State<CancelledOrdersReportScreen> {
  List<Map<String, dynamic>> reportData = [];
  List<Map<String, dynamic>> summaryData = [];

  DateTime startDate = DateTime.now();
  DateTime endDate = DateTime.now();

  // Filter state
  String selectedType = 'all';         // 'all' | 'food' | 'drink'
  String selectedApproval = 'all';     // 'all' | 'true' | 'false'

  bool isLoading = false;

  static const _purple      = Color(0xFF7C4DFF);
  static const _purpleLight = Color(0xFFEDE7F6);
  static const _bg          = Color(0xFFF9FAFB);

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  String _fmtDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  double _pd(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;

  // ── Date picker ────────────────────────────────────────────
  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? startDate : endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _purple),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        startDate = picked;
        if (endDate.isBefore(startDate)) endDate = startDate;
      } else {
        endDate = picked;
        if (endDate.isBefore(startDate)) startDate = endDate;
      }
    });
    await _fetchData();
  }

  // ── Fetch ──────────────────────────────────────────────────
  Future<void> _fetchData() async {
    setState(() => isLoading = true);

    final apiBase = dotenv.env['API_URL'] ?? '';

    // Build query params
    final params = {
      'startDate': _fmtDate(startDate),
      'endDate':   _fmtDate(endDate),
      'foodType':  selectedType,
      if (selectedApproval != 'all') 'isApproved': selectedApproval,
    };
    final uri = Uri.parse('$apiBase/other-reports/cancelled-orders-report')
        .replace(queryParameters: params);

    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body) as Map<String, dynamic>;
        final d = decoded['data'];
        final s = decoded['summary'];
        setState(() {
          reportData = d is List
              ? List<Map<String, dynamic>>.from(d.map((e) => Map<String, dynamic>.from(e)))
              : [];
          summaryData = s is List
              ? List<Map<String, dynamic>>.from(s.map((e) => Map<String, dynamic>.from(e)))
              : [];
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
        _snack('Failed to load: ${response.statusCode}');
      }
    } catch (e, st) {
      debugPrint('fetch error: $e\n$st');
      setState(() => isLoading = false);
      _snack('Error: $e');
    }
  }

  // ── Download ───────────────────────────────────────────────
  Future<void> _download(String format) async {
    final apiBase  = dotenv.env['API_URL'] ?? '';
    final expType  = (format == 'xlsx' || format == 'excel') ? 'excel' : format;

    final params = {
      'startDate':  _fmtDate(startDate),
      'endDate':    _fmtDate(endDate),
      'foodType':   selectedType,
      'exportType': expType,
      if (selectedApproval != 'all') 'isApproved': selectedApproval,
    };
    final uri = Uri.parse('$apiBase/other-reports/cancelled-orders-report/download')
        .replace(queryParameters: params);

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        _snack('Download failed: ${response.statusCode}');
        return;
      }

      final bytes    = response.bodyBytes;
      final startStr = DateFormat('dd-MM-yy').format(startDate);
      final endStr   = DateFormat('dd-MM-yy').format(endDate);
      final ext      = expType == 'excel' ? 'xlsx' : (expType == 'csv' ? 'csv' : 'pdf');
      final filename = 'Cancelled-Orders_${startStr}_$endStr.$ext';
      final mime     = ext == 'pdf'
          ? 'application/pdf'
          : ext == 'xlsx'
              ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
              : 'text/csv';

      // Android permission handling
      bool canWrite = true;
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        final sdkInt = info.version.sdkInt ?? 0;
        if (sdkInt >= 33) {
          // Android 13+: Request MANAGE_EXTERNAL_STORAGE
          final status = await Permission.manageExternalStorage.status;
          if (!status.isGranted) canWrite = (await Permission.manageExternalStorage.request()).isGranted;
        } else {
          // Android 12 and below
          final status = await Permission.storage.status;
          if (!status.isGranted) canWrite = (await Permission.storage.request()).isGranted;
        }
      }
      if (!canWrite) { _snack('Storage permission not granted'); return; }

      // Get main Downloads folder (Android public Downloads)
      Directory? dir;
      try {
        if (Platform.isAndroid) {
          dir = Directory('/storage/emulated/0/Download');
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
        } else {
          dir = await getDownloadsDirectory();
        }
      } catch (_) {
        dir = null;
      }
      dir ??= await getApplicationDocumentsDirectory();

      if (dir == null) { _snack('Cannot access storage'); return; }

      String path = '${dir.path}${Platform.pathSeparator}$filename';
      File file = File(path);
      if (await file.exists()) {
        int c = 1;
        final base = filename.replaceFirst(RegExp(r'\.[^.]+$'), '');
        final ext2 = RegExp(r'(\.[^.]+)$').firstMatch(filename)?.group(1) ?? '';
        do {
          path = '${dir.path}${Platform.pathSeparator}${base}($c)$ext2';
          file = File(path);
          c++;
        } while (await file.exists());
      }

      await file.writeAsBytes(bytes);
      _snack('Saved to: $path');
      try { await OpenFile.open(path); } catch (_) {
        _snack('File saved. Open from Downloads.');
      }
    } catch (e, st) {
      debugPrint('Download error: $e\n$st');
      _snack('Download failed: $e');
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ── Build ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: Text(
          'Cancelled Orders Report',
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600, fontSize: 16, color: Colors.black87),
        ),
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDateRow(),
            const SizedBox(height: 14),
            _buildControlsRow(),
            const SizedBox(height: 20),
            _buildSummaryCard(),
            const SizedBox(height: 20),
            if (isLoading)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: CircularProgressIndicator()))
            else if (reportData.isEmpty)
              Center(
                  child: Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Text('No cancelled orders found.',
                          style: GoogleFonts.poppins(
                              fontSize: 13, color: Colors.black54))))
            else
              SingleChildScrollView(
                  scrollDirection: Axis.horizontal, child: _buildDataTable()),
          ],
        ),
      ),
    );
  }

  // ── Date row ───────────────────────────────────────────────
  Widget _buildDateRow() => Row(
        children: [
          Expanded(child: _dateTile('Start', startDate, () => _pickDate(true))),
          const SizedBox(width: 12),
          Expanded(child: _dateTile('End', endDate, () => _pickDate(false))),
        ],
      );

  Widget _dateTile(String label, DateTime date, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      elevation: 1,
      shadowColor: Colors.black12,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            const Icon(Icons.calendar_today_outlined, size: 15, color: Colors.black54),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: GoogleFonts.poppins(fontSize: 10, color: Colors.black45)),
              Text(DateFormat('d MMM yyyy').format(date),
                  style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w500)),
            ]),
          ]),
        ),
      ),
    );
  }

  // ── Controls ───────────────────────────────────────────────
  Widget _buildControlsRow() {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Type filter
        _filterDropdown<String>(
          label: 'Type',
          value: selectedType,
          items: const [
            DropdownMenuItem(value: 'all',   child: Text('All')),
            DropdownMenuItem(value: 'food',  child: Text('Food')),
            DropdownMenuItem(value: 'drink', child: Text('Drink')),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => selectedType = v);
            _fetchData();
          },
        ),

        // Approval filter
        _filterDropdown<String>(
          label: 'Status',
          value: selectedApproval,
          items: const [
            DropdownMenuItem(value: 'all',   child: Text('All')),
            DropdownMenuItem(value: 'true',  child: Text('Approved')),
            DropdownMenuItem(value: 'false', child: Text('Pending')),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => selectedApproval = v);
            _fetchData();
          },
        ),

        // Download buttons
        _dlButton(Icons.table_chart_outlined, 'Excel', () => _download('excel')),
        _dlButton(Icons.picture_as_pdf_outlined, 'PDF', () => _download('pdf')),
        _dlButton(Icons.code, 'CSV', () => _download('csv')),
      ],
    );
  }

  Widget _filterDropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label:', style: GoogleFonts.poppins(fontSize: 13)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                style: GoogleFonts.poppins(fontSize: 13, color: Colors.black87),
                items: items,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      );

  Widget _dlButton(IconData icon, String label, VoidCallback onPressed) =>
      ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label, style: GoogleFonts.poppins(fontSize: 12)),
        style: ElevatedButton.styleFrom(
          backgroundColor: _purple,
          foregroundColor: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
      );

  // ── Summary card ───────────────────────────────────────────
  Widget _buildSummaryCard() {
    if (summaryData.isEmpty) return const SizedBox.shrink();
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: MaterialStateProperty.all(_purpleLight),
            dataRowMinHeight: 36,
            headingRowHeight: 40,
            columnSpacing: 24,
            columns: [
              _col('Label'),
              _col('Qty'),
              _col('Total Amount'),
              _col('Tax'),
              _col('Gross Amount'),
            ],
            rows: summaryData.map((row) {
              String f(dynamic v) =>
                  (v is num ? v : _pd(v)).toStringAsFixed(2);
              return DataRow(cells: [
                DataCell(_cell(row['label']?.toString() ?? '', bold: true)),
                DataCell(_cell((row['quantity'] ?? 0).toString())),
                DataCell(_cell('₹${f(row['totalAmount'])}')),
                DataCell(_cell('₹${f(row['tax'])}')),
                DataCell(_cell('₹${f(row['grossAmount'])}')),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }

  // ── Main data table ────────────────────────────────────────
  Widget _buildDataTable() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: DataTable(
        headingRowColor: MaterialStateProperty.all(_purpleLight),
        columnSpacing: 14,
        dataRowMinHeight: 36,
        headingRowHeight: 42,
        columns: [
          _col('Type'),
          _col('Category'),
          _col('Item'),
          _col('Remarks'),   // waiter's typed name at cancel time
          _col('Table'),
          _col('Section'),
          _col('Qty'),
          _col('Price/Item'),
          _col('Total'),
          _col('CGST'),
          _col('SGST'),
          _col('VAT'),
          _col('Tax'),
          _col('Gross'),
          _col('Ordered By'),
          _col('Cancelled By'),
          _col('Status'),
          _col('Date & Time'),
        ],
        rows: reportData.asMap().entries.map((entry) {
          final idx = entry.key;
          final r   = entry.value;
          String f(dynamic v) => _pd(v).toStringAsFixed(2);

          final rowColor = idx % 2 == 0 ? Colors.white : const Color(0xFFFBFAFF);
          final isApproved = r['isApproved'] == true;

          return DataRow(
            color: MaterialStateProperty.all(rowColor),
            cells: [
              DataCell(_typeChip(r['type']?.toString() ?? '')),
              DataCell(_cell(r['category']?.toString() ?? '')),
              DataCell(_cell(r['itemName']?.toString() ?? '', maxWidth: 120)),
              // Remarks: shown in muted colour — it's the waiter's typed note
              DataCell(_cell(
                r['remarks']?.toString() ?? '',
                maxWidth: 120,
                color: Colors.black45,
                italic: true,
              )),
              DataCell(_cell(r['tableNumber']?.toString() ?? '-')),
              DataCell(_cell(r['sectionNumber']?.toString() ?? '-')),
              DataCell(_cell((r['quantity'] ?? 0).toString())),
              DataCell(_cell('₹${f(r['pricePerItem'])}')),
              DataCell(_cell('₹${f(r['totalAmount'])}')),
              DataCell(_cell('₹${f(r['cgst'])}')),
              DataCell(_cell('₹${f(r['sgst'])}')),
              DataCell(_cell('₹${f(r['vat'])}')),
              DataCell(_cell('₹${f(r['tax'])}')),
              DataCell(_cell('₹${f(r['grossAmount'])}',
                  color: Colors.red.shade700, bold: true)),
              DataCell(_cell(r['orderedBy']?.toString() ?? '-')),
              DataCell(_cell(r['cancelledBy']?.toString() ?? '-')),
              // Approval status chip
              DataCell(_statusChip(isApproved)),
              DataCell(_cell(r['cancelledAt']?.toString() ?? '-')),
            ],
          );
        }).toList(),
      ),
    );
  }

  // ── Widget helpers ─────────────────────────────────────────
  DataColumn _col(String label) => DataColumn(
        label: Text(label,
            style: GoogleFonts.poppins(
                fontSize: 11.5, fontWeight: FontWeight.w600)),
      );

  Widget _cell(
    String text, {
    bool bold = false,
    bool italic = false,
    double? maxWidth,
    Color? color,
  }) {
    Widget child = Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 11.5,
        fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        color: color ?? Colors.black87,
      ),
      overflow: TextOverflow.ellipsis,
      maxLines: 2,
    );
    if (maxWidth != null) child = SizedBox(width: maxWidth, child: child);
    return child;
  }

  Widget _typeChip(String type) {
    final isFood = type == 'food';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isFood ? Colors.orange.shade50 : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: isFood ? Colors.orange.shade200 : Colors.blue.shade200),
      ),
      child: Text(
        type.isEmpty ? '-' : type[0].toUpperCase() + type.substring(1),
        style: GoogleFonts.poppins(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isFood ? Colors.orange.shade800 : Colors.blue.shade800,
        ),
      ),
    );
  }

  Widget _statusChip(bool approved) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: approved ? Colors.green.shade50 : Colors.amber.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: approved ? Colors.green.shade300 : Colors.amber.shade400),
      ),
      child: Text(
        approved ? 'Approved' : 'Pending',
        style: GoogleFonts.poppins(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: approved ? Colors.green.shade800 : Colors.orange.shade800,
        ),
      ),
    );
  }
}