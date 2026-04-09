import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';

class EditExpensePage extends StatefulWidget {
  final Map<String, dynamic> expense;

  const EditExpensePage({super.key, required this.expense});

  @override
  State<EditExpensePage> createState() => _EditExpensePageState();
}

class _EditExpensePageState extends State<EditExpensePage> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _typeController;
  late TextEditingController _amountController;
  late TextEditingController _descriptionController;

  String? _paymentMethod;
  String? _paymentStatus;

  DateTime selectedDate = DateTime.now();
  File? _newImage;

  final String baseUrl = "${dotenv.env['API_URL']}/accounting/expense";

  final List<String> paymentMethods = [
    'Cash',
    'UPI',
    'Cheque',
    'Card',
    'Not Paid',
  ];

  final List<String> paymentStatuses = [
    'Paid',
    'Pending',
  ];

  @override
  void initState() {
    super.initState();
    final expense = widget.expense;
    _typeController = TextEditingController(text: expense['type']);
    _amountController = TextEditingController(text: expense['amount'].toString());
    _descriptionController = TextEditingController(text: expense['description'] ?? '');
    _paymentMethod = expense['payment_method'] ?? null;
    _paymentStatus = expense['payment_status'] ?? null;
    selectedDate = DateTime.parse(expense['date']);
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _newImage = File(picked.path));
    }
  }

  Future<void> _submitUpdate() async {
    if (!_formKey.currentState!.validate()) return;

    final uri = Uri.parse("$baseUrl/${widget.expense['id']}");
    final request = http.MultipartRequest('PUT', uri);

    request.fields['type'] = _typeController.text.trim();
    request.fields['amount'] = _amountController.text.trim();
    request.fields['description'] = _descriptionController.text.trim();
    request.fields['date'] = selectedDate.toIso8601String().split("T")[0];
    request.fields['payment_method'] = _paymentMethod ?? '';
    request.fields['payment_status'] = _paymentStatus ?? '';

    if (_newImage != null) {
      final stream = http.ByteStream(_newImage!.openRead());
      final length = await _newImage!.length();
      final multipartFile = http.MultipartFile(
        'receipt_image',
        stream,
        length,
        filename: _newImage!.path.split('/').last,
      );
      request.files.add(multipartFile);
    }

    try {
      final response = await request.send();
      final res = await http.Response.fromStream(response);

      if (res.statusCode == 200) {
        if (context.mounted) Navigator.pop(context, true);
      } else {
        print("Update failed: ${res.statusCode}, ${res.body}");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: ${res.statusCode}')),
        );
      }
    } catch (e) {
      print("Error updating: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating expense')),
      );
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
    final existingImage = widget.expense['receipt_image_path'];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFF89F3F),
        title: Text(
          "Edit Expense",
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 20, color: Colors.white),
        ),
        elevation: 0,
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

              // Payment Method Dropdown
              _buildDropdown(
                label: "Payment Method",
                value: _paymentMethod,
                items: paymentMethods,
                onChanged: (val) => setState(() => _paymentMethod = val),
              ),

              // Payment Status Dropdown
              _buildDropdown(
                label: "Payment Status",
                value: _paymentStatus,
                items: paymentStatuses,
                onChanged: (val) => setState(() => _paymentStatus = val),
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  Text(
                    "Date: ${DateFormat('yyyy-MM-dd').format(selectedDate)}",
                    style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500, color: const Color(0xFF4A4A4A)),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.calendar_month, color: Color(0xFFF89F3F)),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: const ColorScheme.light(
                                primary: Color(0xFFF89F3F),
                                onPrimary: Colors.white,
                                onSurface: Colors.black,
                              ),
                              textButtonTheme: TextButtonThemeData(
                                style: TextButton.styleFrom(foregroundColor: const Color(0xFFF89F3F)),
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) setState(() => selectedDate = picked);
                    },
                  )
                ],
              ),

              const SizedBox(height: 12),

              GestureDetector(
  onTap: _pickImage,
  child: Container(
    height: 160,
    width: double.infinity,
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFFBDBDBD)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Stack(
      children: [
        // Show image if available
        if (_newImage != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(_newImage!, fit: BoxFit.cover, width: double.infinity, height: 160),
          )
        else if (existingImage != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              "${dotenv.env['API_URL']}$existingImage",
              fit: BoxFit.cover,
              width: double.infinity,
              height: 160,
              errorBuilder: (_, __, ___) => Center(
                child: Text(
                  "Failed to load image",
                  style: GoogleFonts.poppins(color: Colors.redAccent),
                ),
              ),
            ),
          ),
        
        // Always show the upload text in the center with semi-transparent background
        Center(
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              "Tap to upload image",
              style: GoogleFonts.poppins(color: Colors.white),
            ),
          ),
        ),
      ],
    ),
  ),
),


              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF89F3F),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _submitUpdate,
                  child: Text(
                    "Update Expense",
                    style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {TextInputType keyboardType = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        style: GoogleFonts.poppins(fontSize: 14, color: const Color(0xFF4A4A4A)),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.poppins(color: const Color(0xFF78726D)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFFF89F3F)), borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        validator: (val) => val == null || val.isEmpty ? 'Required' : null,
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.poppins(color: const Color(0xFF78726D)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFFF89F3F)), borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: value,
            icon: const Icon(Icons.arrow_drop_down, color: Color(0xFFF89F3F)),
            items: items
                .map((item) => DropdownMenuItem(
                      value: item,
                      child: Text(
                        item,
                        style: GoogleFonts.poppins(fontSize: 14, color: const Color(0xFF4A4A4A)),
                      ),
                    ))
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}
