import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class LeaveLetterScreen extends StatefulWidget {
  const LeaveLetterScreen({super.key});

  @override
  State<LeaveLetterScreen> createState() => LeaveLetterScreenState();
}

class LeaveLetterScreenState extends State<LeaveLetterScreen> {
  List<UserRecord> _users = [];
  List<UserRecord> _filtered = [];
  final TextEditingController _searchController = TextEditingController();
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    final url = Uri.parse('${dotenv.env['API_URL']}/auth/users');

    try {
      final response = await http.get(url);
      if (!mounted) return;

      if (response.statusCode == 200) {
        final List<dynamic> jsonData = json.decode(response.body);
        final users = jsonData.map((e) => UserRecord.fromJson(e)).toList();
        if (!mounted) return;
        setState(() {
          _users = users;
          _filtered = users;
          _loading = false;
          _error = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  void _filter(String query) {
    final results = _users.where((user) =>
        user.name.toLowerCase().contains(query.toLowerCase()) ||
        user.email.toLowerCase().contains(query.toLowerCase())).toList();

    setState(() {
      _filtered = results;
    });
  }

  void _download(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the link')),
      );
    }
  }

  Future<void> _uploadLeaveLetter(int userId) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null && result.files.single.path != null) {
      final file = result.files.single;
      final uri = Uri.parse('${dotenv.env['API_URL']}/hr/leave/$userId');
      final request = http.MultipartRequest('PUT', uri);
      request.files.add(await http.MultipartFile.fromPath('pdf_file', file.path!));

      try {
        final response = await request.send();
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Leave letter uploaded successfully')),
          );
          await _fetchUsers();
        } else {
          final responseBody = await response.stream.bytesToString();
          debugPrint('Upload failed: $responseBody');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to upload letter')),
          );
        }
      } catch (e) {
        debugPrint('Upload exception: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Upload error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: Text(
          "Leave Letters",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: Colors.black87,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error
              ? const Center(child: Text("Failed to load users."))
              : RefreshIndicator(
                  onRefresh: _fetchUsers,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.search, color: Colors.grey),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  onChanged: _filter,
                                  style: const TextStyle(fontSize: 14),
                                  decoration: const InputDecoration.collapsed(
                                    hintText: "Search by name or email...",
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade100),
                          ),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columnSpacing: 20,
                              headingRowHeight: 48,
                              dataRowHeight: 64,
                              headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                              border: TableBorder(
                                horizontalInside: BorderSide(width: 0.5, color: Colors.grey.shade200),
                              ),
                              columns:  [
                                DataColumn(label: Text('Name', style: GoogleFonts.poppins(fontWeight: FontWeight.w600,fontSize: 12.5))),
                                DataColumn(label: Text('Role', style: GoogleFonts.poppins(fontWeight: FontWeight.w600,fontSize: 12.5))),
                                DataColumn(label: Text('Letter', style: GoogleFonts.poppins(fontWeight: FontWeight.w600,fontSize: 12.5))),
                              ],
                              rows: _filtered.map((user) {
                                final hasLetter = user.appointmentLetterPath != null &&
                                    user.appointmentLetterPath!.isNotEmpty;

                                return DataRow(
                                  cells: [
                                    DataCell(Text(
                                      user.name.isNotEmpty ? user.name : '-',
                                      style: GoogleFonts.poppins(fontSize: 12),
                                    )),
                                    DataCell(Text(
                                      user.role.isNotEmpty ? user.role : '-',
                                      style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
                                    )),
                                    DataCell(Row(
                                      children: [
                                        TextButton.icon(
                                          onPressed: () => _uploadLeaveLetter(user.id),
                                          style: TextButton.styleFrom(
                                            backgroundColor: Colors.orange.shade50,
                                            foregroundColor: Colors.deepOrange,
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                          ),
                                          icon: const Icon(Icons.upload_file, size: 18),
                                          label:  Text("Upload", style: GoogleFonts.poppins(fontSize: 12,)),
                                        ),
                                        const SizedBox(width: 8),
                                        TextButton.icon(
                                          onPressed: hasLetter ? () => _download(user.appointmentLetterPath) : null,
                                          style: TextButton.styleFrom(
                                            backgroundColor: hasLetter ? Colors.green.shade50 : Colors.grey.shade200,
                                            foregroundColor: hasLetter ? Colors.green : Colors.grey,
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                          ),
                                          icon: const Icon(Icons.download, size: 18),
                                          label: Text("Download", style: GoogleFonts.poppins(fontSize: 12,)),
                                        ),
                                      ],
                                    )),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}

class UserRecord {
  final int id;
  final String name;
  final String email;
  final String role;
  final String? appointmentLetterPath;

  UserRecord({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.appointmentLetterPath,
  });

  factory UserRecord.fromJson(Map<String, dynamic> json) {
    return UserRecord(
      id: json['id'],
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      role: json['role']?['name'] ?? 'Unknown',
      appointmentLetterPath: json['leave_letter_path'],
    );
  }
}






