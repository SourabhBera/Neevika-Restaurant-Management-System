import 'package:Neevika/widgets/sidebar.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ViewUsersScreen extends StatefulWidget {
  const ViewUsersScreen({super.key});

  @override
  State<ViewUsersScreen> createState() => _ViewUsersScreenState();
}

class _ViewUsersScreenState extends State<ViewUsersScreen> {
  List<dynamic> users = [];
  List<dynamic> filteredUsers = [];

  bool isLoading = true;
  bool hasErrorOccurred = false;

  final TextEditingController _searchController = TextEditingController();

  // ── Design tokens (same as AdminUsersScreen) ─────────────────────────────────
  static const Color _bg           = Color(0xFFF0F4F8);
  static const Color _surface      = Colors.white;
  static const Color _primary      = Color(0xFF1E5EAF);
  static const Color _primaryLight = Color(0xFFE8F0FB);
  static const Color _textPrimary  = Color(0xFF0F1C2E);
  static const Color _textSecondary = Color(0xFF6B7A8D);
  static const Color _green        = Color(0xFF27AE60);
  static const Color _greenBg      = Color(0xFFE8F8EF);
  static const Color _red          = Color(0xFFE53935);
  static const Color _redBg        = Color(0xFFFDECEC);
  static const Color _amber        = Color(0xFFF59E0B);
  static const Color _amberBg      = Color(0xFFFFF8E7);
  static const Color _divider      = Color(0xFFEAEEF3);

  TextStyle _p(double size, FontWeight weight, Color color) =>
      GoogleFonts.poppins(fontSize: size, fontWeight: weight, color: color);

  @override
  void initState() {
    super.initState();
    fetchUsers();
    _searchController.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch() {
    final q = _searchController.text.toLowerCase();
    setState(() {
      filteredUsers = users.where((u) {
        return (u['name'] ?? '').toLowerCase().contains(q) ||
            (u['email'] ?? '').toLowerCase().contains(q) ||
            (u['phone_number'] ?? '').contains(q);
      }).toList();
    });
  }

  // ── API ───────────────────────────────────────────────────────────────────────

  Future<void> fetchUsers() async {
    try {
      final response = await http
          .get(Uri.parse('${dotenv.env['API_URL']}/auth/unverified-users'))
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        print("\nFetched users: ${decoded['users'].length}\n\n");
        setState(() {
          users = decoded['users'];
          filteredUsers = users;
          isLoading = false;
          hasErrorOccurred = false;
        });
      } else {
        setState(() { isLoading = false; hasErrorOccurred = true; });
      }
    } catch (e) {
      setState(() { isLoading = false; hasErrorOccurred = true; });
      debugPrint("Fetch users error: $e");
    }
  }

