import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:Neevika/screens/Food/ingredients/AddIngredientsScreen.dart';
import 'package:Neevika/screens/Food/ingredients/editIngredientScreen.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';


class IngredientScreen extends StatefulWidget {
  const IngredientScreen({super.key});

  @override
  State<IngredientScreen> createState() => _IngredientScreenState();
}

class _IngredientScreenState extends State<IngredientScreen> {
  final Color primaryRed = const Color(0xFFDC3C29);
  final Color lightGray = const Color(0xFFF6F6F7);
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> ingredients = [];
  List<dynamic> filteredIngredients = [];
  bool isLoading = true;
  bool hasErrorOccurred = false;

  Future<void> fetchIngredients() async {
    try {
      final response = await http
          .get(Uri.parse('${dotenv.env['API_URL']}/ingredients/'))
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        setState(() {
          ingredients = json.decode(response.body);
          filteredIngredients = ingredients;
          isLoading = false;
          hasErrorOccurred = false;
        });
      } else {
        setState(() {
          isLoading = false;
          hasErrorOccurred = true;
        });
      }
    } catch (e) {
      setState(() {
        isLoading = false;
        hasErrorOccurred = true;
      });
      print('Error fetching ingredients: $e');
    }
  }

  Future<void> deleteIngredient(int id) async {
  try {
    final response = await http.delete(
      Uri.parse('${dotenv.env['API_URL']}/ingredients/$id'),
    );

    if (response.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingredient deleted')),
      );
      await fetchIngredients();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete ingredient. Code: ${response.statusCode}')),
      );
    }
  } catch (e) {
    print('Delete error: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Error occurred while deleting.')),
    );
  }
}

  @override
  void initState() {
    super.initState();
    fetchIngredients();

    _searchController.addListener(() {
      final query = _searchController.text.toLowerCase();
      setState(() {
        filteredIngredients = ingredients.where((ingredient) {
          final name = (ingredient['itemName'] ?? '').toLowerCase();
          final desc = (ingredient['description'] ?? '').toLowerCase();
          return name.contains(query) || desc.contains(query);
        }).toList();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
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
             
              'Ingredients',
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Manage your restaurent ingredients',
              style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
      body: isLoading
              ? Center(
                child: LoadingAnimationWidget.staggeredDotsWave(
                  color: Colors.black,
                  size: 40,
                ),
              )
              : hasErrorOccurred
              ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.alertTriangle,
                      size: 60,
                      color: Color(0xFFEF4444),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "Something went wrong",
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Please check your connection or try again.",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          isLoading = true;
                          hasErrorOccurred = false;
                        });
                        fetchIngredients();
                      },
                      icon: const Icon(
                        LucideIcons.refreshCw,
                        size: 20,
                        color: Colors.white,
                      ),
                      label: Text(
                        "Retry",
                        style: GoogleFonts.poppins(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              )
              :  Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text("Add Ingredient"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryRed,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            textStyle:
                                GoogleFonts.poppins(fontWeight: FontWeight.w600),
                          ),
                          onPressed: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AddIngredientPage(),
                              ),
                            );
                            if (result != null) fetchIngredients();
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: "Search Ingredients...",
                          hintStyle: GoogleFonts.poppins(
                            fontSize: 14,
                            color: const Color(0xFF1C1917),
                          ),
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: const Color(0xFFF8F5F2),
                          contentPadding: const EdgeInsets.all(14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Color.fromARGB(255, 204, 203, 203),
                              width: 1.3,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Color.fromARGB(255, 204, 203, 203),
                              width: 1.3,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Color(0xFFE5E5E5),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Expanded(
                        child: filteredIngredients.isEmpty
                            ? Center(
                                child: Text(
                                  "No ingredients found.",
                                  style: GoogleFonts.poppins(
                                    color: Colors.grey[600],
                                    fontSize: 16,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                itemCount: filteredIngredients.length,
                                itemBuilder: (context, index) {
                                  final ingredient = filteredIngredients[index];
                                  return Container(
                                    width:
                                        MediaQuery.of(context).size.width * 0.9,
                                    margin: const EdgeInsets.only(bottom: 15),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      border: Border.all(
                                          color: const Color(0xFFE5E5E5)),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                          top: 4, bottom: 8),
                                      child: ListTile(
                                        title: Text(
                                          ingredient['itemName'] ?? 'No Name',
                                          style: GoogleFonts.poppins(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16,
                                          ),
                                        ),
                                        subtitle: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const SizedBox(height: 4),
                                            Text(
                                              ingredient['description'] ??
                                                  'No Description',
                                              style: GoogleFonts.poppins(
                                                fontSize: 13,
                                                color: Colors.grey[800],
                                              ),
                                            ),
                                          ],
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.edit,
                                                  size: 20),
                                              onPressed: () async {
                                                final result = await Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) => EditIngredientPage(
                                                      initialId: ingredient['id'],
                                                      initialName: ingredient['itemName'],
                                                      initialDescription: ingredient['description'],
                                                    ),
                                                  ),
                                                );
                                                if (result != null) {
                                                  fetchIngredients();
                                                }
                                              }
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.delete_outline,
                                                  size: 20),
                                              color: Colors.red[400],
                                              onPressed: () async {
                                                  final confirm = await showDialog<bool>(
                                                    context: context,
                                                    builder: (context) => AlertDialog(
                                                      title: const Text("Confirm Deletion"),
                                                      content: const Text("Are you sure you want to delete this ingredient?"),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () => Navigator.pop(context, false),
                                                          child: const Text("Cancel"),
                                                        ),
                                                        TextButton(
                                                          onPressed: () => Navigator.pop(context, true),
                                                          child: const Text("Delete", style: TextStyle(color: Colors.red)),
                                                        ),
                                                      ],
                                                    ),
                                                  );

                                                  if (confirm == true) {
                                                    await deleteIngredient(ingredient['id']);
                                                  }
                                                },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
    );
  }
}