import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:Neevika/screens/Authentication/login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  List<Map<String, dynamic>> roles = [];
  String? selectedRoleId;
  bool isLoading = false;
  bool isFetchingRoles = true;

  @override
  void initState() {
    super.initState();
    _fetchRoles();
  }

Future<void> _fetchRoles() async {
  try {
    final response = await http.get(Uri.parse('${dotenv.env['API_URL']}/auth/user_role'));
    if (response.statusCode == 200) {
      final Map<String, dynamic> roleData = jsonDecode(response.body);
      final List<dynamic> rolesList = roleData['roles'];

      final filteredRoles = rolesList
          .where((role) =>
              role['role_name'] != 'Admin' && role['id'].toString() != '1')
          .map<Map<String, dynamic>>((role) => {
                'id': role['id'],
                'name': role['role_name'],
              })
          .toList();

      if (!mounted) return; // ✅ Prevent setState after dispose
      setState(() {
        roles = filteredRoles;
        selectedRoleId = roles.isNotEmpty ? roles[0]['id'].toString() : null;
        isFetchingRoles = false;
      });
    } else {
      throw Exception('Failed to load roles');
    }
  } catch (e) {
    print('Role fetch error: $e');
    if (!mounted) return; // ✅ Prevent setState after dispose
    setState(() {
      isFetchingRoles = false;
    });
  }
}


  Future<void> _register() async {
    if (selectedRoleId == null) return;

    setState(() {
      isLoading = true;
    });

    if  (passwordController.text != confirmPasswordController.text){
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Password and Confirm Password does not match', style: GoogleFonts.poppins()),
          backgroundColor: Color(0xFFD95326),
        ),
      );
      return;
    }

    try {
      final url = Uri.parse('${dotenv.env['API_URL']}/auth/register');
      print('\nUser Role $selectedRoleId');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': nameController.text,
          'email': emailController.text,
          'phone_number': phoneController.text,
          'password': passwordController.text,
          'role': selectedRoleId,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registration successful')),
        );
      //   Navigator.pushReplacement(
      //   context,
      //   MaterialPageRoute(builder: (context) => LoginScreen()),
      // );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Registration failed: ${response.body}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

@override
void dispose() {
  nameController.dispose();
  emailController.dispose();
  phoneController.dispose();
  passwordController.dispose();
  confirmPasswordController.dispose();
  super.dispose();
}

  @override
  Widget build(BuildContext context) {
    
    final inputColor = const Color(0xFFF7F2EF);
    final accentRed = const Color(0xFFDD4422);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F5F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F5F2),
        title: Text(
          'Register',
          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
  child: Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Create Account',
           textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
        
        const SizedBox(height: 24),
        _buildInputLabel('Name'),
        _buildTextField(nameController, 'John Doe', inputColor),
        const SizedBox(height: 16),
        _buildInputLabel('Email'),
        _buildTextField(emailController, 'name@example.com', inputColor),
        const SizedBox(height: 16),
        _buildInputLabel('Phone Number'),
        _buildTextField(phoneController, '123456789', inputColor),
        const SizedBox(height: 16),
        _buildInputLabel('Password'),
        _buildTextField(passwordController, '•••••••', inputColor, obscureText: true),
        const SizedBox(height: 16),
        _buildInputLabel('Confirm Password'),
        _buildTextField(confirmPasswordController, '•••••••', inputColor, obscureText: true),
        const SizedBox(height: 16),
        _buildInputLabel('Role'),
        DropdownButtonFormField<String>(
          value: selectedRoleId,
          items: roles.map<DropdownMenuItem<String>>((role) {
            return DropdownMenuItem<String>(
              value: role['id'].toString(),
              child: Text(role['name'], style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              selectedRoleId = value;
            });
          },
          decoration: InputDecoration(
            fillColor: inputColor,
            filled: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide.none,
            ),
          ),
        ),


        const SizedBox(height: 24),
        SizedBox(
          height: 44,
          child: ElevatedButton.icon(
            onPressed: isLoading ? null : _register,
            style: ElevatedButton.styleFrom(
              backgroundColor: accentRed,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            icon: isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.app_registration, size: 18, color: Colors.white),
            label: Text(
              isLoading ? 'Registering...' : 'Register',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    ),
  ),
),

    );
  }

  Widget _buildInputLabel(String label) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, Color fillColor, {bool obscureText = false}) {
    return Center(
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 4),
        child: TextFormField(
          controller: controller,
          obscureText: obscureText,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 12),
            fillColor: fillColor,
            filled: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }
}
