import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class UsersByRolePage extends StatefulWidget {
  final String id;
  final String roleName;

  const UsersByRolePage({super.key, required this.id, required this.roleName});

  @override
  _UsersByRolePageState createState() => _UsersByRolePageState();
}

class _UsersByRolePageState extends State<UsersByRolePage> {
  late Future<List<TransferRecord>> _usersByRole;

  @override
  void initState() {
    super.initState();
    _usersByRole = fetchUsersByRole(widget.id);
  }

  Future<List<TransferRecord>> fetchUsersByRole(String id) async {
    final response = await http.get(
      Uri.parse('${dotenv.env['API_URL']}/auth/user_role/$id'),
    );
    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(response.body);

      return data.map((json) => TransferRecord.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load users by role');
    }
  }

  Future<List<UserRole>> fetchRoles() async {
    final response = await http.get(
      Uri.parse('${dotenv.env['API_URL']}/auth/user_role/'),
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> jsonBody = json.decode(response.body);
      final List<dynamic> data = jsonBody['roles'];

      return data.map((json) => UserRole.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load roles');
    }
  }

  void _showEditDialog(TransferRecord user) async {
    final nameController = TextEditingController(text: user.name);
    final emailController = TextEditingController(text: user.email);
    final phoneController = TextEditingController(text: user.phoneNumber);
    final salaryController = TextEditingController(
      text: user.salary != null ? user.salary.toString() : '',
    );

    List<UserRole> roles = await fetchRoles();
    String? selectedRoleId = roles.isNotEmpty ? widget.id : null;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Edit User'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Name'),
                    ),
                    TextField(
                      controller: emailController,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    TextField(
                      controller: phoneController,
                      decoration: const InputDecoration(labelText: 'Phone'),
                    ),
                    TextField(
                      controller: salaryController,
                      decoration: const InputDecoration(labelText: 'Salary'),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: selectedRoleId,
                      decoration: const InputDecoration(labelText: 'Role'),
                      items:
                          roles.map((role) {
                            return DropdownMenuItem<String>(
                              value: role.id,
                              child: Text(role.name),
                            );
                          }).toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedRoleId = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                ElevatedButton(
                  child: const Text('Save'),
                  onPressed: () async {
                    try {
                      await updateUser(
                        userId: user.id,
                        name: nameController.text.trim(),
                        email: emailController.text.trim(),
                        phone: phoneController.text.trim(),
                        salary:
                            double.tryParse(salaryController.text.trim()) ?? 0,
                        roleId: selectedRoleId ?? '',
                      );

                      Navigator.of(context).pop();

                      // Refresh list
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder:
                              (context) => UsersByRolePage(
                                id: widget.id,
                                roleName: widget.roleName,
                              ),
                        ),
                      );

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('User updated successfully')),
                      );
                    } catch (e) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to update user: $e')),
                      );
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> updateUser({
    required String userId,
    required String name,
    required String email,
    required String phone,
    required double salary,
    required String roleId,
  }) async {
    final url = Uri.parse('${dotenv.env['API_URL']}/admin/users/$userId');

    final body = jsonEncode({
      "name": name,
      "email": email,
      "phone_number": phone,
      "salary": salary,
      "roleId": roleId,
    });
    debugPrint("Body: $body");

    final headers = {'Content-Type': 'application/json'};

    final response = await http.put(url, headers: headers, body: body);

    if (response.statusCode != 200) {
      throw Exception('Failed to update user: ${response.body}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLargeScreen = MediaQuery.of(context).size.width >= 600;
    // debugPrint("Roles: ${widget.id}");
    return Scaffold(
      backgroundColor: const Color(0xFFF8F5F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F5F2),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.roleName} Details',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            Text(
              'Manage your Roles',
              style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: FutureBuilder<List<TransferRecord>>(
        future: _usersByRole,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text('No users available for this role.'),
            );
          }

          final users = snapshot.data!;

          if (isLargeScreen) {
            // DataTable layout
            return SingleChildScrollView(
              scrollDirection: Axis.vertical,
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'List of employees in ${widget.roleName}',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(
                        Colors.deepPurple.shade100,
                      ),
                      dataRowColor: WidgetStateProperty.all(Colors.white),
                      columns: const [
                        DataColumn(label: Text('Name')),
                        DataColumn(label: Text('Email')),
                        DataColumn(label: Text('Phone')),
                        DataColumn(label: Text('Salary')),
                        DataColumn(label: Text('Edit')),
                      ],
                      rows:
                          users.map((record) {
                            return DataRow(
                              cells: [
                                DataCell(
                                  Text(
                                    record.name,
                                    style: GoogleFonts.poppins(),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    record.email,
                                    style: GoogleFonts.poppins(),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    record.phoneNumber.isNotEmpty
                                        ? record.phoneNumber
                                        : 'N/A',
                                    style: GoogleFonts.poppins(),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    record.salary != null
                                        ? record.salary!.toString()
                                        : 'N/A',
                                    style: GoogleFonts.poppins(),
                                  ),
                                ),
                                DataCell(
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 18),
                                    onPressed: () {
                                      _showEditDialog(record);
                                    },
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                    ),
                  ),
                ],
              ),
            );
          } else {
            // Card layout
            return ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: users.length,
              itemBuilder: (context, index) {
                final user = users[index];
                return Card(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  margin: const EdgeInsets.symmetric(
                    vertical: 4.0,
                    horizontal: 8,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                user.name,
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 18),
                              tooltip: 'Edit User',
                              onPressed: () => _showEditDialog(user),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Email: ${user.email}',
                          style: GoogleFonts.poppins(
                            fontSize: 10.5,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Phone: ${user.phoneNumber.isNotEmpty ? user.phoneNumber : 'N/A'}",
                          style: GoogleFonts.poppins(
                            fontSize: 10.5,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Salary: ${user.salary.toString()}",
                          style: GoogleFonts.poppins(
                            fontSize: 10.5,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          }
        },
      ),
    );
  }
}

class TransferRecord {
  final String id;
  final String name;
  final String email;
  final String phoneNumber;
  final double? salary;

  TransferRecord({
    required this.id,
    required this.name,
    required this.email,
    required this.phoneNumber,
    required this.salary,
  });

  factory TransferRecord.fromJson(Map<String, dynamic> json) {
    return TransferRecord(
      id: json['id'].toString(),
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      phoneNumber: json['phone_number'] ?? '',
      salary:
          json['salary'] != null ? (json['salary'] as num).toDouble() : null,
    );
  }
}

class UserRole {
  final String id;
  final String name;

  UserRole({required this.id, required this.name});

  factory UserRole.fromJson(Map<String, dynamic> json) {
    return UserRole(
      id: json['id'].toString(),
      name: json['role_name'], // ✅ match API key
    );
  }
}
