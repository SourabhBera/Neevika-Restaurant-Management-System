// lib/screens/ComplimentaryProfiles/ViewComplimentaryProfilesScreen.dart

import 'package:Neevika/screens/Tables/BillDetailsScreen.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:async';

class ViewComplimentaryProfilesScreen extends StatefulWidget {
  const ViewComplimentaryProfilesScreen({super.key});

  @override
  State<ViewComplimentaryProfilesScreen> createState() => _ViewComplimentaryProfilesScreenState();
}

class _ViewComplimentaryProfilesScreenState extends State<ViewComplimentaryProfilesScreen> {
  List<dynamic> profiles = [];
  List<dynamic> filteredProfiles = [];
  bool isLoading = true;
  bool hasErrorOccurred = false;
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    fetchProfiles();
  }

  Future<void> fetchProfiles() async {
    setState(() {
      isLoading = true;
      hasErrorOccurred = false;
    });

    try {
      final response = await http
          .get(Uri.parse('${dotenv.env['API_URL']}/complimentaryProfiles/'))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        setState(() {
          profiles = body;
          filteredProfiles = profiles;
          isLoading = false;
          hasErrorOccurred = false;
        });
      } else {
        setState(() {
          isLoading = false;
          hasErrorOccurred = true;
        });
      }
    } catch (e) {
      print('Error fetching profiles: $e');
      setState(() {
        isLoading = false;
        hasErrorOccurred = true;
      });
    }
  }

  void filterProfiles(String query) {
    final q = query.toLowerCase();
    final filtered = profiles.where((p) {
      final name = (p['name'] ?? '').toString().toLowerCase();
      final desc = (p['description'] ?? '').toString().toLowerCase();
      return name.contains(q) || desc.contains(q);
    }).toList();
    setState(() {
      filteredProfiles = filtered;
    });
  }

  Widget _safeProfileIcon(String? key) {
    final icon = kProfileIcons[key] ?? Icons.person;
    return Icon(icon, size: 18, color: Colors.white);
  }



  Widget buildProfileCard(dynamic profile) {
    final colorHex = profile['color'] ?? '#E5E7EB'; // fallback gray
    Color chipColor = _parseHexColor(colorHex);

    return Container(
      margin: const EdgeInsets.all(12),
      width: MediaQuery.of(context).size.width * 0.89,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E5E5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: name + active chip + icon + color
          Row(
            children: [
              CircleAvatar(
                backgroundColor: chipColor,
                child: _safeProfileIcon(profile['icon']),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  profile['name'] ?? 'Unnamed profile',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1C1917),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (profile['active'] ?? true) ? const Color(0xFF10B981) : const Color(0xFFF97316),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  (profile['active'] ?? true) ? 'Active' : 'Inactive',
                  style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            profile['description'] ?? '',
            style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF78726D)),
          ),
          const SizedBox(height: 14),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    // Open details screen (fetch totals & bills)
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ComplimentaryProfileDetailsScreen(profileId: profile['id']),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFFF8F5F2),
                    side: const BorderSide(color: Color(0xFFE5E5E5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    "View Bills",
                    style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w500, color: const Color(0xFF1C1917)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    // open edit screen
                    final updated = await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => AddEditComplimentaryProfileScreen(profile: profile)),
                    );
                    if (updated == true) {
                      fetchProfiles();
                    }
                  },
                  icon: const Icon(Icons.edit, size: 16, color: Color(0xFF1C1917)),
                  label: Text('Edit', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w500, color: const Color(0xFF1C1917))),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFFF8F5F2),
                    side: const BorderSide(color: Color(0xFFE5E5E5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 48,
                height: 40,
                child: OutlinedButton(
                  onPressed: () => _confirmDelete(profile['id']),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFE5E5E5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: EdgeInsets.zero,
                    backgroundColor: const Color(0xFFF8F5F2),
                  ),
                  child: const Icon(Icons.delete, color: Colors.red, size: 18),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(int id) async {
    final should = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Profile', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text('Are you sure you want to delete this complimentary profile?', style: GoogleFonts.poppins()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: GoogleFonts.poppins())),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Delete', style: GoogleFonts.poppins(color: Colors.red))),
        ],
      ),
    );

    if (should == true) {
      await _deleteProfile(id);
    }
  }

  Future<void> _deleteProfile(int id) async {
    try {
      final res = await http.delete(Uri.parse('${dotenv.env['API_URL']}/complimentaryProfiles/$id'));
      if (res.statusCode == 200 || res.statusCode == 204) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Profile deleted'), backgroundColor: Colors.green));
        fetchProfiles();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete'), backgroundColor: Colors.red));
      }
    } catch (e) {
      print('delete error: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting profile'), backgroundColor: Colors.red));
    }
  }

  Widget buildSearchBar() {
    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.89,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: TextField(
          style: GoogleFonts.poppins(fontSize: 14, color: Colors.black),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF8F5F2),
            hintText: 'Search Profiles...',
            hintStyle: GoogleFonts.poppins(fontSize: 14, color: const Color(0xFF1C1917)),
            prefixIcon: const Icon(Icons.search, color: Color(0xFF1C1917)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color.fromARGB(255, 204, 203, 203), width: 1.3)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE5E5E5), width: 1.5)),
          ),
          onChanged: (value) {
            setState(() {
              searchQuery = value;
              filterProfiles(value);
            });
          },
        ),
      ),
    );
  }

  Widget buildAddButton() {
    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.89,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ElevatedButton(
          onPressed: () async {
            final created = await Navigator.push(context, MaterialPageRoute(builder: (context) => AddEditComplimentaryProfileScreen()));
            if (created == true) fetchProfiles();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFD95326),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            minimumSize: const Size.fromHeight(50),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add, color: Colors.white),
              const SizedBox(width: 8),
              Text('Add Complimentary Profile', style: GoogleFonts.poppins(color: Colors.white, fontSize: 12)),
            ],
          ),
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Complimentary Profiles', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
            const SizedBox(height: 4),
            Text('Manage complimentary profiles and view bills totals', style: GoogleFonts.poppins(fontSize: 10, color: Colors.black54)),
          ],
        ),
      ),
      body: isLoading
          ? Center(child: LoadingAnimationWidget.staggeredDotsWave(color: Colors.black, size: 40))
          : hasErrorOccurred
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.alertTriangle, size: 60, color: Color(0xFFEF4444)),
                      const SizedBox(height: 16),
                      Text("Something went wrong", style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text("Please check your connection or try again.", textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            isLoading = true;
                            hasErrorOccurred = false;
                          });
                          fetchProfiles();
                        },
                        icon: const Icon(LucideIcons.refreshCw, size: 20, color: Colors.white),
                        label: Text("Retry", style: GoogleFonts.poppins(color: Colors.white)),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                      ),
                    ],
                  ),
                )
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1600),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          const SizedBox(height: 12),
                          buildSearchBar(),
                          buildAddButton(),
                          const SizedBox(height: 12),
                          ...filteredProfiles.map((p) => buildProfileCard(p)),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }

  // helper to parse hex color like '#FF00AA' or 'FF00AA'
  Color _parseHexColor(String hex) {
    String cleaned = hex.replaceAll('#', '').trim();
    if (cleaned.length == 6) cleaned = 'FF$cleaned'; // add alpha
    try {
      return Color(int.parse(cleaned, radix: 16));
    } catch (e) {
      return const Color(0xFFB3B3B3);
    }
  }
}

