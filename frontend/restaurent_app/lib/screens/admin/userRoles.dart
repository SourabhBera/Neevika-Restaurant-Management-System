import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:Neevika/screens/Admin/UsersByRole.dart';


class ViewUserRoleScreen extends StatefulWidget {
  const ViewUserRoleScreen({super.key});

  @override
  State<ViewUserRoleScreen> createState() => _ViewUserRoleScreenState();
}

class _ViewUserRoleScreenState extends State<ViewUserRoleScreen> {
  List<dynamic> userRoles = [];
  bool isLoading = true;
  bool hasErrorOccurred = false;

  @override
  void initState() {
    super.initState();
    fetchUserRoles();
  }
Future<void> fetchUserRoles() async {
  try {
    final response = await http
        .get(Uri.parse('${dotenv.env['API_URL']}/auth/user_role'))
        .timeout(const Duration(seconds: 6));

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      final roles = decoded['roles'] ?? [];

      if (roles is List) {
        setState(() {
          userRoles = roles;
          isLoading = false;
          hasErrorOccurred = false;
        });
      } else {
        throw Exception("Unexpected data format for roles");
      }
    } else {
      await Future.delayed(const Duration(seconds: 4));
      setState(() {
        isLoading = false;
        hasErrorOccurred = true;
      });
    }
  } catch (e) {
    await Future.delayed(const Duration(seconds: 4));
    setState(() {
      isLoading = false;
      hasErrorOccurred = true;
    });
    debugPrint('Error fetching User roles: $e');
  }
}

void showEditRoleDialog(int id, String currentRoleName) {
  final TextEditingController controller = TextEditingController(text: currentRoleName);

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text("Edit Role", style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16)),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: "Role Name",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              String updatedName = controller.text.trim();
              if (updatedName.isNotEmpty) {
                Navigator.of(context).pop(); // Close dialog
                await updateRole(id, updatedName); // Send PUT request
              }
            },
            child: Text("Update"),
          ),
        ],
      );
    },
  );
}


Future<void> updateRole(int id, String updatedName) async {
  final url = Uri.parse('${dotenv.env['API_URL']}/auth/user_role/$id');

  try {
    final response = await http.put(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': updatedName}),
    );

    print(updatedName);

    if (response.statusCode == 200) {
      // Refresh roles list
      fetchUserRoles();
    } else {
      debugPrint('Failed to update role. Status code: ${response.statusCode}');
    }
  } catch (e) {
    debugPrint('Error updating role: $e');
  }
}


Future<void> deleteRole(int id) async {
  final url = Uri.parse('${dotenv.env['API_URL']}/auth/user_role/$id');

  try {
    final response = await http.delete(
      url,
      headers: {'Content-Type': 'application/json'},);

    if (response.statusCode == 200 || response.statusCode == 204) {
      debugPrint('Deleted role successfully. Status code: ${response.statusCode}'); 

      fetchUserRoles();
    } else {
      debugPrint('Failed to delete role. Status code: ${response.statusCode}'); 
    }
  } catch (e) {
    debugPrint('Error deleting role: $e');
  }
}

void showDeleteConfirmationDialog(int id, String roleName) {
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text("Delete Role", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text(
          "Are you sure you want to delete the role \"$roleName\"?",
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFB00020)),
            onPressed: () async {
              Navigator.of(context).pop(); // Close the dialog first
              await deleteRole(id);        // Then delete the role
            },
            child: Text("Delete", style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      );
    },
  );
}

void showAddRoleDialog() {
  final TextEditingController controller = TextEditingController();

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text("Add User Role", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 15)),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: "Role Name",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              String newRoleName = controller.text.trim();
              if (newRoleName.isNotEmpty) {
                Navigator.of(context).pop(); // Close the dialog
                await addNewRole(newRoleName);
              }
            },
            child: Text("Add"),
          ),
        ],
      );
    },
  );
}


Future<void> addNewRole(String roleName) async {
  final url = Uri.parse('${dotenv.env['API_URL']}/auth/user_role');

  try {
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': roleName}),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      debugPrint('Role added successfully');
      fetchUserRoles(); // Refresh the list
    } else {
      debugPrint('Failed to add role. Status code: ${response.statusCode}');
    }
  } catch (e) {
    debugPrint('Error adding role: $e');
  }
}
  

Widget builduserRolesCard(int id, String roleName) {
  return GestureDetector(
    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UsersByRolePage(id: id.toString(),  roleName: roleName.toString()), // 👈 navigate with id
        ),
      );
    },
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      width: MediaQuery.of(context).size.width * 0.9,
      height: MediaQuery.of(context).size.width * 0.14,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Color(0xFFE5E5E5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            roleName,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1C1917),
            ),
          ),
          Row(
            children: [
              IconButton(
                onPressed: () {
                  showEditRoleDialog(id, roleName);
                },
                icon: const Icon(
                  Icons.edit,
                  size: 16,
                  color: Color(0xFF1C1917),
                ),
              ),
              IconButton(
                onPressed: () {
                  showDeleteConfirmationDialog(id, roleName);
                },
                icon: const Icon(
                  Icons.delete,
                  size: 16,
                  color: Color(0xFFB00020),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

  // Build the button below the search bar
  Widget buildAddButton() {
    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.9, 
      height: MediaQuery.of(context).size.width * 0.15, 

      child: Padding(
        padding: const EdgeInsets.only(
          bottom: 12,
        ), // Remove top margin, keep bottom padding
        child: ElevatedButton(
          onPressed: () {
            showAddRoleDialog();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(0xFFD95326), // Red background color
            elevation: 0, // No elevation (flat button)
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            minimumSize: const Size.fromHeight(50),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add, // Add icon
                color: Colors.white, // White icon color
              ),
              SizedBox(width: 8), // Space between icon and text
              Text(
                'Add User Roles', // Text on the button
                style: GoogleFonts.poppins(
                  color: Colors.white, // White text color
                  fontSize: 12,
                ),
              ),
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
            Text(
              'User Roles',
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Manage the roles of the emplyees',
              style: GoogleFonts.poppins(fontSize: 10, color: Colors.black54),
            ),
          ],
        ),
      ),

      body:
          isLoading
              ? Center(
                child: LoadingAnimationWidget.staggeredDotsWave(
                  color: Colors.black,
                  size: 40,
                ),
              )
              : hasErrorOccurred
              ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.alertTriangle,
                      size: 60,
                      color: Color(0xFFEF4444),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "Something went wrong",
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Please check your connection or try again.",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          isLoading = true;
                          hasErrorOccurred = false;
                        });
                        fetchUserRoles();
                      },
                      icon: const Icon(
                        LucideIcons.refreshCw,
                        size: 20,
                        color: Colors.white,
                      ),
                      label: Text(
                        "Retry",
                        style: GoogleFonts.poppins(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
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
                        const SizedBox(height: 18),
                        buildAddButton(),
                        const SizedBox(height: 4),
                        ...userRoles.map((role) => builduserRolesCard(role['id'], role['role_name'])),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
    );
  }
}
