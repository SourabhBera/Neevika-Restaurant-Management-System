import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ScoreboardScreen extends StatefulWidget {
  const ScoreboardScreen({super.key});

  @override
  State<ScoreboardScreen> createState() => _ScoreboardScreenState();
}

class _ScoreboardScreenState extends State<ScoreboardScreen> {
  String selectedView = 'Today';
  List<Map<String, dynamic>> leaderboardData = [];
  bool isLoading = false;

  final List<String> views = ['Today', 'Monthly'];

  DateTimeRange? customRange;
  bool isCustomDate = false;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    customRange = DateTimeRange(start: today, end: today);
    fetchDailyScoreboard();
  }

  Future<void> fetchDailyScoreboard() async {
    setState(() {
      isLoading = true;
    });
    try {
      final response = await http.get(
        Uri.parse('${dotenv.env['API_URL']}/admin/todayScore'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List scoreboard = data['scoreboard'];
        setState(() {
          leaderboardData = scoreboard.map((entry) => {
            "name": entry["userName"],
            "orders": entry["orders"] ?? 0,
            "amount": double.tryParse(entry["totalSales"].toString()) ?? 0,
            "commissionTotal": double.tryParse(entry["commissionTotal"].toString()) ?? 0,
          }).toList();
        });
      } else {
        print("Failed to load scoreboard: ${response.body}");
      }
    } catch (e) {
      print("Error fetching scoreboard: $e");
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> fetchMonthlyScoreboard() async {
    setState(() {
      isLoading = true;
    });
    try {
      final response = await http.get(
        Uri.parse('${dotenv.env['API_URL']}/admin/monthlyScore'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List scoreboard = data['scoreboard'];
        setState(() {
          leaderboardData = scoreboard.map((entry) => {
            "name": entry["userName"],
            "orders": entry["orders"] ?? 0,
            "amount": double.tryParse(entry["totalSales"].toString()) ?? 0,
            "commissionTotal": double.tryParse(entry["commissionTotal"].toString()) ?? 0,
          }).toList();
        });
      } else {
        print("Failed to load monthly scoreboard: ${response.body}");
      }
    } catch (e) {
      print("Error fetching monthly scoreboard: $e");
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> fetchScoreboardByDateRange(DateTime start, DateTime end) async {
    setState(() {
      isLoading = true;
    });
    final startStr = DateFormat('yyyy-MM-dd').format(start);
    final endStr = DateFormat('yyyy-MM-dd').format(end);

    try {
      final response = await http.get(
        Uri.parse(
          '${dotenv.env['API_URL']}/admin/sales-scoreboard?startDate=$startStr&endDate=$endStr',
        ),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List scoreboard = data['scoreboard'];
        setState(() {
          leaderboardData = scoreboard.map((entry) => {
            "name": entry["userName"],
            "orders": entry["orders"] ?? 0,
            "amount": double.tryParse(entry["totalSales"].toString()) ?? 0,
            "commissionTotal": double.tryParse(entry["commissionTotal"].toString()) ?? 0,
          }).toList();
        });
      } else {
        print("Failed custom date fetch: ${response.body}");
      }
    } catch (e) {
      print("Error fetching custom range: $e");
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F5F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F5F2),
        elevation: 0,
        leading: BackButton(color: Colors.black87),
        title: Text(
          "Scoreboard",
          style: GoogleFonts.poppins(
            color: Colors.black87,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSwitchButton(),
            const SizedBox(height: 16),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchButton() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEDEBE9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: views.map((view) {
          final isSelected = selectedView == view;
          final icon = view == 'Today' ? Icons.today : Icons.lock_clock;
          return GestureDetector(
            onTap: () {
              setState(() {
                selectedView = view;
                isCustomDate = false;
                leaderboardData = [];
              });
              if (view == 'Today') {
                fetchDailyScoreboard();
              } else {
                fetchMonthlyScoreboard();
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFFCFAF8) : const Color(0xFFEDEBE9),
                borderRadius: BorderRadius.circular(8),
                boxShadow: isSelected
                    ? [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0,4))]
                    : [],
              ),
              child: AnimatedScale(
                scale: isSelected ? 1.05 : 1.0,
                duration: const Duration(milliseconds: 300),
                child: Row(
                  children: [
                    Icon(icon, size: 20, color: isSelected ? const Color(0xFF1C1917) : const Color(0xFF78726D)),
                    const SizedBox(width: 6),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 350),
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        color: isSelected ? const Color(0xFF1C1917) : const Color(0xFF78726D),
                      ),
                      child: Text(view == 'Today' ? "Today's Rankings" : "Monthly Top 5", style: GoogleFonts.poppins(fontSize: 11)),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildContent() {
    return selectedView == 'Today' ? _buildLeaderboard() : _buildMonthlyView();
  }

  Widget _buildLeaderboard() {
    final today = DateTime.now();
    final formattedToday = DateFormat('dd/MM/yyyy').format(today);
    final displayDate = isCustomDate && customRange != null
        ? '${DateFormat('dd/MM/yyyy').format(customRange!.start)} → ${DateFormat('dd/MM/yyyy').format(customRange!.end)}'
        : formattedToday;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Today's Leaderboard", style: GoogleFonts.poppins(fontSize: 15.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(displayDate, style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.black54)),
            TextButton(
              onPressed: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2023),
                  lastDate: DateTime.now(),
                  initialDateRange: customRange ?? DateTimeRange(start: today, end: today),
                );
                if (picked != null) {
                  setState(() {
                    isCustomDate = true;
                    customRange = picked;
                  });
                  fetchScoreboardByDateRange(picked.start, picked.end);
                }
              },
              child: Text("Custom Date", style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w500, color: const Color(0xFF1C1917))),
            ),
          ],
        ),
        const SizedBox(height: 16),
        isLoading
            ? const Center(child: CircularProgressIndicator())
            : leaderboardData.isEmpty
                ? Center(child: Text("No sales for this date.", style: GoogleFonts.poppins()))
                : _buildLeaderboardTable(leaderboardData),
      ],
    );
  }

  Widget _buildMonthlyView() {
    final now = DateTime.now();
    final monthYear = DateFormat('MMMM yyyy').format(now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Top Performers This Month", style: GoogleFonts.poppins(fontSize: 15.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(monthYear, style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.black54)),
        const SizedBox(height: 16),
        isLoading
            ? const Center(child: CircularProgressIndicator())
            : leaderboardData.isEmpty
                ? Center(child: Text("No sales recorded this month.", style: GoogleFonts.poppins()))
                : _buildLeaderboardTable(leaderboardData),
      ],
    );
  }

  Widget _buildLeaderboardTable(List<Map<String, dynamic>> data) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFEAEAEA))),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        children: [
          _buildHeaderRow(),
          const Divider(height: 16),
          ...data.asMap().entries.map((entry) {
            final index = entry.key + 1;
            final item = entry.value;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: Row(
                children: [
                  SizedBox(width: 32, child: _buildRankBadge(index)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(item['name'], style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500))),
                  SizedBox(width: 40, child: Text(item['orders'].toString(), textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 12))),
                  SizedBox(width: 70, child: Text('₹${NumberFormat('#,##0').format(item['amount'])}', textAlign: TextAlign.end, style: GoogleFonts.poppins(fontSize: 12))),
                  SizedBox(width: 70, child: Text('₹${NumberFormat('#,##0').format(item['commissionTotal'])}', textAlign: TextAlign.end, style: GoogleFonts.poppins(fontSize: 12))),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildHeaderRow() {
    return Row(
      children: [
        SizedBox(width: 40, child: Text("Rank", style: _headerStyle())),
        const SizedBox(width: 12),
        Expanded(child: Text("Waiter", style: _headerStyle())),
        SizedBox(width: 50, child: Text("Orders", textAlign: TextAlign.center, style: _headerStyle())),
        SizedBox(width: 70, child: Text("Amount", textAlign: TextAlign.end, style: _headerStyle())),
        SizedBox(width: 70, child: Text("Incentive", textAlign: TextAlign.end, style: _headerStyle())),
      ],
    );
  }

  TextStyle _headerStyle() {
    return GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w600);
  }

  Widget _buildRankBadge(int rank) {
    if (rank > 3) {
      return Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: const Color(0xFFDDDDDD), width: 1.5)),
        alignment: Alignment.center,
        child: Text(rank.toString(), style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF4B4B4B))),
      );
    }
    Color color;
    switch (rank) {
      case 1:
        color = const Color(0xFFFFC107);
        break;
      case 2:
        color = const Color(0xFFB0BEC5);
        break;
      case 3:
        color = const Color(0xFF8D6E63);
        break;
      default:
        color = Colors.grey;
    }
    return CircleAvatar(
      radius: 13,
      backgroundColor: color,
      child: Text(rank.toString(), style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
    );
  }
}
