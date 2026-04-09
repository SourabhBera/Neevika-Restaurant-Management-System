import 'dart:convert';
import 'package:Neevika/widgets/sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({Key? key}) : super(key: key);

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  List users = [];
  List filteredUsers = [];
  bool loading = true;
  String _selectedRole = 'All';
  List<String> _roles = ['All'];

  // Roles for edit dropdown (id → name)
  List<Map<String, String>> _roleOptions = [];

  final String? baseUrl = dotenv.env['API_URL'];
  final TextEditingController _searchController = TextEditingController();

  // ── Design tokens ────────────────────────────────────────────────────────────
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
  static const Color _divider      = Color(0xFFEAEEF3);

  // ── Poppins shorthand ────────────────────────────────────────────────────────
  TextStyle _p(double size, FontWeight weight, Color color) =>
      GoogleFonts.poppins(fontSize: size, fontWeight: weight, color: color);

  @override
  void initState() {
    super.initState();
    fetchUsers();
    fetchRoleOptions();
    _searchController.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Filtering ────────────────────────────────────────────────────────────────

  void _applyFilters() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      filteredUsers = users.where((u) {
        final matchesSearch =
            (u['name'] ?? '').toLowerCase().contains(query) ||
            (u['phone_number'] ?? '').contains(query) ||
            (u['role']?['name'] ?? '').toLowerCase().contains(query);
        final matchesRole = _selectedRole == 'All' ||
            (u['role']?['name'] ?? '') == _selectedRole;
        return matchesSearch && matchesRole;
      }).toList();
    });
  }

  void _onSearch() => _applyFilters();

  // ── API calls ────────────────────────────────────────────────────────────────

  Future<void> fetchUsers() async {
    try {
      final res = await http.get(Uri.parse("$baseUrl/admin/users"));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final roleSet = <String>{'All'};
        for (final u in data) {
          final r = u['role']?['name'];
          if (r != null) roleSet.add(r.toString());
        }
        setState(() {
          users = data;
          filteredUsers = data;
          _roles = roleSet.toList();
          loading = false;
        });
      }
    } catch (e) {
      debugPrint("Fetch users error: $e");
      setState(() => loading = false);
    }
  }

  Future<void> fetchRoleOptions() async {
    try {
      final res = await http.get(Uri.parse("$baseUrl/auth/user_role/"));
      if (res.statusCode == 200) {
        final body = json.decode(res.body);
        final List<dynamic> data = body['roles'] ?? body;
        setState(() {
          _roleOptions = data
              .map<Map<String, String>>((r) => {
                    'id': r['id'].toString(),
                    'name': (r['role_name'] ?? r['name'] ?? '').toString(),
                  })
              .toList();
        });
        debugPrint("Loaded role options: $_roleOptions");
      }
    } catch (e) {
      debugPrint("Fetch roles error: $e");
    }
  }

  Future<void> updateUser({
    required String userId,
    required String name,
    required String email,
    required String phone,
    required double salary,
    required String roleId,
  }) async {
    final res = await http.put(
      Uri.parse("$baseUrl/admin/users/$userId"),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "name": name,
        "email": email,
        "phone_number": phone,
        "salary": salary,
        "roleId": roleId,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to update user: ${res.body}');
    }
  }

  Future<void> forceLogout(String userId) async {
    try {
      final res = await http.post(Uri.parse("$baseUrl/auth/logout/$userId"));
      if (res.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("User logged out successfully",
              style: _p(13, FontWeight.w500, Colors.white)),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          backgroundColor: _primary,
        ));
        fetchUsers();
      }
    } catch (e) {
      debugPrint("Logout error: $e");
    }
  }

  // ── Dialogs ──────────────────────────────────────────────────────────────────

  /// Details popup — with an Edit button at the bottom
  void _showUserDetails(Map user) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: _surface,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  _avatar(user['name'] ?? '?'),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user['name'] ?? '-',
                            style: _p(17, FontWeight.w700, _textPrimary)),
                        Text(user['role']?['name'] ?? '-',
                            style: _p(12, FontWeight.w400, _textSecondary)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: _textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: _divider),
              const SizedBox(height: 8),
              _detailRow(Icons.email_outlined, "Email", user['email']),
              _detailRow(
                  Icons.phone_outlined, "Phone", user['phone_number']),
              _detailRow(
                  Icons.location_on_outlined, "Address", user['address']),
              _detailRow(Icons.monetization_on_outlined, "Salary",
                  user['salary']?.toString()),
              _detailRow(Icons.calendar_today_outlined, "Created",
                  user['createdAt']),
              const SizedBox(height: 14),
              // Status badges
              Row(
                children: [
                  _badge(
                    user['isActive'] == true ? "Active" : "Inactive",
                    user['isActive'] == true ? _green : _red,
                    user['isActive'] == true ? _greenBg : _redBg,
                  ),
                  const SizedBox(width: 8),
                  _badge(
                    user['isVerified'] == true ? "Verified" : "Unverified",
                    user['isVerified'] == true ? _green : _red,
                    user['isVerified'] == true ? _greenBg : _redBg,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Edit button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    elevation: 0,
                  ),
                  onPressed: () {
                    Navigator.pop(context); // close details first
                    _showEditDialog(user);
                  },
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label:
                      Text("Edit User", style: _p(13, FontWeight.w600, Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Edit dialog — mirrors UsersByRolePage._showEditDialog
  void _showEditDialog(Map user) async {
    final nameController =
        TextEditingController(text: user['name']?.toString() ?? '');
    final emailController =
        TextEditingController(text: user['email']?.toString() ?? '');
    final phoneController =
        TextEditingController(text: user['phone_number']?.toString() ?? '');
    final salaryController =
        TextEditingController(text: user['salary']?.toString() ?? '');

    if (_roleOptions.isEmpty) await fetchRoleOptions();

    final currentRoleName = (user['role']?['name'] ?? '').toString().trim().toLowerCase();
    String? selectedRoleId = _roleOptions.isNotEmpty
        ? (_roleOptions.firstWhere(
            (r) => (r['name'] ?? '').trim().toLowerCase() == currentRoleName,
            orElse: () => _roleOptions.first,
          )['id'])
        : null;
    debugPrint("Pre-selected role: $currentRoleName → id: $selectedRoleId");

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          InputDecoration _field(String label) => InputDecoration(
                labelText: label,
                labelStyle: _p(13, FontWeight.w400, _textSecondary),
                filled: true,
                fillColor: _bg,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: _primary, width: 1.5),
                ),
              );

          return Dialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            backgroundColor: _surface,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Row(
                    children: [
                      Expanded(
                          child: Text("Edit User",
                              style:
                                  _p(17, FontWeight.w700, _textPrimary))),
                      IconButton(
                        icon:
                            const Icon(Icons.close, color: _textSecondary),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  Text(user['name']?.toString() ?? '',
                      style: _p(12, FontWeight.w400, _textSecondary)),
                  const SizedBox(height: 16),
                  const Divider(color: _divider),
                  const SizedBox(height: 16),

                  // Fields
                  TextField(
                    controller: nameController,
                    style: _p(13, FontWeight.w500, _textPrimary),
                    decoration: _field("Name"),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailController,
                    style: _p(13, FontWeight.w500, _textPrimary),
                    decoration: _field("Email"),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneController,
                    style: _p(13, FontWeight.w500, _textPrimary),
                    decoration: _field("Phone"),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: salaryController,
                    style: _p(13, FontWeight.w500, _textPrimary),
                    decoration: _field("Salary"),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedRoleId,
                    style: _p(13, FontWeight.w500, _textPrimary),
                    decoration: _field("Role"),
                    items: _roleOptions
                        .map((r) => DropdownMenuItem<String>(
                              value: r['id'],
                              child: Text(r['name'] ?? '',
                                  style: _p(
                                      13, FontWeight.w500, _textPrimary)),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setDialogState(() => selectedRoleId = v),
                  ),
                  const SizedBox(height: 24),

                  // Actions
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: _divider),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding:
                                const EdgeInsets.symmetric(vertical: 13),
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: Text("Cancel",
                              style: _p(
                                  13, FontWeight.w500, _textSecondary)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding:
                                const EdgeInsets.symmetric(vertical: 13),
                            elevation: 0,
                          ),
                          onPressed: () async {
                            try {
                              await updateUser(
                                userId: user['id'].toString(),
                                name: nameController.text.trim(),
                                email: emailController.text.trim(),
                                phone: phoneController.text.trim(),
                                salary: double.tryParse(
                                        salaryController.text.trim()) ??
                                    0,
                                roleId: selectedRoleId ?? '',
                              );
                              if (!mounted) return;
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                content: Text("User updated successfully",
                                    style: _p(
                                        13, FontWeight.w500, Colors.white)),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(10)),
                                backgroundColor: _green,
                              ));
                              fetchUsers();
                            } catch (e) {
                              if (!mounted) return;
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                content: Text("Failed to update: $e",
                                    style: _p(
                                        13, FontWeight.w500, Colors.white)),
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: _red,
                              ));
                            }
                          },
                          child: Text("Save",
                              style:
                                  _p(13, FontWeight.w600, Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showLogoutConfirm(Map user) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: _surface,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                    color: _redBg, shape: BoxShape.circle),
                child: const Icon(Icons.logout_rounded,
                    color: _red, size: 28),
              ),
              const SizedBox(height: 16),
              Text("Force Logout",
                  style: _p(17, FontWeight.w700, _textPrimary)),
              const SizedBox(height: 8),
              Text(
                "Are you sure you want to force logout ${user['name']}?",
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
                        padding:
                            const EdgeInsets.symmetric(vertical: 13),
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
                        padding:
                            const EdgeInsets.symmetric(vertical: 13),
                        elevation: 0,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        forceLogout(user['id'].toString());
                      },
                      child: Text("Logout",
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

  // ── Helpers ──────────────────────────────────────────────────────────────────

  Widget _avatar(String name) {
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase();
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
          color: _primaryLight, borderRadius: BorderRadius.circular(12)),
      alignment: Alignment.center,
      child: Text(initials, style: _p(15, FontWeight.w700, _primary)),
    );
  }

  Widget _badge(String label, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 7, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: GoogleFonts.poppins(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: _textSecondary),
          const SizedBox(width: 10),
          Text("$label  ", style: _p(12, FontWeight.w500, _textSecondary)),
          Expanded(
              child: Text(value ?? '-',
                  style: _p(12, FontWeight.w600, _textPrimary))),
        ],
      ),
    );
  }

  // ── User card ────────────────────────────────────────────────────────────────

  Widget _userCard(Map user) {
    final bool isActive = user['isActive'] == true;
    final bool isVerified = user['isVerified'] == true;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
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
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          children: [
            _avatar(user['name'] ?? '?'),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () => _showUserDetails(user),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(user['name'] ?? '-',
                        style: _p(14, FontWeight.w700, _textPrimary)),
                    const SizedBox(height: 3),
                    Text(
                      "${user['role']?['name'] ?? '-'}  ·  ${user['phone_number'] ?? '-'}",
                      style: _p(11, FontWeight.w400, _textSecondary),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                _badge(isActive ? "Active" : "Inactive",
                    isActive ? _green : _red, isActive ? _greenBg : _redBg),
                const SizedBox(height: 5),
                _badge(isVerified ? "Verified" : "Unverified",
                    isVerified ? _green : _red,
                    isVerified ? _greenBg : _redBg),
              ],
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert,
                  color: _textSecondary, size: 20),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 4,
              onSelected: (value) {
                if (value == 'details') _showUserDetails(user);
                if (value == 'edit') _showEditDialog(user);
                if (value == 'logout') _showLogoutConfirm(user);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'details',
                  child: Row(children: [
                    const Icon(Icons.person_outline,
                        size: 18, color: _textSecondary),
                    const SizedBox(width: 10),
                    Text("View Details",
                        style: _p(13, FontWeight.w400, _textPrimary)),
                  ]),
                ),
                PopupMenuItem(
                  value: 'edit',
                  child: Row(children: [
                    const Icon(Icons.edit_outlined,
                        size: 18, color: _textSecondary),
                    const SizedBox(width: 10),
                    Text("Edit User",
                        style: _p(13, FontWeight.w400, _textPrimary)),
                  ]),
                ),
                PopupMenuItem(
                  value: 'logout',
                  child: Row(children: [
                    const Icon(Icons.logout_rounded, size: 18, color: _red),
                    const SizedBox(width: 10),
                    Text("Force Logout",
                        style: _p(13, FontWeight.w400, _red)),
                  ]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      drawer: const Sidebar(),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                            Text("User Management",
                                style:
                                    _p(16, FontWeight.w700, _textPrimary)),
                            Text("Manage all system users",
                                style: _p(
                                    10, FontWeight.w400, _textSecondary)),
                          ],
                        ),
                      ),
                      if (!loading)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                              color: _primaryLight,
                              borderRadius: BorderRadius.circular(20)),
                          child: Text("${filteredUsers.length} users",
                              style: _p(11, FontWeight.w600, _primary)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Search + Add User
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          style: _p(13, FontWeight.w400, _textPrimary),
                          decoration: InputDecoration(
                            hintText: "Search users...",
                            hintStyle:
                                _p(13, FontWeight.w400, _textSecondary),
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
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        // ← Navigate to /register
                        onPressed: () =>
                            Navigator.pushNamed(context, '/register'),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text("Add User",
                            style: _p(13, FontWeight.w600, Colors.white)),
                      ),
                    ],
                  ),
                  // Role filter chips
                  if (!loading && _roles.length > 1) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 34,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _roles.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final role = _roles[i];
                          final selected = _selectedRole == role;
                          return GestureDetector(
                            onTap: () {
                              setState(() => _selectedRole = role);
                              _applyFilters();
                            },
                            child: AnimatedContainer(
                              duration:
                                  const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: selected ? _primary : _surface,
                                borderRadius:
                                    BorderRadius.circular(20),
                                border: Border.all(
                                    color:
                                        selected ? _primary : _divider),
                              ),
                              child: Text(
                                role,
                                style: GoogleFonts.poppins(
                                  color: selected
                                      ? Colors.white
                                      : _textSecondary,
                                  fontSize: 12,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── List ────────────────────────────────────────────────────────
            Expanded(
              child: loading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: _primary))
                  : filteredUsers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.person_search_outlined,
                                  size: 52,
                                  color:
                                      _textSecondary.withOpacity(0.4)),
                              const SizedBox(height: 12),
                              Text("No users found",
                                  style: _p(
                                      14, FontWeight.w500, _textSecondary)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(
                              top: 14, bottom: 20),
                          itemCount: filteredUsers.length,
                          itemBuilder: (_, i) =>
                              _userCard(filteredUsers[i]),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}