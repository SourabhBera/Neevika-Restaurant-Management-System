import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:Neevika/screens/Tables/BillDetailsScreen.dart';


const _kBg = Color(0xFFF8F5F2);
const _kWhite = Colors.white;
const _kBorder = Color(0xFFE5E5E5);
const _kBorderLight = Color(0xFFCCCBCB);
const _kAccent = Color(0xFFD95326);
const _kText = Color(0xFF1C1917);
const _kMuted = Color(0xFF78726D);
const _kTableHeader = Color(0xFFF3F3F3);

// ─────────────────────────────────────────────────────────────────────────────
//  MAIN PAGE
// ─────────────────────────────────────────────────────────────────────────────
class BillsPage extends StatefulWidget {
  const BillsPage({super.key});

  @override
  State<BillsPage> createState() => _BillsPageState();
}

class _BillsPageState extends State<BillsPage> {
  List<dynamic> _allBills = [];
  List<dynamic> _filteredBills = [];
  bool _isLoading = true;
  bool _hasError = false;

  String _searchQuery = '';
  DateTime? _selectedDate;
  String? _selectedSection;
  List<String> _sections = ['All Sections'];

  static const int _pageSize = 60;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _fetchBills();
  }

  Future<void> _fetchBills() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final response = await http
          .get(Uri.parse('${dotenv.env['API_URL']}/tables/bills/'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List<dynamic>;
        print(data);
        data.sort((a, b) => b['id'].compareTo(a['id']));

        final sectionSet = <String>{};
        for (final bill in data) {
          final s = bill['section_name']?.toString();
          if (s != null && s.isNotEmpty) sectionSet.add(s);
        }

        setState(() {
          _allBills = data;
          _filteredBills = data;
          _sections = ['All Sections', ...sectionSet.toList()..sort()];
          _selectedSection = 'All Sections';
          _isLoading = false;
        });
      } else {
        await Future.delayed(const Duration(seconds: 2));
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    } catch (e) {
      await Future.delayed(const Duration(seconds: 2));
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  void _applyFilters() {
    List<dynamic> r = _allBills;

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      r = r.where((bill) {
        final id = bill['id'].toString();
        final table = bill['display_number']?.toString() ?? '';
        final items = (bill['order_details'] as List? ?? [])
            .map((i) => i['item'].toString().toLowerCase())
            .join(' ');
        final section = (bill['section_name'] ?? '').toString().toLowerCase();
        return id.contains(q) ||
            table.contains(q) ||
            items.contains(q) ||
            section.contains(q);
      }).toList();
    }

    if (_selectedDate != null) {
      r = r.where((bill) {
        final dt = DateTime.tryParse(bill['time_of_bill'] ?? '');
        if (dt == null) return false;
        return dt.year == _selectedDate!.year &&
            dt.month == _selectedDate!.month &&
            dt.day == _selectedDate!.day;
      }).toList();
    }

    if (_selectedSection != null && _selectedSection != 'All Sections') {
      r = r
          .where((b) => b['section_name']?.toString() == _selectedSection)
          .toList();
    }

    setState(() {
      _filteredBills = r;
      _currentPage = 0;
    });
  }

  void _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(primary: _kAccent),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _applyFilters();
    }
  }

  void _openBillDetails(dynamic bill) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => BillDetailsPage(
        billId: bill['id'],
        billNumber: bill['id'].toString(),
      ),
    ));
  }

  List<dynamic> get _pageBills {
    final start = _currentPage * _pageSize;
    final end = (start + _pageSize).clamp(0, _filteredBills.length);
    if (start >= _filteredBills.length) return [];
    return _filteredBills.sublist(start, end);
  }

  int get _totalPages =>
      (_filteredBills.length / _pageSize).ceil().clamp(1, 9999);

  double get _totalRevenue => _filteredBills.fold(
      0, (s, b) => s + (double.tryParse(b['final_amount'].toString()) ?? 0));

  int get _todayCount {
    final today = DateTime.now();
    return _filteredBills.where((b) {
      final dt = DateTime.tryParse(b['updatedAt'] ?? '');
      return dt != null &&
          dt.year == today.year &&
          dt.month == today.month &&
          dt.day == today.day;
    }).length;
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _kText),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Text(
              'Bills',
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _kText,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'View and manage all billing records',
              style: GoogleFonts.poppins(fontSize: 10.2, color: _kMuted),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
      body: _isLoading
          ? Center(
              child: LoadingAnimationWidget.staggeredDotsWave(
                color: Colors.black,
                size: 40,
              ),
            )
          : _hasError
              ? _buildErrorView()
              : _buildBody(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.alertTriangle,
              size: 60, color: Color(0xFFEF4444)),
          const SizedBox(height: 16),
          Text('Something went wrong',
              style: GoogleFonts.poppins(
                  fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Please check your connection or try again.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 14, color: _kMuted)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _fetchBills,
            icon: const Icon(LucideIcons.refreshCw,
                size: 18, color: Colors.white),
            label: Text('Retry',
                style: GoogleFonts.poppins(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Stats card ───────────────────────────────────────────────
            _buildStatsCard(),
            const SizedBox(height: 16),

            // ── Bills list card ──────────────────────────────────────────
            _buildBillsCard(),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  STATS CARD
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildStatsCard() {
    final avg = _filteredBills.isEmpty ? 0.0 : _totalRevenue / _filteredBills.length;

    String fmtRevenue(double v) {
      if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
      if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
      return '₹${v.toStringAsFixed(0)}';
    }

    return _surfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Billing Overview',
              style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _kText)),
          const SizedBox(height: 4),
          Text('Summary across all filtered records',
              style: GoogleFonts.poppins(fontSize: 13, color: _kMuted)),
          const SizedBox(height: 20),
          Row(
            children: [
              _statBox('Total Bills', '${_filteredBills.length}'),
              const SizedBox(width: 10),
              _statBox('Revenue', fmtRevenue(_totalRevenue)),
              const SizedBox(width: 10),
              _statBox('Today', '$_todayCount'),
              const SizedBox(width: 10),
              _statBox('Avg Bill', '₹${avg.toStringAsFixed(0)}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statBox(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style:
                    GoogleFonts.poppins(fontSize: 10.5, color: _kMuted)),
            const SizedBox(height: 5),
            Text(value,
                style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: _kText)),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  BILLS LIST CARD
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildBillsCard() {
    return _surfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title ───────────────────────────────────────────────────────
          Text('Bills List',
              style: GoogleFonts.poppins(
                  fontSize: 16.2,
                  fontWeight: FontWeight.w600,
                  color: _kText)),
          const SizedBox(height: 4),
          Text('${_filteredBills.length} records found',
              style: GoogleFonts.poppins(fontSize: 12, color: _kMuted)),
          const SizedBox(height: 16),

          // ── Search ──────────────────────────────────────────────────────
          SizedBox(
            height: 44,
            child: TextField(
              onChanged: (q) {
                _searchQuery = q;
                _applyFilters();
              },
              style: GoogleFonts.poppins(fontSize: 13, color: _kText),
              decoration: InputDecoration(
                hintText: 'Search by bill no, table, item…',
                hintStyle:
                    GoogleFonts.poppins(fontSize: 13, color: _kMuted),
                prefixIcon:
                    const Icon(Icons.search, color: _kMuted, size: 18),
                filled: true,
                fillColor: _kBg,
                contentPadding: const EdgeInsets.symmetric(
                    vertical: 0, horizontal: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                        color: _kBorderLight, width: 1.3)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                        color: _kBorderLight, width: 1.3)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: _kBorder, width: 1.5)),
              ),
            ),
          ),

          const SizedBox(height: 10),

          // ── Date + Section ───────────────────────────────────────────────
          Row(
            children: [
              // Date chip
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: _selectedDate != null
                        ? _kAccent.withOpacity(0.07)
                        : _kBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _selectedDate != null
                          ? _kAccent.withOpacity(0.4)
                          : _kBorderLight,
                      width: 1.3,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.calendar,
                          size: 13,
                          color: _selectedDate != null
                              ? _kAccent
                              : _kMuted),
                      const SizedBox(width: 6),
                      Text(
                        _selectedDate != null
                            ? DateFormat('d MMM yyyy')
                                .format(_selectedDate!)
                            : 'Pick Date',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: _selectedDate != null
                              ? _kAccent
                              : _kMuted,
                          fontWeight: _selectedDate != null
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                      if (_selectedDate != null) ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () {
                            setState(() => _selectedDate = null);
                            _applyFilters();
                          },
                          child: const Icon(Icons.close_rounded,
                              size: 13, color: _kAccent),
                        ),
                      ]
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Section dropdown
              Expanded(
                child: Container(
                  height: 38,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: _kBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: _kBorderLight, width: 1.3),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedSection,
                      isExpanded: true,
                      icon: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: _kMuted),
                      style: GoogleFonts.poppins(
                          color: _kText, fontSize: 11),
                      dropdownColor: _kWhite,
                      items: _sections
                          .map((s) => DropdownMenuItem(
                                value: s,
                                child: Text(s,
                                    style: GoogleFonts.poppins(
                                      fontSize: 11,
                                      color: s == _selectedSection
                                          ? _kAccent
                                          : _kText,
                                    )),
                              ))
                          .toList(),
                      onChanged: (s) {
                        setState(() => _selectedSection = s);
                        _applyFilters();
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ── Table ────────────────────────────────────────────────────────
          _pageBills.isEmpty ? _emptyState()
        : Column(
            children: [
              _tableHeader(),
              SizedBox(
                height: 420,
                child: ListView.builder(
                  itemCount: _pageBills.length,
                  itemBuilder: (context, index) {
                    final bill = _pageBills[index];
                    return _tableRow(bill, index.isOdd);
                  },
                ),
              ),
              const SizedBox(height: 20),
              _paginationBar(),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Table header ─────────────────────────────────────────────────────────
  Widget _tableHeader() {
    return Container(
      decoration: BoxDecoration(
        color: _kTableHeader,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(6),
          topRight: Radius.circular(6),
        ),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          _hCell('No.', flex: 2),
          _hCell('Bill No', flex: 3),
          _hCell('Section', flex: 4),
          _hCell('Table', flex: 2),
          _hCell('Amount', flex: 3),
          _hCell('Date & Time', flex: 5),
        ],
      ),
    );
  }

  Widget _hCell(String label, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
        child: Text(label,
            style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _kText)),
      ),
    );
  }

  // ─── Table row ────────────────────────────────────────────────────────────
  Widget _tableRow(dynamic bill, bool isOdd) {
    final amount =
        double.tryParse(bill['final_amount']?.toString() ?? '0') ?? 0;
    final billId = bill['id']?.toString() ?? '—';
    final tableNo = bill['display_number']?.toString() ?? '—';
    final section = bill['section_name']?.toString() ?? '—';
    final dtRaw = bill['time_of_bill'];
    final dt = dtRaw != null ? DateTime.tryParse(dtRaw) : null;
    final dateStr = dt != null
        ? DateFormat('d MMM yy, h:mm a').format(dt.toLocal())
        : '—';

    // Global serial number across filtered list
    final globalIdx = _filteredBills.indexOf(bill) + 1;

    final Color amtColor = amount >= 2000
        ? const Color(0xFF16A34A)
        : amount >= 500
            ? _kText
            : _kMuted;

    return InkWell(
      onTap: () => _openBillDetails(bill),
      hoverColor: _kAccent.withOpacity(0.04),
      child: Container(
        decoration: BoxDecoration(
          color: isOdd ? const Color(0xFFFAF9F8) : _kWhite,
          border: Border(
            left: const BorderSide(color: _kBorder, width: 1),
            right: const BorderSide(color: _kBorder, width: 1),
            bottom: BorderSide(color: Colors.grey.shade200, width: 1),
          ),
        ),
        child: Row(
          children: [
            _dCell('$globalIdx',
                flex: 2, muted: true, small: true),
            _dCell('#$billId', flex: 3, bold: true),
            _dCell(section, flex: 4,  small: true),
            _dCell('T$tableNo', flex: 2),
            _dCell(
              '₹${amount.toStringAsFixed(0)}',
              flex: 3,
              accentColor: amtColor,
              bold: amount >= 2000,
            ),
            _dCell(dateStr, flex: 5, muted: true, small: true),
          ],
        ),
      ),
    );
  }

  Widget _dCell(
    String text, {
    required int flex,
    bool bold = false,
    bool muted = false,
    bool small = false,
    Color? accentColor,
  }) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
        child: Text(
          text,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.poppins(
            fontSize: small ? 10.5 : 13,
            fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
            color: accentColor ?? (muted ? const Color.fromARGB(255, 97, 92, 88) : _kText),
          ),
        ),
      ),
    );
  }

  // ─── Pagination ───────────────────────────────────────────────────────────
  Widget _paginationBar() {
    final start =
        (_currentPage * _pageSize + 1).clamp(0, _filteredBills.length);
    final end = ((_currentPage + 1) * _pageSize)
        .clamp(0, _filteredBills.length);

    List<int> pages = [];
    if (_totalPages <= 7) {
      pages = List.generate(_totalPages, (i) => i);
    } else {
      pages = [0];
      if (_currentPage > 2) pages.add(-1);
      for (int i = (_currentPage - 1).clamp(1, _totalPages - 2);
          i <= (_currentPage + 1).clamp(1, _totalPages - 2);
          i++) {
        pages.add(i);
      }
      if (_currentPage < _totalPages - 3) pages.add(-1);
      pages.add(_totalPages - 1);
    }

    return Row(
      children: [
        Text('$start–$end of ${_filteredBills.length}',
            style: GoogleFonts.poppins(fontSize: 11, color: _kMuted)),
        const Spacer(),
        _pgBtn(
          icon: Icons.chevron_left_rounded,
          onTap:
              _currentPage > 0 ? () => setState(() => _currentPage--) : null,
          enabled: _currentPage > 0,
        ),
        const SizedBox(width: 4),
        ...pages.map((p) {
          if (p == -1) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Text('…',
                  style: GoogleFonts.poppins(
                      color: _kMuted, fontSize: 12)),
            );
          }
          final active = p == _currentPage;
          return GestureDetector(
            onTap: () => setState(() => _currentPage = p),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: active ? _kAccent : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: active ? _kAccent : _kBorderLight,
                    width: 1.2),
              ),
              alignment: Alignment.center,
              child: Text(
                '${p + 1}',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight:
                      active ? FontWeight.w700 : FontWeight.normal,
                  color: active ? Colors.white : _kMuted,
                ),
              ),
            ),
          );
        }),
        const SizedBox(width: 4),
        _pgBtn(
          icon: Icons.chevron_right_rounded,
          onTap: _currentPage < _totalPages - 1
              ? () => setState(() => _currentPage++)
              : null,
          enabled: _currentPage < _totalPages - 1,
        ),
      ],
    );
  }

  Widget _pgBtn(
      {required IconData icon,
      required VoidCallback? onTap,
      required bool enabled}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: enabled ? _kBg : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: enabled
                  ? _kBorderLight
                  : _kBorderLight.withOpacity(0.4),
              width: 1.2),
        ),
        child: Icon(icon,
            size: 16,
            color: enabled ? _kText : _kMuted.withOpacity(0.4)),
      ),
    );
  }

  // ─── Empty ────────────────────────────────────────────────────────────────
  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            Icon(LucideIcons.fileText,
                size: 44, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No bills match your filters',
                style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _kMuted)),
            const SizedBox(height: 6),
            Text('Try adjusting the search or date filter',
                style: GoogleFonts.poppins(
                    fontSize: 11.5, color: Colors.grey.shade400)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SHARED CARD HELPER
// ─────────────────────────────────────────────────────────────────────────────
Widget _surfaceCard({required Widget child}) {
  return Card(
    color: _kWhite,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: const BorderSide(color: _kBorder),
    ),
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      child: child,
    ),
  );
}