  Future<void> approveUser(dynamic userId) async {
    try {
      final response = await http.put(
        Uri.parse('${dotenv.env['API_URL']}/auth/verify-user/$userId'),
      );
      if (response.statusCode == 200) {
        fetchUsers();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("User approved successfully",
              style: _p(13, FontWeight.w500, Colors.white)),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          backgroundColor: _green,
        ));
      }
    } catch (e) {
      debugPrint("Approve error: $e");
    }
  }

  Future<void> rejectUser(dynamic userId) async {
    try {
      final response = await http.delete(
        Uri.parse('${dotenv.env['API_URL']}/auth/reject-user/$userId'),
      );
      if (response.statusCode == 200) {
        fetchUsers();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("User rejected",
              style: _p(13, FontWeight.w500, Colors.white)),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          backgroundColor: _red,
        ));
      }
    } catch (e) {
      debugPrint("Reject error: $e");
    }
  }

  // ── Confirm reject dialog ─────────────────────────────────────────────────────

  void _showRejectConfirm(dynamic user) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: _surface,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration:
                    const BoxDecoration(color: _redBg, shape: BoxShape.circle),
                child: const Icon(Icons.person_remove_outlined,
                    color: _red, size: 28),
              ),
              const SizedBox(height: 16),
              Text("Reject User", style: _p(17, FontWeight.w700, _textPrimary)),
              const SizedBox(height: 8),
              Text(
                "Are you sure you want to reject ${user['name']}? This action cannot be undone.",
                textAlign: TextAlign.center,
                style: _p(13, FontWeight.w400, _textSecondary),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _divider),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text("Cancel",
                          style: _p(13, FontWeight.w500, _textSecondary)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _red,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        elevation: 0,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        rejectUser(user['id']);
                      },
                      child: Text("Reject",
                          style: _p(13, FontWeight.w600, Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  Widget _avatar(String name) {
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase();
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
          color: _primaryLight, borderRadius: BorderRadius.circular(13)),
      alignment: Alignment.center,
      child: Text(initials, style: _p(15, FontWeight.w700, _primary)),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: _textSecondary),
          const SizedBox(width: 8),
          Text("$label  ", style: _p(11, FontWeight.w600, _textSecondary)),
          Expanded(
              child: Text(value, style: _p(11, FontWeight.w400, _textPrimary))),
        ],
      ),
    );
  }

  // ── User card ─────────────────────────────────────────────────────────────────

  Widget _buildUserCard(dynamic user) {
    String createdDate = '';
    if (user['createdAt'] != null) {
      final date = DateTime.tryParse(user['createdAt'].toString());
      if (date != null) {
        createdDate = DateFormat('dd MMM yyyy • hh:mm a').format(date);
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF1E5EAF).withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top row: avatar + name + badge ──────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _avatar(user['name'] ?? '?'),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user['name'] ?? 'User',
                          style: _p(14, FontWeight.w700, _textPrimary)),
                      const SizedBox(height: 2),
                      Text(user['role']?['name'] ?? 'Role',
                          style: _p(11, FontWeight.w400, _textSecondary)),
                    ],
                  ),
                ),
                // Unverified badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: _amberBg,
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.circle, size: 7, color: _amber),
                      const SizedBox(width: 4),
                      Text("Unverified",
                          style: _p(10, FontWeight.w600, _amber)),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),
            const Divider(color: _divider, height: 1),
            const SizedBox(height: 12),

            // ── Info rows ────────────────────────────────────────────────────
            _infoRow(Icons.email_outlined, "Email",
                user['email'] ?? 'N/A'),
            _infoRow(Icons.phone_outlined, "Phone",
                user['phone_number'] ?? 'N/A'),
            if (createdDate.isNotEmpty)
              _infoRow(Icons.calendar_today_outlined, "Created", createdDate),

            const SizedBox(height: 16),

            // ── Action buttons ───────────────────────────────────────────────
            Row(
              children: [
                // Approve
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => approveUser(user['id']),
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: Text("Approve",
                        style: _p(12, FontWeight.w600, Colors.white)),
                  ),
                ),
                const SizedBox(width: 10),
                // Reject
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _red,
                      side: const BorderSide(color: _red, width: 1.2),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => _showRejectConfirm(user),
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: Text("Reject",
                        style: _p(12, FontWeight.w600, _red)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      drawer: const Sidebar(),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Container(
              color: _surface,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Builder(
                        builder: (ctx) => IconButton(
                          onPressed: () => Scaffold.of(ctx).openDrawer(),
                          icon: const Icon(Icons.menu_rounded,
                              color: _textPrimary, size: 22),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("User Approvals",
                                style: _p(16, FontWeight.w700, _textPrimary)),
                            Text("Approve new registered users",
                                style:
                                    _p(10, FontWeight.w400, _textSecondary)),
                          ],
                        ),
                      ),
                      if (!isLoading && !hasErrorOccurred)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                              color: _amberBg,
                              borderRadius: BorderRadius.circular(20)),
                          child: Text("${filteredUsers.length} pending",
                              style: _p(11, FontWeight.w600, _amber)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Search bar
                  TextField(
                    controller: _searchController,
                    style: _p(13, FontWeight.w400, _textPrimary),
                    decoration: InputDecoration(
                      hintText: "Search users...",
                      hintStyle: _p(13, FontWeight.w400, _textSecondary),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: _textSecondary, size: 20),
                      filled: true,
                      fillColor: _bg,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Body ────────────────────────────────────────────────────────
            Expanded(
              child: isLoading
                  ? Center(
                      child: LoadingAnimationWidget.staggeredDotsWave(
                          color: _primary, size: 40),
                    )
                  : hasErrorOccurred
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(LucideIcons.alertTriangle,
                                  size: 52, color: _red),
                              const SizedBox(height: 16),
                              Text("Something went wrong",
                                  style: _p(
                                      16, FontWeight.w600, _textPrimary)),
                              const SizedBox(height: 6),
                              Text("Please check your connection and retry.",
                                  style: _p(
                                      12, FontWeight.w400, _textSecondary)),
                              const SizedBox(height: 24),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _primary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 13),
                                  elevation: 0,
                                ),
                                onPressed: () {
                                  setState(() {
                                    isLoading = true;
                                    hasErrorOccurred = false;
                                  });
                                  fetchUsers();
                                },
                                icon: const Icon(LucideIcons.refreshCw,
                                    size: 16),
                                label: Text("Retry",
                                    style: _p(
                                        13, FontWeight.w600, Colors.white)),
                              ),
                            ],
                          ),
                        )
                      : filteredUsers.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.how_to_reg_outlined,
                                      size: 52,
                                      color:
                                          _textSecondary.withOpacity(0.4)),
                                  const SizedBox(height: 12),
                                  Text("No pending approvals",
                                      style: _p(14, FontWeight.w500,
                                          _textSecondary)),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.only(
                                  top: 14, bottom: 24),
                              itemCount: filteredUsers.length,
                              itemBuilder: (_, i) =>
                                  _buildUserCard(filteredUsers[i]),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}