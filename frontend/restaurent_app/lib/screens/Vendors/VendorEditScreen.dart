import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
class EditVendorScreen extends StatefulWidget {
  final dynamic vendor;
  const EditVendorScreen({super.key, required this.vendor});

  @override
  _EditVendorScreenState createState() => _EditVendorScreenState();
}

class _EditVendorScreenState extends State<EditVendorScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController vendorNameController;
  late TextEditingController businessTypeController;
  late TextEditingController contactPersonController;
  late TextEditingController emailController;
  late TextEditingController phoneController;
  late TextEditingController addressController;
  late String status;
  final List<String> statusOptions = ['Active', 'Inactive'];

  void updateVendor() async {
    final String apiUrl ='${dotenv.env['API_URL']}/vendor/${widget.vendor['id']}';

    final Map<String, dynamic> updatedData = {
      'name': vendorNameController.text,
      'business_type': businessTypeController.text,
      'contact_person': contactPersonController.text,
      'email': emailController.text,
      'phone': phoneController.text,
      // 'address': addressController.text,
      'status': status.toLowerCase(), // assuming backend expects lowercase
      'userId': 1,
    };

    try {
      final response = await http.put(
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }


Future<void> deleteVendor() async {
  final response = await http.delete(
    Uri.parse('${dotenv.env['API_URL']}/vendor/${widget.vendor['id']}'),
    headers: {'Content-Type': 'application/json'},
  );

  if (response.statusCode == 200) {
    // Success - optionally show a message or update UI
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Vendor deleted successfully')),
    );
    Navigator.pop(context);
  } else {
    // Handle error
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to delete vendor: ${response.body}')),
    );
  }
}
  @override
  void initState() {
    super.initState();
    vendorNameController = TextEditingController(text: widget.vendor['name']);
    businessTypeController = TextEditingController(
      text: widget.vendor['business_type'],
    );
    contactPersonController = TextEditingController(
      text: widget.vendor['contact_person'],
    );
    emailController = TextEditingController(text: widget.vendor['email']);
    phoneController = TextEditingController(text: widget.vendor['phone']);
    addressController = TextEditingController(
      text: widget.vendor['address'] ?? '',
    );
    String rawStatus = widget.vendor['status'] ?? 'Active';
    status = rawStatus[0].toUpperCase() + rawStatus.substring(1).toLowerCase();
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
              'Edit Vendor',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Update vendor information',
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
              border: Border.all(color: Color(0xFFE5E7EB), width: 1.5),
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Edit Vendor Details',
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1C1917),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Update the information for Fresh Farms Produce',
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildLabel('Vendor Name *'),
                  _buildTextField(vendorNameController),
                  _buildLabel('Business Type'),
                  _buildTextField(businessTypeController),
                  _buildLabel('Contact Person'),
                  _buildTextField(contactPersonController),
                  _buildLabel('Email Address'),
                  _buildTextField(emailController),
                  _buildLabel('Phone Number'),
                  _buildTextField(phoneController),
                  _buildLabel('Status'),
                  _buildDropdown(),
                  _buildLabel('Address'),
                  _buildTextField(addressController, maxLines: 3),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 150,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  title: const Text('Confirm Delete'),
                                  content: const Text(
                                    'Are you sure you want to delete this vendor?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () {
                                        Navigator.of(
                                          context,
                                        ).pop(); // Close the dialog
                                      },
                                      child: const Text('Cancel'),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFFDC2626,
                                        ),
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () async {
                                        Navigator.of(
                                          context,
                                        ).pop(); // Close the dialog

                                        // Call the delete function
                                        await deleteVendor();
                                      },
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                          icon: const Icon(Icons.delete, size: 16),
                          label: Text(
                            'Delete Vendor',
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

                      const SizedBox(width: 20),
                      SizedBox(
                        width: 155,
                        child: ElevatedButton.icon(
                          onPressed: updateVendor,
                          icon: const Icon(Icons.save_alt, size: 16),
                          label: Text(
                            'Update Vendor',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
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
                  const SizedBox(height: 15),
                  Center(
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width * 0.9,
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

  Widget _buildTextField(TextEditingController controller, {int maxLines = 1}) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      style: GoogleFonts.poppins(fontSize: 11),
      decoration: InputDecoration(

        filled: true,
        fillColor: const Color(0xFFF9F9F9),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
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
      items:
          statusOptions
              .map(
                (option) => DropdownMenuItem(
                  value: option,
                  child: Text(option, style: GoogleFonts.poppins(fontSize: 11)),
                ),
              )
              .toList(),
    );
  }
}
