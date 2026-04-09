import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'dart:async';
import 'package:Neevika/screens/Drinks/drinksMenuIngredients/DrinksAddMenuIngredientsScreen.dart';
import 'package:Neevika/screens/Drinks/drinksMenuIngredients/DrinksEditMenuIngredientsScreen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';

class DrinksMenuIngredientsScreen extends StatefulWidget {
  const DrinksMenuIngredientsScreen({super.key});

  @override
  State<DrinksMenuIngredientsScreen> createState() => _DrinksMenuIngredientsScreenState();
}

class _DrinksMenuIngredientsScreenState extends State<DrinksMenuIngredientsScreen> {
  final Color primaryRed = const Color(0xFFDC3C29);
  final Color lightGray = const Color(0xFFF4F4F4);

  final TextEditingController _searchController = TextEditingController();
  List<dynamic> menuIngredients = [];
  bool isLoading = true;
  bool hasErrorOccurred = false;

  List<Map<String, dynamic>> groupByMenu(List<dynamic> rawList) {
  final Map<int, Map<String, dynamic>> grouped = {};

  for (var item in rawList) {
    final int menuId = item['MenuId'];
    final String menuName = item['menu']['name'];
    final ingredient = {
      'id':item['id'],
      'name': item['inventory']['itemName'],
      'quantity': item['quantityRequired'],
      'unit': item['unit'],
    };

    if (!grouped.containsKey(menuId)) {
      grouped[menuId] = {
        'menuId': menuId,
        'menuName': menuName,
        'ingredients': [ingredient],
      };
    } else {
      grouped[menuId]!['ingredients'].add(ingredient);
    }
  }

  return grouped.values.toList();
}

  @override
  void initState() {
    super.initState();
    fetchMenuIngredients();
  }

  Future<void> fetchMenuIngredients() async {
    try {
      final response = await http
          .get(Uri.parse('${dotenv.env['API_URL']}/drinks-menu-ingredients/'))
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final rawData = json.decode(response.body);
        print(rawData);
        setState(() {
          menuIngredients = groupByMenu(rawData);
          isLoading = false;
          hasErrorOccurred = false;
        });

      } else {
        await Future.delayed(const Duration(seconds: 4));
        setState(() {
          isLoading = false;
          hasErrorOccurred = true;
        });
      }
    } catch (e) {
      await Future.delayed(const Duration(seconds: 4));
      setState(() {
        isLoading = false;
        hasErrorOccurred = true;
      });
      print('Error fetching menu ingredients: $e');
    }
  }




Future<void> _downloadExcel() async {
  final url = Uri.parse('${dotenv.env['API_URL']}/drinks-menu-ingredients/export-excel');
  setState(() => isLoading = true);

  try {
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = androidInfo.version.sdkInt;

    // Only request storage permission for SDK <= 32
    bool hasPermission = true;
    if (sdkInt <= 32) {
      final status = await Permission.storage.status;
      if (!status.isGranted) {
        final result = await Permission.storage.request();
        hasPermission = result.isGranted;
      }
    }

    if (!hasPermission) {
      throw Exception('Storage permission not granted');
    }

    final response = await http.get(url);
    if (response.statusCode == 200) {
      final bytes = response.bodyBytes;

      // Save to app-specific directory (compliant with scoped storage)
      final dir = await getExternalStorageDirectory();
      final filePath = '${dir!.path}/drinks_menu_ingredients.xlsx';
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Downloaded to: $filePath")),
      );

      OpenFile.open(filePath);
    } else {
      throw Exception('Failed to download. Status: ${response.statusCode}');
    }
  } catch (e) {
    print("Error: $e");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Download failed: $e")),
    );
  } finally {
    setState(() => isLoading = false);
  }
}

