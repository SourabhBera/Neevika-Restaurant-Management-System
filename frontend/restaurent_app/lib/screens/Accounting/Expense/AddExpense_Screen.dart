import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AddExpensePage extends StatefulWidget {
  const AddExpensePage({super.key});

  @override
  State<AddExpensePage> createState() => _AddExpensePageState();
}

class _AddExpensePageState extends State<AddExpensePage> {
  final _formKey = GlobalKey<FormState>();
  final _typeController = TextEditingController();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();

  String? _selectedPaymentMethod;
  String? _selectedPaymentStatus;

  DateTime selectedDate = DateTime.now();
  File? _image;

  final String baseUrl = "${dotenv.env['API_URL']}/accounting/expense";

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _image = File(picked.path);
      });
    }
  }

  Future<void> _submitCreate() async {
    if (!_formKey.currentState!.validate()) return;

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwtToken');

    if (token == null) {
      print('No token found. User might not be logged in.');
      return;
    }

    final decodedToken = JwtDecoder.decode(token);
    final userId = decodedToken['id'];
    var userRole = decodedToken['role'];

    final uri = Uri.parse(baseUrl);
    final request = http.MultipartRequest('POST', uri);

    request.fields['type'] = _typeController.text;
    request.fields['amount'] = _amountController.text;
    request.fields['description'] = _descriptionController.text;
    request.fields['date'] = selectedDate.toIso8601String().split("T")[0];
    request.fields['payment_method'] = _selectedPaymentMethod ?? '';
    request.fields['payment_status'] = _selectedPaymentStatus ?? '';
    request.fields['user_id'] = userId.toString();

    if (_image != null) {
      final stream = http.ByteStream(_image!.openRead());
      final length = await _image!.length();
      final multipartFile = http.MultipartFile(
        'receipt_image',
        stream,
        length,
        filename: _image!.path.split('/').last,
      );
      request.files.add(multipartFile);
    }

    try {
      final response = await request.send();
      final res = await http.Response.fromStream(response);

      if (res.statusCode == 201) {
        if (context.mounted) Navigator.pop(context, true);
      } else {
        print("Create failed: ${res.statusCode}, ${res.body}");
      }
    } catch (e) {
      print("Error creating: $e");
    }
  }

  @override
  void dispose() {
    _typeController.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Add Expense", style: GoogleFonts.poppins()),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _buildTextField("Type", _typeController),
              _buildTextField("Amount", _amountController, keyboardType: TextInputType.number),
              _buildTextField("Description", _descriptionController),
              _buildDropdown(
                label: "Payment Method",
                value: _selectedPaymentMethod,
                options: ['Cash', 'UPI', 'Cheque', 'Card', 'Not Paid'],
                onChanged: (val) => setState(() => _selectedPaymentMethod = val),
              ),
              _buildDropdown(
                label: "Payment Status",
                value: _selectedPaymentStatus,
                options: ['Paid', 'Pending'],
                onChanged: (val) => setState(() => _selectedPaymentStatus = val),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    "Date: ${DateFormat('yyyy-MM-dd').format(selectedDate)}",
                    style: GoogleFonts.poppins(fontSize: 14),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.calendar_month),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setState(() => selectedDate = picked);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  height: 160,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _image != null
                      ? Image.file(_image!, fit: BoxFit.cover)
                      : Center(
                          child: Text(
                            "Tap to upload receipt",
                            style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: _submitCreate,
                  child: Text("Add Expense", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller,
      {TextInputType keyboardType = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        style: GoogleFonts.poppins(),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.poppins(),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        validator: (val) => val == null || val.isEmpty ? 'Required' : null,
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> options,
    required void Function(String?) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DropdownButtonFormField<String>(
        value: options.contains(value) ? value : null,
        items: options
            .map((option) => DropdownMenuItem(
                  value: option,
                  child: Text(option, style: GoogleFonts.poppins(fontSize: 14)),
                ))
            .toList(),
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.poppins(),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        validator: (val) => val == null || val.isEmpty ? 'Required' : null,
      ),
    );
  }
}
