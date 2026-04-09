// DrinksEditMenuScreen.dart
//
// NOTE: The DrinksMenu model does NOT have a 'veg' field.
// The dish type dropdown is kept in the UI for future use but the value
// is NOT sent to the backend (sending it would cause no harm but is meaningless).
// To fully enable veg/non-veg: add `veg: DataTypes.BOOLEAN` to the model + migration.

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class UpdateDrinksMenuPage extends StatefulWidget {
  final int id;
  final String name;
  final String price;
  final int categoryId;
  final String description;
  final bool veg;
  final bool isOffer;
  final bool isUrgent;
  final String offerPrice;
  final String waiterCommission;
  final String commissionType;
  final String? userRole;
  final bool OutOfStock;

  const UpdateDrinksMenuPage({
    super.key,
    required this.id,
    required this.name,
    required this.price,
    required this.categoryId,
    required this.description,
    required this.veg,
    required this.isOffer,
    required this.commissionType,
    required this.offerPrice,
    required this.waiterCommission,
    this.userRole,
    required this.isUrgent,
    required this.OutOfStock,
  });

  @override
  _UpdateDrinksMenuPageState createState() => _UpdateDrinksMenuPageState();
}

class _UpdateDrinksMenuPageState extends State<UpdateDrinksMenuPage> {
  late TextEditingController _nameController;
  late TextEditingController _priceController;
  late TextEditingController _descriptionController;
  late TextEditingController _waiterCommissionController;
  late TextEditingController _offerPriceController;

  String? _selectedCommissionType = 'flat';

