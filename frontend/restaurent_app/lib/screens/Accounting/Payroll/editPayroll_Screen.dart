import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class EditPayrollDialog extends StatefulWidget {
  final Map<String, dynamic> payrollData;
  final void Function(Map<String, dynamic> updatedData) onSave;

  const EditPayrollDialog({
    Key? key,
    required this.payrollData,
    required this.onSave,
  }) : super(key: key);

  @override
  State<EditPayrollDialog> createState() => _EditPayrollDialogState();
}

class _EditPayrollDialogState extends State<EditPayrollDialog> {
  late TextEditingController bonusController;
  late TextEditingController deductionsController;
  late TextEditingController notesController;

  double baseSalary = 0;
  double netSalary = 0;
  String selectedStatus = "Unpaid";

  final List<String> statusOptions = ["Paid", "Unpaid", "Pending"];
  bool isSaving = false;

  @override
  void initState() {
    super.initState();

    final data = widget.payrollData;

    baseSalary = _toDouble(data['base_salary']);
    bonusController = TextEditingController(text: _toString(data['bonus']));
    deductionsController = TextEditingController(text: _toString(data['deductions']));
    notesController = TextEditingController(text: data['notes']?.toString() ?? '');
    selectedStatus = data['payment_status'] ?? 'Unpaid';

    _recalculateNetSalary();
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  String _toString(dynamic value) {
    if (value == null) return '0';
    return value.toString();
  }

  void _recalculateNetSalary() {
    final bonus = _toDouble(bonusController.text);
    final deductions = _toDouble(deductionsController.text);
    setState(() {
      netSalary = baseSalary + bonus - deductions;
    });
  }

  Future<void> _submitDataToAPI(Map<String, dynamic> updatedData) async {
    setState(() => isSaving = true);

    final url = Uri.parse('${dotenv.env['API_URL']}/payroll/${updatedData["id"]}');

    try {
      final response = await http.put(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(updatedData),
      );

      if (response.statusCode == 200) {
        widget.onSave(updatedData);
        Navigator.pop(context);
      } else {
        throw Exception("Failed to update. Server responded with ${response.statusCode}");
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: ${e.toString()}")),
      );
    } finally {
      setState(() => isSaving = false);
    }
  }

  @override
  void dispose() {
    bonusController.dispose();
    deductionsController.dispose();
    notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text("Edit Payroll", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 20),

              _buildNumberField("Bonus (₹)", bonusController),
              const SizedBox(height: 14),

              _buildNumberField("Deductions (₹)", deductionsController),
              const SizedBox(height: 14),

              _buildDropdownStatus(),
              const SizedBox(height: 14),

              TextFormField(
                controller: notesController,
                maxLines: 3,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: InputDecoration(
                  labelText: "Notes",
                  labelStyle: GoogleFonts.poppins(),
                  filled: true,
                  fillColor: const Color(0xFFF8F5F2),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),

              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Net Salary: ₹${netSalary.toStringAsFixed(2)}",
                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.green[800]),
                  ),
                  ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () {
                            final updated = {
                              ...widget.payrollData,
                              'bonus': _toDouble(bonusController.text),
                              'deductions': _toDouble(deductionsController.text),
                              'net_salary': netSalary,
                              'notes': notesController.text.trim(),
                              'payment_status': selectedStatus,
                            };
                            _submitDataToAPI(updated);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: isSaving
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text("Save", style: GoogleFonts.poppins(color: Colors.white)),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNumberField(String label, TextEditingController controller) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: GoogleFonts.poppins(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.poppins(),
        filled: true,
        fillColor: const Color(0xFFF8F5F2),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onChanged: (_) => _recalculateNetSalary(),
    );
  }

  Widget _buildDropdownStatus() {
    return DropdownButtonFormField<String>(
      value: selectedStatus,
      items: statusOptions.map((status) {
        return DropdownMenuItem<String>(
          value: status,
          child: Text(status, style: GoogleFonts.poppins()),
        );
      }).toList(),
      decoration: InputDecoration(
        labelText: "Payment Status",
        labelStyle: GoogleFonts.poppins(),
        filled: true,
        fillColor: const Color(0xFFF8F5F2),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onChanged: (value) {
        if (value != null) {
          setState(() => selectedStatus = value);
        }
      },
    );
  }
}
