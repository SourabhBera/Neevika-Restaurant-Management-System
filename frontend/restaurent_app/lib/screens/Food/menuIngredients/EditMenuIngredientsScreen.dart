import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
class EditMenuItemIngredientsScreen extends StatefulWidget {
  final String menuItemName;
  final int menuItemId;
  final int menuIngredientId;
  final List<Map<String, dynamic>> existingIngredients;

  const EditMenuItemIngredientsScreen({
    super.key,
    required this.menuItemName,
    required this.menuItemId,
    required this.menuIngredientId,
    required this.existingIngredients,
  });

  @override
  State<EditMenuItemIngredientsScreen> createState() =>
      _EditMenuItemIngredientsScreenState();
}

class _EditMenuItemIngredientsScreenState
    extends State<EditMenuItemIngredientsScreen> {
  List<dynamic> menuItems = [];
  List<dynamic> ingredientOptions = [];
  List<Map<String, dynamic>> ingredients = [];
  String? selectedMenuItem;
  

  final List<String> units = ['Gram (g)', 'Kilogram (Kg)', ];


@override
void initState() {
  super.initState();
  fetchMenuItems();
  fetchIngredients();

  ingredients = widget.existingIngredients.map((ingredient) {
    print('ing id -- ${ingredient['id'].toString()}');
    int menuIngredientId = ingredient['id'];
    return {
      'id': ingredient['id'].toString(),
      'ingredient': ingredient['name'], // ✅ changed from 'ingredientName'
      'quantity': ingredient['quantity'].toString(), // ✅ changed from 'quantityRequired'
      'unit': ingredient['unit'],
    };
  }).toList();

  print('\n\n--------->>  $ingredients \n\n');

  
  selectedMenuItem = widget.menuItemName;
}


  void addIngredient() {
  setState(() {
    ingredients.add({
      'ingredient': ingredientOptions.isNotEmpty
          ? ingredientOptions.first['itemName']
          : null,
      'quantity': '',
      'unit': units.first, // default to a known unit
    });
  });
}

  void removeIngredient(int index) {
    setState(() {
      ingredients.removeAt(index);
    });
  }

  void saveChanges() {
  submitEditedMenuIngredients(); // You already have this function
  Navigator.pop(context); // Optionally pop the screen after saving
}


Future<void> fetchMenuItems() async {
    try {
      final response = await http
          .get(Uri.parse('${dotenv.env['API_URL']}/menu/'))
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


  Future<void> submitEditedMenuIngredients() async {
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

      

      final response = await http.put(
        Uri.parse('${dotenv.env['API_URL']}/menu-ingredients/${ing['id']}'),
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
      backgroundColor: const Color(0xFFFCF9F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF9F6),
        title: Text(
          'Edit Menu Ingredients',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
        
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.all(20),
            width: 420,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Menu Item: ${widget.menuItemName}',
                  style: GoogleFonts.poppins(
                      fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Update the ingredients for this menu item.',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Ingredients *',
                        style:
                            GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                    // ElevatedButton.icon(
                    //   onPressed: addIngredient,
                    //   icon: const Icon(Icons.add, size: 16),
                    //   label: const Text('Add Ingredient'),
                    //   style: ElevatedButton.styleFrom(
                    //     elevation: 0,
                    //     backgroundColor: Colors.white,
                    //     foregroundColor: Colors.black,
                    //     side: BorderSide(color: Colors.grey.shade300),
                    //     shape: RoundedRectangleBorder(
                    //       borderRadius: BorderRadius.circular(8),
                    //     ),
                    //     padding: const EdgeInsets.symmetric(
                    //         horizontal: 12, vertical: 10),
                    //     textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                    //   ),
                    // ),
                  ],
                ),
                const SizedBox(height: 12),
                ...ingredients.asMap().entries.map((entry) {
                  print(entry.value);
                  int index = entry.key;
                  var ing = entry.value;
                  return Container(
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
                                    fontWeight: FontWeight.w500)),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.red),
                              onPressed: () => removeIngredient(index),
                            )
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('Ingredient',
                            style: GoogleFonts.poppins(fontSize: 14)),
                        const SizedBox(height: 6),
                       DropdownButtonFormField<String>(
  value: ingredientOptions.any((i) => i['itemName'] == ing['ingredient'])
      ? ing['ingredient'] as String
      : null,
  items: ingredientOptions
      .map<DropdownMenuItem<String>>((i) => DropdownMenuItem<String>(
            value: i['itemName'],
            child: Text(i['itemName']),
          ))
      .toList(),
  onChanged: (value) {
    setState(() {
      ing['ingredient'] = value;
    });
  },
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(
                                vertical: 14, horizontal: 12),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text('Quantity',
                            style: GoogleFonts.poppins(fontSize: 14)),
                        const SizedBox(height: 6),
                        TextFormField(
                          initialValue: ing['quantity'] != null ? ing['quantity'].toString() : '',
                          keyboardType: TextInputType.number,
                          onChanged: (val) => ing['quantity'] = val,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(
                                vertical: 14, horizontal: 12),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text('Unit', style: GoogleFonts.poppins(fontSize: 14)),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                        value: ing['unit'] != null && units.contains(ing['unit']) ? ing['unit'] : null,

                        items: units
                            .map((u) => DropdownMenuItem<String>(
                                  value: u,
                                  child: Text(u),
                                ))
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            ing['unit'] = value;
                          });
                        },
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(
                                vertical: 14, horizontal: 12),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: saveChanges,
                    icon: const Icon(Icons.save_alt),
                    label: Text('Save Ingredients',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w500)),
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
            ),
          ),
        ),
      ),
    );
  }
}