  int? _selectedCategoryId;
  List<Map<String, dynamic>> _categories = [];
  bool isOffer = false;
  bool isUrgentSale = false;
  bool isOutOfStock = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.name);
    _priceController = TextEditingController(text: widget.price);
    _descriptionController = TextEditingController(text: widget.description);
    _waiterCommissionController =
        TextEditingController(text: widget.waiterCommission);
    _offerPriceController = TextEditingController(text: widget.offerPrice);
    _selectedCategoryId = widget.categoryId;
    isUrgentSale = widget.isUrgent;
    isOutOfStock = widget.OutOfStock;

    // ✅ Initialize from widget props (not hardcoded false)
    isOffer = widget.isOffer;
    _selectedCommissionType =
        widget.commissionType.isNotEmpty ? widget.commissionType : 'flat';

    fetchCategories();
  }

  bool get _canManageOffers =>
      widget.userRole == 'Admin' ||
      widget.userRole == 'Restaurant Manager' ||
      widget.userRole == 'Owner' ||
      widget.userRole == 'Acting Restaurant Manager';

  Widget _buildCommissionTypeDropdown() {
    return _styledDropdown<String>(
      value: _selectedCommissionType,
      items: ['flat', 'percentage'],
      onChanged: (v) => setState(() => _selectedCommissionType = v),
    );
  }

  Widget _styledDropdown<T>({
    required T? value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border.all(
            color: const Color.fromARGB(255, 235, 235, 229), width: 0.7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          items: items
              .map((i) => DropdownMenuItem<T>(
                  value: i, child: Text(i.toString())))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Future<void> submitMenuItem() async {
    final name = _nameController.text.trim();
    final priceText = _priceController.text.trim();
    final description = _descriptionController.text.trim();
    final waiterCommissionText = _waiterCommissionController.text.trim();
    final offerPriceText = _offerPriceController.text.trim();

    if (name.isEmpty ||
        priceText.isEmpty ||
        description.isEmpty ||
        _selectedCategoryId == null ||
        (waiterCommissionText.isEmpty && isOffer) ||
        (offerPriceText.isEmpty && isOffer)) {
      _showError('Please fill in all required fields.');
      return;
    }

    final double? price = double.tryParse(priceText);
    final double? waiterCommission = double.tryParse(waiterCommissionText);
    final double? offerPrice = double.tryParse(offerPriceText);

    if (price == null ||
        (waiterCommission == null && isOffer) ||
        (offerPrice == null && isOffer)) {
      _showError(
          'Enter valid numbers for price, commission, and offer price.');
      return;
    }

    final body = json.encode({
      'name': name,
      'price': price,
      'categoryId': _selectedCategoryId,
      'description': description,
      // 'veg' intentionally omitted — field does not exist in DrinksMenu model
      'isOffer': isOffer,
      'isUrgent': isUrgentSale,
      'isOutOfStock': isOutOfStock,
      'waiterCommission': isOffer ? waiterCommission : null,
      'offerPrice': isOffer ? offerPrice : null,
      'commissionType': isOffer ? _selectedCommissionType : null,
    });

    try {
      final response = await http.put(
        Uri.parse('${dotenv.env['API_URL']}/drinks-menu/${widget.id}'),
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Menu item updated successfully!'),
              backgroundColor: Colors.green),
        );
        // ✅ Return structured patch for optimistic update in parent screen
        Navigator.pop(context, {
          'id': widget.id,
          'name': name,
          'price': price,
          'categoryId': _selectedCategoryId,
          'description': description,
          'isOffer': isOffer,
          'isUrgent': isUrgentSale,
          'outOfStock': isOutOfStock,
          'waiterCommission': isOffer ? waiterCommission.toString() : '0',
          'offerPrice': isOffer ? offerPrice.toString() : '0',
          'commissionType': isOffer ? _selectedCommissionType : 'flat',
        });
      } else {
        _showError('Failed to update menu item.');
      }
    } catch (e) {
      print('Error updating menu item: $e');
      _showError('Something went wrong.');
    }
  }

  Future<void> deleteMenuItem() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Item',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text(
            'Are you sure you want to delete "${widget.name}"? This cannot be undone.',
            style: GoogleFonts.poppins(fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD95326)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await http.delete(
        Uri.parse('${dotenv.env['API_URL']}/drinks-menu/${widget.id}'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200 ||
          response.statusCode == 201 ||
          response.statusCode == 204) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Menu item deleted successfully!'),
              backgroundColor: Color.fromARGB(255, 210, 68, 68)),
        );
        // ✅ Return structured delete signal for optimistic delete in parent
        Navigator.pop(context, {'id': widget.id, 'deleted': true});
      } else {
        _showError('Failed to delete menu item.');
      }
    } catch (e) {
      print('Error deleting menu item: $e');
      _showError('Something went wrong.');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red));
  }

  Future<void> fetchCategories() async {
    try {
      final response = await http
          .get(Uri.parse('${dotenv.env['API_URL']}/drinks-categories/'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _categories =
              data.map((e) => {'id': e['id'], 'name': e['name']}).toList();
          if (!_categories.any((cat) => cat['id'] == _selectedCategoryId)) {
            _selectedCategoryId =
                _categories.isNotEmpty ? _categories.first['id'] : null;
          }
        });
      }
    } catch (e) {
      print('Error fetching categories: $e');
    }
  }

  Widget _buildLabel(String text, {double fontSize = 13}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: fontSize,
              color: const Color(0xFF1C1917))),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    String hint = '',
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
              color: Color.fromARGB(255, 235, 235, 229), width: 0.7),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
              color: Color.fromARGB(255, 235, 235, 229), width: 0.7),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
              color: Color.fromARGB(255, 235, 235, 229), width: 0.7),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
    );
  }

  Widget _buildCategoryDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border.all(
            color: const Color.fromARGB(255, 235, 235, 229), width: 0.7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _selectedCategoryId,
          isExpanded: true,
          items: _categories
              .map<DropdownMenuItem<int>>((cat) => DropdownMenuItem<int>(
                  value: cat['id'], child: Text(cat['name'])))
              .toList(),
          onChanged: (val) => setState(() => _selectedCategoryId = val!),
        ),
      ),
    );
  }

  Widget _buildFeatureToggle({
    required String text,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Text(text,
            style: GoogleFonts.poppins(
                fontSize: 13, fontWeight: FontWeight.w600)),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBFAF8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F5F2),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Update Menu',
                style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1C1917))),
            const SizedBox(height: 5),
            Text('Update restaurant menu items',
                style: GoogleFonts.poppins(
                    fontSize: 14, color: const Color(0xFF78726D))),
          ],
        ),
      ),
      body: _categories.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 10),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color.fromARGB(255, 134, 129, 124),
                        width: 0.7),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('Update Menu Item', fontSize: 20),
                      const SizedBox(height: 18),

                      _buildLabel('Name'),
                      _buildTextField(
                          controller: _nameController,
                          hint: 'Enter item name'),
                      const SizedBox(height: 18),

                      _buildLabel('Category'),
                      _buildCategoryDropdown(),
                      const SizedBox(height: 18),

                      _buildLabel('Price'),
                      _buildTextField(
                          controller: _priceController,
                          hint: 'Enter price',
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true)),
                      const SizedBox(height: 18),

                      // Urgent Sale — admin/manager only
                      if (_canManageOffers)
                        _buildFeatureToggle(
                          text: 'Urgent Sale',
                          value: isUrgentSale,
                          onChanged: (val) =>
                              setState(() => isUrgentSale = val),
                        ),

                      _buildFeatureToggle(
                        text: 'Out of Stock',
                        value: isOutOfStock,
                        onChanged: (val) =>
                            setState(() => isOutOfStock = val),
                      ),

                      // Enable Offer — admin/manager only
                      if (_canManageOffers)
                        _buildFeatureToggle(
                          text: 'Enable Offer',
                          value: isOffer,
                          onChanged: (val) => setState(() => isOffer = val),
                        ),

                      // ✅ Correct condition: both isOffer AND canManageOffers
                      if (isOffer && _canManageOffers) ...[
                        const SizedBox(height: 18),
                        _buildLabel('Commission Type'),
                        _buildCommissionTypeDropdown(),
                        const SizedBox(height: 18),
                        _buildLabel('Waiter Commission'),
                        _buildTextField(
                            controller: _waiterCommissionController,
                            hint: 'Enter waiter commission',
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true)),
                        const SizedBox(height: 18),
                        _buildLabel('Offer New Price'),
                        _buildTextField(
                            controller: _offerPriceController,
                            hint: 'Enter offer price',
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true)),
                      ],

                      const SizedBox(height: 35),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: submitMenuItem,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(LucideIcons.arrowUpFromLine,
                                    color: Colors.white, size: 20),
                                const SizedBox(width: 8),
                                Text('Update Item',
                                    style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: 16)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 15),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: deleteMenuItem,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD95326),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(LucideIcons.trash2,
                                    color: Colors.white, size: 20),
                                const SizedBox(width: 8),
                                Text('Delete Item',
                                    style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: 16)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}