

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

class AddMenuItemIngredientsScreen extends StatefulWidget {
  const AddMenuItemIngredientsScreen({super.key});

  @override
  _AddMenuItemIngredientsScreenState createState() =>
      _AddMenuItemIngredientsScreenState();
}

class _AddMenuItemIngredientsScreenState
    extends State<AddMenuItemIngredientsScreen> {
  String? selectedMenuItem;
  List<dynamic> menuItems = [];
  List<dynamic> drinksMenuItems = [];
  List<dynamic> ingredientOptions = [];
  List<Map<String, dynamic>> ingredients = [];
  final List<String> units = ['Piece', 'Gram (g)', 'Kilogram (Kg)', 'Mililiters (ml)', 'Liters (L)', 'Cup', 'Tablespoon', 'Teaspoon', 'Slices'];


  @override
  void initState() {
    super.initState();
    fetchMenuItems();
    fetchIngredients();
  }

void addIngredientField() {
  setState(() {
    ingredients.add({
      'ingredient': ingredientOptions.isNotEmpty ? ingredientOptions.first['itemName'] : null,
      'quantity': '',
      'unit': units.first,
    });
  });
}
  

  void saveIngredients() async {
  await submitMenuIngredients();
  Navigator.pop(context, true);
}

  void cancel() {
    Navigator.pop(context);
  }

  void removeIngredient(int index) {
    setState(() {
      ingredients.removeAt(index);
    });
  }

  Future<void> fetchMenuItems() async {
    try {  
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwtToken');

      if (token == null) {
        print('No token found. User might not be logged in.');
        setState(() {
          
        });
        return;
      }

      final response = await http
          .get(Uri.parse('${dotenv.env['API_URL']}/menu/'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },)
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        setState(() {
          menuItems = json.decode(response.body);
          
        });
      } else {
        await Future.delayed(const Duration(seconds: 4));
        setState(() {
          
        });
      }
    } catch (e) {
      await Future.delayed(const Duration(seconds: 4));
      setState(() {
        
      });
      print('Error fetching menu: $e');
    }
  }

  Future<void> fetchIngredients() async {
    try {
      final response = await http
          .get(Uri.parse('${dotenv.env['API_URL']}/inventory/'))
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        setState(() {
          ingredientOptions = json.decode(response.body);
          
        });
      } else {
        await Future.delayed(const Duration(seconds: 4));
        setState(() {
          
        });
      }
    } catch (e) {
      await Future.delayed(const Duration(seconds: 4));
      setState(() {
        
      });
      print('Error fetching menu: $e');
    }
  }


  Future<void> submitMenuIngredients() async {
  try {
    final selectedMenu = menuItems.firstWhere(
      (item) => item['name'] == selectedMenuItem,
      orElse: () => null,
    );

    if (selectedMenu == null) {
      print("Menu item not found.");
      return;
    }

    final menuId = selectedMenu['id'];

    for (var ing in ingredients) {
      final ingredientObj = ingredientOptions.firstWhere(
        (opt) => opt['itemName'] == ing['ingredient'],
        orElse: () => null,
      );

      if (ingredientObj == null || ing['quantity'] == null || ing['unit'] == null) {
        print("Missing ingredient info, skipping...");
        continue;
      }

      final payload = {
        "MenuId": menuId,
        "inventoryId": ingredientObj['id'],
        "quantityRequired": ing['quantity'],
        "unit": ing['unit'],
      };

      final response = await http.post(
        Uri.parse('${dotenv.env['API_URL']}/menu-ingredients/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      print(jsonEncode(payload));

      if (response.statusCode != 200 && response.statusCode != 201) {
        print("Failed to save ingredient ${ingredientObj['itemName']}: ${response.body}");
      }
    }

    print("All ingredients submitted.");
  } catch (e) {
    print("Error submitting ingredients: $e");
  }
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
          const SizedBox(height: 2),
          Text(
            'Add Menu Ingredients',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Add a ingredients to your menu items',
            style: GoogleFonts.poppins(fontSize: 11, color: Colors.black54),
          ),
          const SizedBox(height: 7),
        ],
      ),
    ),
      body: Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.86,
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.only(left:8, right:8, bottom: 50),
      decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Color(0xFFE5E7EB),
                width: 1.5,
              ),
            ),
            child: SizedBox(
              width: MediaQuery.of(context).size.width * 0.86,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Menu Item Ingredients',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Select menu item and assign ingredients to it.',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Menu Item *',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w500, fontSize: 12)),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: MediaQuery.of(context).size.width * 0.7,
                    child: DropdownButtonFormField<String>(
                      dropdownColor: const Color(0xFFF8F5F2),
                      value: selectedMenuItem,
                      isExpanded: true,
                      items: menuItems
                          .map<DropdownMenuItem<String>>(
                            (item) => DropdownMenuItem(
                              value: item['name'],
                              child: Container(
                                constraints: BoxConstraints(
                                  maxWidth: MediaQuery.of(context).size.width * 0.6,
                                ),
                                child: Text(
                                  item['name'],
                                  style: GoogleFonts.poppins(fontSize: 11.5),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      selectedItemBuilder: (context) {
                        return menuItems.map<Widget>((item) {
                          return Container(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.6,
                            ),
                            child: Text(
                              item['name'],
                              style: GoogleFonts.poppins(fontSize: 11.5),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          );
                        }).toList();
                      },
                      onChanged: (value) {
                        setState(() {
                          selectedMenuItem = value;
                        });
                      },
                      decoration: InputDecoration(
                        fillColor: const Color(0xFFF8F5F2),
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 12,
                        ),
                      ),
                    ),

                  ),

                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Ingredients *',
                          style:GoogleFonts.poppins(fontWeight: FontWeight.w500, fontSize: 12)),
                      Padding(
                        padding: const EdgeInsets.only(right: 4.0),
                        child: ElevatedButton.icon(
                          onPressed: addIngredientField,
                          icon: const Icon(Icons.add, size: 16),
                          label:  Text('Add Ingredient', style:
                                GoogleFonts.poppins(fontWeight: FontWeight.w500, fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  ...ingredients.asMap().entries.map((entry) {
                  int index = entry.key;
                  var ing = entry.value;
                              
                    return Column(
                      children: [
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Ingredient ${index + 1}',
                                      style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 13
                                          )),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 20,
                                        color: Colors.red),
                                    onPressed: () => removeIngredient(index),
                                  )
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text('Ingredient',
                                  style: GoogleFonts.poppins(fontSize: 12)),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<String>(
                                dropdownColor: Color(0xFFF8F5F2),
                                focusColor: Color(0xFFF8F5F2),
                                value: ing['ingredient'],
                                items: ingredientOptions
                                    .map<DropdownMenuItem<String>>((i) => DropdownMenuItem(
                                          value: i['itemName'],
                                          child: Text(i['itemName'], style:
                                GoogleFonts.poppins(fontWeight: FontWeight.w500, fontSize: 11.5)),
                                        ))
                                    .toList(),
                                onChanged: (value) {
                                  setState(() {
                                    ing['ingredient'] = value;
                                  });
                                },
                                decoration: InputDecoration(
                                  fillColor: Color(0xFFF8F5F2),
                                  filled: true,
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                  contentPadding: const EdgeInsets.symmetric(
                                      vertical: 14, horizontal: 12),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text('Quantity',
                                  style: GoogleFonts.poppins(fontSize: 12)),
                              const SizedBox(height: 6),
                              TextFormField(
                                initialValue: ing['quantity'],
                                keyboardType: TextInputType.number,
                                onChanged: (val) => ing['quantity'] = val,
                                style: GoogleFonts.poppins(fontSize: 11.5),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: Color(0xFFF8F5F2),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                  contentPadding: const EdgeInsets.symmetric(
                                      vertical: 14, horizontal: 12),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text('Unit', style: GoogleFonts.poppins(fontSize: 12)),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<String>(
                                dropdownColor: Color(0xFFF8F5F2),
                                focusColor: Color(0xFFF8F5F2),
                                value: ing['unit'],
                                items: units
                                    .map((u) =>
                                        DropdownMenuItem(value: u, child: Text(u, style:
                                GoogleFonts.poppins( fontSize: 11.5))))
                                    .toList(),
                                onChanged: (value) {
                                  setState(() {
                                    ing['unit'] = value!;
                                  });
                                },
                                decoration: InputDecoration(
                                  fillColor: Color(0xFFF8F5F2),
                                  filled: true,
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                  contentPadding: const EdgeInsets.symmetric(
                                      vertical: 14, horizontal: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20,)
                      ],
                    );
                  }),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0, right:8),
                        child: OutlinedButton(
                          onPressed: cancel,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text('Cancel',
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Padding(
                        padding: const EdgeInsets.only(right:10.0),
                        child: ElevatedButton.icon(
                          onPressed: saveIngredients,
                          icon: const Icon(Icons.save_alt),
                          label: Text('Save Ingredients',
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE94B27),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}