Future<void> _uploadExcel() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
    withData: true, // safer on Android 13+
  );
  if (result == null) return;

  final fileBytes = result.files.single.bytes!;
  final fileName = result.files.single.name;
  final uri = Uri.parse('${dotenv.env['API_URL']}/drinks-menu-ingredients/bulk-upload');

  final request = http.MultipartRequest('POST', uri);
  request.files.add(http.MultipartFile.fromBytes('file', fileBytes, filename: fileName));

  setState(() => isLoading = true);
  try {
    final streamed = await request.send();
    final respStr = await streamed.stream.bytesToString();
    if (streamed.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload success!')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $respStr')),
      );
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Upload error: $e')),
    );
  } finally {
    setState(() => isLoading = false);
  }
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
              'Drinks Menu Ingredient',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Manage restaurant drinks and its ingredients',
              style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey),
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
          :  hasErrorOccurred
  ? Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            LucideIcons.alertTriangle,
            size: 60,
            color: Color(0xFFEF4444), // Tailwind red-500
          ),
          const SizedBox(height: 16),
          Text(
            "Something went wrong",
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1F2937), // Tailwind gray-800
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Please check your connection or try again.",
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                isLoading = true;
                hasErrorOccurred = false;
              });
              fetchMenuIngredients(); // Retry fetch
            },
            icon: const Icon(
              LucideIcons.refreshCw,
              size: 20,
              color: Colors.white,
            ),
            label: Text(
              "Retry",
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB), // Tailwind blue-600
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    )
              : Column(
                    children: [
                      const SizedBox(height: 20),
                      SizedBox(
                        width: MediaQuery.of(context).size.width * 0.9,
                        height: MediaQuery.of(context).size.width * 0.116,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.add),
                          label: Text("Add Ingredient", 
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                            ),),
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
                                builder: (_) => AddMenuItemIngredientsScreen(),
                              ),
                            );

                            if (result == true) {
                              fetchMenuIngredients();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content:
                                      Text('Ingredient added successfully!'),
                                  behavior: SnackBarBehavior.floating,
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: MediaQuery.of(context).size.width * 0.9,
                        height: MediaQuery.of(context).size.width * 0.116,
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: "Search Menu Item...",
                            hintStyle: GoogleFonts.poppins(fontSize: 13.5),
                            prefixIcon: const Icon(Icons.search, size: 18,),
                            filled: true,
                            fillColor: const Color(0xFFF8F5F2),
                            contentPadding: const EdgeInsets.all(14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade400),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Color(0xFFF37269),
                                width: 1,
                              ),
                            ),
                          ),
                          onChanged: (value) {
                            setState(() {});
                          },
                        ),
                      ),
                      const SizedBox(height: 24),
                      Expanded(
                        child: ListView.builder(
                          itemCount: menuIngredients.length,
                          itemBuilder: (context, index) {
                            final item = menuIngredients[index];
                            final name = item['menuName'];
                            final menuId = item['menuId'];
                            final ingredients = item['ingredients'];
                            // print(ingredients);

                            if (_searchController.text.isNotEmpty &&
                                !name.toLowerCase().contains(_searchController.text.toLowerCase())) {
                              return const SizedBox.shrink();
                            }

                            return Container(
                              // width: MediaQuery.of(context).size.width * 0.92,
                             
                              margin: const EdgeInsets.only(left:21 ,right:21, bottom: 10),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name ?? 'NA',
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Ingredients:',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  ...ingredients.map<Widget>((ing) => Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                                    child: Text(
                                      '${ing['name']} - ${ing['quantity']} ${ing['unit'] ?? "NA"}',
                                      style: GoogleFonts.poppins(fontSize: 12),
                                    ),
                                  )),
                                  const SizedBox(height: 12),
                                  // SizedBox(
                                  //   width: double.infinity,
                                  //   child: OutlinedButton.icon(
                                  //     onPressed: () async {
                                  //       final result = await Navigator.push(
                                  //         context,
                                  //         MaterialPageRoute(
                                  //           builder: (_) => EditMenuItemIngredientsScreen(
                                  //             menuItemId: menuId,
                                  //             menuItemName: name,
                                  //             existingIngredients: List<Map<String, dynamic>>.from(ingredients),
                                  //           ),
                                  //         ),
                                  //       );

                                  //       // If the result is true, refresh the data
                                  //       if (result == true) {
                                  //         fetchMenuIngredients();
                                  //         ScaffoldMessenger.of(context).showSnackBar(
                                  //           const SnackBar(
                                  //             content: Text('Ingredients updated successfully!'),
                                  //             behavior: SnackBarBehavior.floating,
                                  //             duration: Duration(seconds: 2),
                                  //           ),
                                  //         );
                                  //       }
                                  //     },
                                  //     icon: const Icon(Icons.edit, size: 16),
                                  //     label: Text(
                                  //       'Edit Ingredients',
                                  //       style: GoogleFonts.poppins(
                                  //         fontSize: 11.5,
                                  //         fontWeight: FontWeight.w500,
                                  //       ),
                                  //     ),
                                  //     style: OutlinedButton.styleFrom(
                                  //       backgroundColor: Color(0xFFF8F5F2),
                                  //       foregroundColor: Colors.black,
                                  //       padding: const EdgeInsets.symmetric(vertical: 12),
                                  //       side: BorderSide(color: Colors.grey.shade300),
                                  //       shape: RoundedRectangleBorder(
                                  //         borderRadius: BorderRadius.circular(8),
                                  //       ),
                                  //     ),
                                  //   ),
                                  // ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 21.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _downloadExcel,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFF8F5F2),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    side: const BorderSide(
                                      color: Color.fromARGB(255, 204, 203, 203),
                                      width: 1.6,
                                    ),
                                  ),
                                  minimumSize: const Size.fromHeight(50),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.download_rounded, color: Colors.black),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Download Excel',
                                      style: GoogleFonts.poppins(
                                        color: Colors.black,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _uploadExcel,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFF8F5F2),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    side: const BorderSide(
                                      color: Color.fromARGB(255, 204, 203, 203),
                                      width: 1.0,
                                    ),
                                  ),
                                  minimumSize: const Size.fromHeight(50),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.upload_rounded, color: Colors.black),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Upload Excel',
                                      style: GoogleFonts.poppins(
                                        color: Colors.black,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
    );
  }
}