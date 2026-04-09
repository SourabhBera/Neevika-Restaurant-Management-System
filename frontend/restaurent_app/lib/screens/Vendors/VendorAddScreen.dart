import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

class AddVendorScreen extends StatefulWidget {
  const AddVendorScreen({super.key});

  @override
  _AddVendorScreenState createState() => _AddVendorScreenState();
}

class _AddVendorScreenState extends State<AddVendorScreen> {
  final _formKey = GlobalKey<FormState>();

  final vendorNameController = TextEditingController();
  final businessTypeController = TextEditingController();
  final contactPersonController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final addressController = TextEditingController();

  String status = 'Active';
  final List<String> statusOptions = ['Active', 'Inactive'];

void addVendor() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('jwtToken');
  if (token == null) {
    print('No token found. User might not be logged in.');
    return;
  }
  final decodedToken = JwtDecoder.decode(token);
  final userId = decodedToken['id'];

  final String apiUrl = '${dotenv.env['API_URL']}/vendor/';

  final Map<String, dynamic> updatedData = {
    'name': vendorNameController.text,
    'business_type': businessTypeController.text,
    'contact_person': contactPersonController.text,
    'email': emailController.text,
    'phone': phoneController.text,
    'address': addressController.text,
    'status': status.toLowerCase(), // assuming backend expects lowercase
    'userId': userId,
  };

  try {
    final response = await http.post(
      Uri.parse(apiUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(updatedData),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vendor updated successfully!')),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: ${response.statusCode}')),
      );
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error: $e')),
    );
  }
}


  @override
  void dispose() {
    vendorNameController.dispose();
    businessTypeController.dispose();
    contactPersonController.dispose();
    emailController.dispose();
    phoneController.dispose();
    addressController.dispose();
    super.dispose();
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
            'Add Vendor',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add a new supplier to your vendor list',
            style: GoogleFonts.poppins(fontSize: 10, color: Colors.black54),
          ),
        ],
      ),
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20),
        child: Container(
          width: 400, // fixed width like in screenshot
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Color(0xFFE5E7EB),
              width: 1.5,
            ),
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add Vendor Details',
                  style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1C1917),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Add the information for new vendor',
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    color: const Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 12),
                _buildLabel('Vendor Name *'),
                _buildTextField(vendorNameController, hintText: 'Company or business name'),

                _buildLabel('Business Type'),
                _buildTextField(businessTypeController, hintText: 'E.g., Grocery, Meat supplier'),

                _buildLabel('Contact Person'),
                _buildTextField(contactPersonController, hintText: 'Full name'),

                _buildLabel('Email Address'),
                _buildTextField(emailController, hintText: 'example@email.com'),

                _buildLabel('Phone Number'),
                _buildTextField(phoneController, hintText: 'Phone number'),

                _buildLabel('Status'),
                _buildDropdown(),

                _buildLabel('Address'),
                _buildTextField(addressController, maxLines: 3, hintText: 'Enter business address'),

                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 130,
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1C1917),
                          backgroundColor: const Color(0xFFFAFAF9),
                          side: const BorderSide(color: Color(0xFFE5E7EB)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    SizedBox(
                      width: 170,
                      child: ElevatedButton.icon(
                        onPressed: addVendor,
                        icon: const Icon(LucideIcons.save, size: 16),
                        label: Text(
                          'Save Vendor',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}


  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF1C1917),
        ),
      ),
    );
  }

Widget _buildTextField(TextEditingController controller, {int maxLines = 1, String? hintText}) {
  return TextFormField(
    controller: controller,
    maxLines: maxLines,
    style: GoogleFonts.poppins(fontSize: 11),
    decoration: InputDecoration(
      hintText: hintText,

      hintStyle: GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 11),
      filled: true,
      fillColor: const Color(0xFFF9F9F9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(8),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFF6366F1)),
        borderRadius: BorderRadius.circular(8),
      ),
    ),
  );
}

  Widget _buildDropdown() {
    return DropdownButtonFormField<String>(
      value: status,
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFFF9F9F9),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Color(0xFF6366F1)),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      style: GoogleFonts.poppins(fontSize: 11, color: Colors.black),
      onChanged: (value) {
        setState(() {
          status = value!;
        });
      },
      items: statusOptions
          .map((option) => DropdownMenuItem(
                value: option,
                child: Text(option, style: GoogleFonts.poppins(fontSize: 11)),
              ))
          .toList(),
    );
  }
}
