import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:Neevika/screens/Food/menu/AddCategoryScreen.dart';

class AddDrinksMenuPage extends StatefulWidget {
  const AddDrinksMenuPage({super.key});

  @override
  _AddDrinksMenuPageState createState() => _AddDrinksMenuPageState();
}

class _AddDrinksMenuPageState extends State<AddDrinksMenuPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController(
    text: '0.00',
  );
  final TextEditingController _descriptionController = TextEditingController();

  int? _selectedCategoryId;
  List<Map<String, dynamic>> _categories = [];
  String? _selectedDishType = 'veg'; 

  @override
  void initState() {
    super.initState();
    fetchCategories();
  }

  Future<void> fetchCategories() async {
    try {
      final response = await http.get(
        Uri.parse('${dotenv.env['API_URL']}/drinks-categories/'),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _categories =
              data.map((e) => {'id': e['id'], 'name': e['name']}).toList();

          // Ensure selected ID is still valid (use first if not found)
          if (!_categories.any((cat) => cat['id'] == _selectedCategoryId)) {
            _selectedCategoryId =
                _categories.isNotEmpty ? _categories.first['id'] : null;
          }
        });
      } else {
        print('Failed to load categories');
      }
    } catch (e) {
      print('Error fetching categories: $e');
    }
  }

  Widget _buildLabel(String text, {double fontSize = 16}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.bold,
          fontSize: fontSize,
          color: Colors.black,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    String hint = '',
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: Color.fromARGB(255, 235, 235, 229),
            width: 0.7,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: Color.fromARGB(255, 235, 235, 229),
            width: 0.7,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: Color.fromARGB(255, 235, 235, 229),
            width: 0.7,
          ),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
    );
  }

  Widget _buildCategoryDropdown() {
  return Container(
    padding: EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: Colors.grey[100],
      border: Border.all(
        color: Color.fromARGB(255, 235, 235, 229),
        width: 0.7,
      ),
      borderRadius: BorderRadius.circular(10),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        value: _selectedCategoryId,
        isExpanded: true,
        items: _categories.map((category) {
          return DropdownMenuItem<int>(
            value: category['id'],
            child: Text(category['name']),
          );
        }).toList(),
        onChanged: (val) {
          setState(() {
            _selectedCategoryId = val;
          });
        },
      ),
    ),
  );
}

Future<void> submitMenuItem() async {
  final String name = _nameController.text.trim();
  final String priceText = _priceController.text.trim();
  final String description = _descriptionController.text.trim();

  if (name.isEmpty || priceText.isEmpty || description.isEmpty || _selectedCategoryId == null || _selectedDishType == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Please fill in all required fields.'),
        backgroundColor: Colors.red,
      ),
    );
    return;
  }

  final double? price = double.tryParse(priceText);
  if (price == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Enter a valid price.'),
        backgroundColor: Colors.red,
      ),
    );
    return;
  }

  final bool isVeg = _selectedDishType == 'veg';

  final body = json.encode({
    'name': name,
    'price': price,
    'drinksCategoryId': _selectedCategoryId,
    'description': description,
    'veg': isVeg, // ✅ Dynamically set
  });

  try {
    final response = await http.post(
      Uri.parse('${dotenv.env['API_URL']}/drinks-menu/addItem'),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Menu item added successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
      Navigator.pop(context, true);
    } else {
      print('Failed to add menu item. Status code: ${response.statusCode}');
      print('Response body: $body');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add menu item: ${response.body}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  } catch (e) {
    print('Error adding menu item: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Something went wrong.'),
        backgroundColor: Colors.red,
      ),
    );
  }
}


Widget _buildDishTypeDropdown() {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: Colors.grey[100],
      border: Border.all(color: Color.fromARGB(255, 235, 235, 229), width: 0.7),
      borderRadius: BorderRadius.circular(10),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _selectedDishType,
        isExpanded: true,
        items: ['veg', 'non-veg'].map((type) {
          return DropdownMenuItem<String>(
            value: type,
            child: Text(type),
          );
        }).toList(),
        onChanged: (value) {
          setState(() {
            _selectedDishType = value;
          });
        },
      ),
    ),
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
            Text(
              'Add Menu',
              style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1C1917),
              ),
            ),
            SizedBox(height: 5),
            Text(
              'Add new menu items to restaurent',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Color(0xFF78726D),
              ),
            ),
          ],
        ),

      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Color.fromARGB(255, 134, 129, 124), width: 0.7),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLabel('Menu Item Details', fontSize: 20),
                const SizedBox(height: 18),

                _buildLabel('Name'),
                _buildTextField(
                  controller: _nameController,
                  hint: 'Enter item name',
                ),

                const SizedBox(height: 18),
                _buildLabel('Price'),
                _buildTextField(
                  controller: _priceController,
                  hint: 'Enter price',
                ),

                const SizedBox(height: 18),
                _buildLabel('Dish Type'),
                _buildDishTypeDropdown(),

                const SizedBox(height: 18),
                _buildLabel('Category'),
                _buildCategoryDropdown(),

                const SizedBox(height: 18),
                _buildLabel('Description'),
                _buildTextField(
                  controller: _descriptionController,
                  hint: 'Add description here...',
                ),

                const SizedBox(height: 35),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: submitMenuItem,

                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    LucideIcons.plus, // Pick your icon here
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Add Item',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                  ),
                ),
                const SizedBox(height: 35),
                
              ],
            ),
            
          ),
        ),
      ),
    );
  }
}