const Map<String, IconData> kProfileIcons = {
  'restaurant': Icons.restaurant,
  'drink': Icons.local_drink,
  'coffee': Icons.coffee,
  'beverage': Icons.emoji_food_beverage,
  'fastfood': Icons.fastfood,
  'icecream': Icons.icecream,
  'cake': Icons.cake,
  'pizza': Icons.local_pizza,
  'bar': Icons.local_bar,
  'meal': Icons.set_meal,
  'person': Icons.person,
  'people': Icons.people_alt,
};

/// ---------- Add / Edit Screen ----------
class AddEditComplimentaryProfileScreen extends StatefulWidget {
  final Map<String, dynamic>? profile; // if null -> create

  const AddEditComplimentaryProfileScreen({super.key, this.profile});

  @override
  State<AddEditComplimentaryProfileScreen> createState() => _AddEditComplimentaryProfileScreenState();
}

class _AddEditComplimentaryProfileScreenState extends State<AddEditComplimentaryProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  bool _active = true;
  bool _isSaving = false;

  String _selectedIconKey = 'person';
  Color _selectedColor = const Color(0xFFFBBF24);

  

  // Preset icons and colors like Chrome’s profile selector
  final List<String> availableIconKeys = kProfileIcons.keys.toList();


  final List<Color> availableColors = [
    Color(0xFFF87171), // red
    Color(0xFFFBBF24), // yellow
    Color(0xFF34D399), // green
    Color(0xFF60A5FA), // blue
    Color(0xFF818CF8), // indigo
    Color(0xFFEC4899), // pink
    Color(0xFF10B981), // emerald
    Color(0xFFFB923C), // orange
    Color(0xFF6366F1), // violet
    Color(0xFF14B8A6), // teal
  ];

  @override
  void initState() {
    super.initState();
    if (widget.profile != null) {
      _nameCtrl.text = widget.profile!['name'] ?? '';
      _descCtrl.text = widget.profile!['description'] ?? '';
      _active = widget.profile!['active'] ?? true;

      final hexColor = widget.profile!['color'] ?? '#FBBF24';
      _selectedColor = _parseHexColor(hexColor);

      final savedIcon = widget.profile!['icon']?.toString();
      _selectedIconKey = kProfileIcons.containsKey(savedIcon)
          ? savedIcon!
          : 'person';
    }
  }


  Color _parseHexColor(String hex) {
    String cleaned = hex.replaceAll('#', '').trim();
    if (cleaned.length == 6) cleaned = 'FF$cleaned';
    try {
      return Color(int.parse(cleaned, radix: 16));
    } catch (e) {
      return const Color(0xFFFBBF24);
    }
  }

  String _colorToHex(Color color) =>
      '#${color.value.toRadixString(16).substring(2).toUpperCase()}';

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final body = {
      'name': _nameCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'icon': _selectedIconKey,
      'color': _colorToHex(_selectedColor),
      'active': _active,
    };


    try {
      final url = widget.profile == null
          ? Uri.parse('${dotenv.env['API_URL']}/complimentaryProfiles/')
          : Uri.parse('${dotenv.env['API_URL']}/complimentaryProfiles/${widget.profile!['id']}');

      final response = widget.profile == null
          ? await http.post(url,
              headers: {'Content-Type': 'application/json'},
              body: json.encode(body))
          : await http.put(url,
              headers: {'Content-Type': 'application/json'},
              body: json.encode(body));

      if (response.statusCode == 200 || response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved successfully'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save profile'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving profile'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  


  @override
  Widget build(BuildContext context) {
    final isEdit = widget.profile != null;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F5F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F5F2),
        elevation: 0,
        title: Text(isEdit ? 'Edit Profile' : 'Add Profile',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E5E5)),
            ),
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 36,
                            backgroundColor: _selectedColor,
                            child: Icon(
                              kProfileIcons[_selectedIconKey] ?? Icons.person,
                              color: Colors.white,
                              size: 28,
                            ),

                          ),
                          const SizedBox(height: 8),
                          Text('Preview',
                              style: GoogleFonts.poppins(
                                  fontSize: 12, color: Colors.grey[600])),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameCtrl,
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Name required' : null,
                      decoration: InputDecoration(
                        labelText: 'Name',
                        filled: true,
                        fillColor: const Color(0xFFF8F5F2),
                      ),
                      style: GoogleFonts.poppins(),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _descCtrl,
                      decoration: InputDecoration(
                        labelText: 'Description',
                        filled: true,
                        fillColor: const Color(0xFFF8F5F2),
                      ),
                      maxLines: 2,
                      style: GoogleFonts.poppins(),
                    ),
                    const SizedBox(height: 18),
                    Text('Choose an Icon',
                        style: GoogleFonts.poppins(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: availableIconKeys.map((key) {
                        final icon = kProfileIcons[key]!;
                        final selected = _selectedIconKey == key;

                        return GestureDetector(
                          onTap: () => setState(() => _selectedIconKey = key),
                          child: CircleAvatar(
                            radius: 22,
                            backgroundColor:
                                selected ? _selectedColor : const Color(0xFFF3F4F6),
                            child: Icon(
                              icon,
                              color: selected ? Colors.white : Colors.black87,
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 18),
                    Text('Choose a Color',
                        style: GoogleFonts.poppins(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: availableColors
                          .map((color) => GestureDetector(
                                onTap: () => setState(() => _selectedColor = color),
                                child: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: color,
                                  child: _selectedColor == color
                                      ? const Icon(Icons.check,
                                          color: Colors.white, size: 18)
                                      : null,
                                ),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Text('Active',
                            style: GoogleFonts.poppins(fontSize: 14)),
                        const SizedBox(width: 12),
                        Switch(
                            value: _active,
                            onChanged: (v) => setState(() => _active = v)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveProfile,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10))),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Text(
                              isEdit ? 'Save Changes' : 'Create Profile',
                              style:
                                  GoogleFonts.poppins(color: Colors.white)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


/// ---------- Details Screen (profile + bills & totals) ----------
class ComplimentaryProfileDetailsScreen extends StatefulWidget {
  final int profileId;
  const ComplimentaryProfileDetailsScreen({super.key, required this.profileId});

  @override
  State<ComplimentaryProfileDetailsScreen> createState() =>
      _ComplimentaryProfileDetailsScreenState();
}

class _ComplimentaryProfileDetailsScreenState
    extends State<ComplimentaryProfileDetailsScreen> {
  bool isLoading = true;
  bool hasError = false;
  Map<String, dynamic>? profile;
  List<dynamic> bills = [];
  double totalAmount = 0.0;

  @override
  void initState() {
    super.initState();
    fetchProfileDetails();
  }

  // ---------- SAFE INITIAL ----------
  String safeInitial(dynamic val) {
    if (val == null) return "";
    final s = val.toString().trim();
    if (s.isEmpty) return "";
    return s[0].toUpperCase();
  }
Future<void> fetchProfileDetails() async {
  setState(() {
    isLoading = true;
    hasError = false;
  });

  try {
    final url =
        "${dotenv.env['API_URL']}/complimentaryProfiles/${widget.profileId}/bills";

    final res = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 8));

    if (res.statusCode != 200) {
      setState(() {
        isLoading = false;
        hasError = true;
      });
      return;
    }

    final raw = json.decode(res.body);

    /// Handle both response types:
    /// 1) { profile: {...}, bills: [...] }
    /// 2) { ... , bills: [...] }
    Map<String, dynamic> prof =
        (raw is Map && raw['profile'] is Map) ? raw['profile'] : raw;

    List<dynamic> b = [];
    if (raw is Map && raw['bills'] is List) {
      b = raw['bills'];
    }

    /// Calculate total amount safely
    double sum = 0;
    for (var bill in b) {
      if (bill is! Map) continue;

      final fa = bill['final_amount'] ?? bill['finalAmount'] ?? 0;

      double parsed;
      if (fa is num) {
        parsed = fa.toDouble();
      } else {
        parsed = double.tryParse(fa.toString()) ?? 0.0;
      }

      sum += parsed;
    }

    setState(() {
      profile = prof;
      bills = b;
      totalAmount = sum;
      isLoading = false;
    });
  } catch (e) {
    print("fetch profile details error: $e");

    setState(() {
      isLoading = false;
      hasError = true;
    });
  }
}

  Widget buildBillRow(dynamic bill) {
    final id = bill['id'] ?? bill['bill_id'];

    final dtRaw =
        bill['generated_at'] ??
            bill['time_of_bill'] ??
            bill['createdAt'] ??
            bill['created_at'];

    final dt =
        dtRaw != null ? DateTime.tryParse(dtRaw.toString()) : null;

    final formattedDate = dt != null
        ? '${dt.day.toString().padLeft(2, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.year}'
        : (dtRaw?.toString() ?? '-');

    final waiter = bill['waiter'] != null
        ? (bill['waiter']['name'] ?? bill['waiter'])
        : (bill['waiter_id'] ?? '-');

    final table = bill['table_number'] ??
              bill['table']?['id'] ??
              bill['tableId'] ??
              '-';

    final finalAmt = bill['final_amount'] ?? bill['finalAmount'] ?? 0;

    return Container(
      padding:
          const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom:
              BorderSide(color: Colors.grey.shade200, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: Text('#${id.toString()}',
                style: GoogleFonts.poppins(fontSize: 12)),
          ),
          Expanded(
            flex: 2,
            child: Text(formattedDate,
                style: GoogleFonts.poppins(fontSize: 12)),
          ),
          Expanded(
            flex: 2,
            child: Text(waiter.toString(),
                style: GoogleFonts.poppins(fontSize: 12)),
          ),
          Expanded(
            flex: 1,
            child: Text(table.toString(),
                style: GoogleFonts.poppins(fontSize: 12),
                textAlign: TextAlign.center),
          ),
          Expanded(
            flex: 2,
            child: Text('₹${(finalAmt).toString()}',
                style: GoogleFonts.poppins(
                    fontSize: 12, fontWeight: FontWeight.w600),
                textAlign: TextAlign.right),
          ),
        ],
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
        iconTheme: const IconThemeData(color: Colors.black),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Profile Details',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text('Complimentary bills and totals',
                style: GoogleFonts.poppins(
                    fontSize: 10, color: Colors.black54)),
          ],
        ),
      ),
      body: isLoading
          ? Center(
              child: LoadingAnimationWidget.staggeredDotsWave(
                  color: Colors.black, size: 40),
            )
          : hasError
              ? Center(
                  child: Text('Failed to load details',
                      style: GoogleFonts.poppins()))
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: SingleChildScrollView(
                      child: Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: const Color(0xFFE5E5E5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ---------- Header Row ----------
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: _parseHexColor(profile?['color'] ?? '#FBBF24'),
                                  child: safeInitial(profile?['name']).isNotEmpty
                                      ? Text(
                                          safeInitial(profile?['name']),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold),
                                        )
                                      : const Icon(Icons.person, color: Colors.white),
                                ),

                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    profile?['name'] ?? '-',
                                    style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                                Text(
                                  profile?['active'] == true
                                      ? 'Active'
                                      : 'Inactive',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: profile?['active'] == true
                                        ? Colors.green
                                        : Colors.orange,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 10),

                            Text(profile?['description'] ?? '',
                                style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: Colors.grey[700])),

                            const SizedBox(height: 18),

                            // ---------- Summary Cards ----------
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8F5F2),
                                      borderRadius:
                                          BorderRadius.circular(8),
                                      border: Border.all(
                                          color:
                                              const Color(0xFFE5E5E5)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('Total Complimentary Bills',
                                            style: GoogleFonts.poppins(
                                                fontSize: 12,
                                                color: Colors.black54)),
                                        const SizedBox(height: 6),
                                        Text('${bills.length}',
                                            style: GoogleFonts.poppins(
                                                fontSize: 18,
                                                fontWeight:
                                                    FontWeight.w700)),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8F5F2),
                                      borderRadius:
                                          BorderRadius.circular(8),
                                      border: Border.all(
                                          color:
                                              const Color(0xFFE5E5E5)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('Total Complimentary Amount',
                                            style: GoogleFonts.poppins(
                                                fontSize: 12,
                                                color: Colors.black54)),
                                        const SizedBox(height: 6),
                                        Text(
                                            '₹${totalAmount.toStringAsFixed(2)}',
                                            style: GoogleFonts.poppins(
                                                fontSize: 18,
                                                fontWeight:
                                                    FontWeight.w700)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 18),

                            // ---------- Table Header ----------
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                      flex: 1,
                                      child: Text('Bill ID',
                                          style: GoogleFonts.poppins(
                                              fontWeight:
                                                  FontWeight.w600))),
                                  Expanded(
                                      flex: 2,
                                      child: Text('Date',
                                          style: GoogleFonts.poppins(
                                              fontWeight:
                                                  FontWeight.w600))),
                                  Expanded(
                                      flex: 2,
                                      child: Text('Waiter',
                                          style: GoogleFonts.poppins(
                                              fontWeight:
                                                  FontWeight.w600))),
                                  Expanded(
                                      flex: 1,
                                      child: Text('Table',
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.poppins(
                                              fontWeight:
                                                  FontWeight.w600))),
                                  Expanded(
                                      flex: 2,
                                      child: Text('Final Amount',
                                          textAlign: TextAlign.right,
                                          style: GoogleFonts.poppins(
                                              fontWeight:
                                                  FontWeight.w600))),
                                ],
                              ),
                            ),

                            const SizedBox(height: 6),

                            // ---------- Bills List ----------
                            ...bills.map((b) => InkWell(
      onTap: () {
        final id = b['id'] ?? b['bill_id'];
        if (id != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => BillDetailsPage(billId: id),
            ),
          );
        }
      },
      child: buildBillRow(b),
    )),

                          ],
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }

  Color _parseHexColor(String hex) {
    String cleaned = hex.replaceAll('#', '').trim();
    if (cleaned.length == 6) cleaned = 'FF$cleaned';
    try {
      return Color(int.parse(cleaned, radix: 16));
    } catch (e) {
      return const Color(0xFFB3B3B3);
    }
  }
}
