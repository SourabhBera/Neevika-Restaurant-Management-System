// DrinksMenuScreen.dart
//
// NOTE ON 'veg' FIELD:
// The DrinksMenu model does NOT have a 'veg' or 'stockAvailable' column.
// As a result:
//   - All drinks items default to veg=true (veg icon shown, Veg filter always matches everything)
//   - Stock always shows 0
//
// To fix this properly, add these columns to the DrinksMenu model and migration:
//   veg: { type: DataTypes.BOOLEAN, defaultValue: true }
//   stockAvailable: { type: DataTypes.INTEGER, defaultValue: 0 }
// Then add them to the attributes array in getDrinksMenus().
// Until then, the Veg toggle is hidden since it's meaningless without real data.

import 'dart:async';
import 'package:Neevika/screens/Food/menu/MenuScreen.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:Neevika/screens/Drinks/drinksMenu/DrinksButtonsScreen.dart';
import 'package:Neevika/screens/Drinks/drinksMenu/DrinksEditMenuScreen.dart';
import 'package:Neevika/screens/Drinks/drinksMenu/DrinksOrderSummaryScreen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:Neevika/services/drinks_cart_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:Neevika/services/cart_service.dart';

import '../../Food/menu/MenuCartScreen.dart';

class DrinksMenuScreen extends StatefulWidget {
  final String? selectedCategoryName;
  const DrinksMenuScreen({super.key, this.selectedCategoryName});

  @override
  State<DrinksMenuScreen> createState() => _DrinksMenuScreenState();
}

class _DrinksMenuScreenState extends State<DrinksMenuScreen> {
  List<Map<String, dynamic>> menuItems = [];
  Map<int, String> categoryMap = {};
  String selectedCategory = 'All';
  String searchQuery = '';
  bool isLoading = true;
  bool hasErrorOccurred = false;
  bool isAuthorized = false;
  int itemCount = CartService().getCartItemCount();
  String userRole = '';
  String? userId;

  Timer? _debounce;
  Timer? _timeoutTimer;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    selectedCategory = widget.selectedCategoryName ?? 'All';
    fetchDrinkCategoriesAndMenu();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _timeoutTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // These special categories are client-side only — never sent to the backend
  static const _clientSideCategories = {'All', 'Offer', 'Urgent Sale'};

  Future<void> fetchDrinkCategoriesAndMenu() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedCategories = prefs.getString('cached_drink_categories');
    final cacheTimestamp = prefs.getInt('drink_categories_cache_time') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    bool useCached =
        cachedCategories != null && (now - cacheTimestamp) < 3600000;

    if (useCached) {
      final List<dynamic> data = json.decode(cachedCategories);
      if (!mounted) return;
      setState(() {
        categoryMap = {for (var c in data) c['id']: c['name']};
      });
      await fetchMenuItems();
      _refreshDrinkCategoriesInBackground(prefs);
      return;
    }

    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 6), () {
      if (isLoading && mounted) {
        setState(() {
          isLoading = false;
          hasErrorOccurred = true;
        });
      }
    });

    try {
      final results = await Future.wait([
        http.get(Uri.parse('${dotenv.env['API_URL']}/drinks-categories/')),
        _fetchMenuItemsRequest(),
      ]);

      final categoriesResponse = results[0];
      final menuResponse = results[1];

      if (!mounted) return;

      if (categoriesResponse.statusCode == 200) {
        final List<dynamic> data = json.decode(categoriesResponse.body);
        await prefs.setString(
          'cached_drink_categories',
          categoriesResponse.body,
        );
        await prefs.setInt('drink_categories_cache_time', now);
        if (!mounted) return;
        setState(() {
          categoryMap = {for (var c in data) c['id']: c['name']};
        });
      }

      _processMenuResponse(menuResponse);
    } catch (e) {
      print('Error fetching drinks categories & menu: $e');
      if (!mounted) return;
      setState(() {
        isLoading = false;
        hasErrorOccurred = true;
      });
    }
  }

  void _refreshDrinkCategoriesInBackground(SharedPreferences prefs) async {
    try {
      final res = await http.get(
        Uri.parse('${dotenv.env['API_URL']}/drinks-categories/'),
      );
      if (res.statusCode == 200) {
        await prefs.setString('cached_drink_categories', res.body);
        await prefs.setInt(
          'drink_categories_cache_time',
          DateTime.now().millisecondsSinceEpoch,
        );
      }
    } catch (e) {
      print('Background drink category refresh failed: $e');
    }
  }

  Future<void> fetchMenuItems({String? searchTerm, bool silent = false}) async {
    try {
      if (searchTerm != null) searchQuery = searchTerm;
      final res = await _fetchMenuItemsRequest();
      if (!mounted) return;
      _processMenuResponse(res);
    } catch (e) {
      print("Error fetching drinks menu: $e");
      if (!silent && mounted) {
        setState(() {
          isAuthorized = true;
          isLoading = false;
          hasErrorOccurred = true;
        });
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  Optimistic helpers — instant UI changes, no network wait
  // ─────────────────────────────────────────────────────────────

  void _applyOptimisticUpdate(Map<String, dynamic> patch) {
    final idx = menuItems.indexWhere((m) => m['id'] == patch['id']);
    if (idx == -1) return;
    setState(() {
      final merged = Map<String, dynamic>.from(menuItems[idx])..addAll(patch);
      if (patch.containsKey('categoryId')) {
        merged['category'] =
            categoryMap[patch['categoryId']] ?? menuItems[idx]['category'];
      }
      menuItems[idx] = merged;
    });
  }

  void _applyOptimisticDelete(int itemId) {
    setState(() {
      menuItems.removeWhere((m) => m['id'] == itemId);
    });
  }

  // ─────────────────────────────────────────────────────────────

  Future<http.Response> _fetchMenuItemsRequest() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwtToken');
    if (token == null) throw Exception('No token found');

    final decodedToken = JwtDecoder.decode(token);
    userId = decodedToken['id']?.toString();
    userRole = decodedToken['role'] ?? '';

    final queryParams = <String, String>{};

    if (searchQuery.isNotEmpty) queryParams['search'] = searchQuery;

    // Only send category to backend for real categories
    // 'Offer' and 'Urgent Sale' are client-side filters only
    if (selectedCategory != 'All' &&
        !_clientSideCategories.contains(selectedCategory)) {
      final matchingEntry = categoryMap.entries.firstWhere(
        (e) => e.value.toString() == selectedCategory,
        orElse: () => const MapEntry(-1, ''),
      );
      if (matchingEntry.key != -1) {
        queryParams['category'] = matchingEntry.key.toString();
      } else {
        final parsed = int.tryParse(selectedCategory);
        if (parsed != null) {
          queryParams['category'] = parsed.toString();
        } else {
          queryParams['category'] = selectedCategory;
        }
      }
    }

    queryParams['limit'] = '100';

    final uri = Uri.parse(
      '${dotenv.env['API_URL']}/drinks-menu/',
    ).replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

    return http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
  }

  void _processMenuResponse(http.Response res) {
    if (!mounted) return;
    if (res.statusCode == 200 ||
        res.statusCode == 201 ||
        res.statusCode == 204) {
      final List<dynamic> data = json.decode(res.body);
      setState(() {
        menuItems =
            data.map<Map<String, dynamic>>((item) {
              return {
                'id': item['id'],
                'name': item['name'],
                'description': item['description'] ?? 'No description',
                'price': item['price'],
                // 'veg' does not exist in DrinksMenu model — always null from API
                // We keep it in the map as null so card logic can handle it safely
                'veg': item['veg'],
                'categoryId': item['drinksCategoryId'],
                'category': categoryMap[item['drinksCategoryId']] ?? 'N/A',
                'isOffer': item['isOffer'] ?? false,
                'isUrgent': item['isUrgent'] ?? false,
                'outOfStock': item['isOutOfStock'] ?? false,
                'waiterCommission': item['waiterCommission']?.toString() ?? '0',
                'offerPrice': item['offerPrice']?.toString() ?? '0',
                'commissionType': item['commissionType']?.toString() ?? 'flat',
                // 'stockAvailable' does not exist in DrinksMenu model — always null
                'stock_available': item['stockAvailable']?.toString() ?? '0',
              };
            }).toList();
        isAuthorized = true;
        isLoading = false;
        hasErrorOccurred = false;
      });
      _timeoutTimer?.cancel();
    } else if (res.statusCode == 403) {
      setState(() {
        isAuthorized = false;
        isLoading = false;
        hasErrorOccurred = true;
      });
    } else {
      setState(() {
        isAuthorized = true;
        isLoading = false;
        hasErrorOccurred = true;
      });
    }
  }

  List<String> get categories => [
    'All',
    'Urgent Sale',
    'Offer',
    ...categoryMap.values.toSet(),
  ];

  List<Map<String, dynamic>> get filteredMenuItems {
    return menuItems.where((item) {
      final matchesCategory =
          selectedCategory == 'All' ||
          (selectedCategory == 'Offer' && item['isOffer'] == true) ||
          (selectedCategory == 'Urgent Sale' && item['isUrgent'] == true) ||
          item['category'] == selectedCategory;

      final matchesSearch = item['name'].toString().toLowerCase().contains(
        searchQuery.toLowerCase(),
      );

      return matchesCategory && matchesSearch;
    }).toList();
  }

  List<Map<String, dynamic>> get filteredMenuItemsWithOpenBar {
    return [
      {
        'id': null,
        'name': 'Open Bar',
        'price': null,
        'veg': null,
        'category': 'Custom',
        'isOffer': false,
        'isUrgent': false,
        'isOpenBar': true,
      },
      ...filteredMenuItems,
    ];
  }

  Widget _buildCartSnackBar() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: GestureDetector(
          onTap:
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => CartPage()),
              ),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1C1917),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.shopping_cart_outlined,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'View Cart',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                Text(
                  '$itemCount items',
                  style: GoogleFonts.poppins(
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
            const SizedBox(height: 4),
            Text(
              'Menu',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Manage restaurant menu',
              style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
      body:
          isLoading
              ? Center(
                child: LoadingAnimationWidget.staggeredDotsWave(
                  color: Colors.black,
                  size: 40,
                ),
              )
              : hasErrorOccurred
              ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10.0),
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
                        isAuthorized
                            ? "Something went wrong"
                            : "You are not authorized to access this page",
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1F2937),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isAuthorized
                            ? "Please check your connection or try again."
                            : "You don't have permission to view this content.",
                        style: GoogleFonts.poppins(
                          fontSize: 13,
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
                          fetchDrinkCategoriesAndMenu();
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
                ),
              )
              : LayoutBuilder(
                builder: (context, constraints) {
                  bool isWideScreen = constraints.maxWidth > 600;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: ListView(
                      children: [
                        const SizedBox(height: 10),
                        buildSearchBar(),
                        _buildTopRowButtons(scale: 1.1),
                        if (isWideScreen)
                          _buildGridView()
                        else
                          ...sortedMenuItems.map(
                            (item) => _buildMenuItemCard(item),
                          ),
                      ],
                    ),
                  );
                },
              ),
      bottomNavigationBar: itemCount != 0 ? _buildCartSnackBar() : null,
      floatingActionButton: FloatingActionButton(
        onPressed: _showCategoriesDialog,
        backgroundColor: Colors.black,
        child: const Icon(Icons.menu, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  void _showCategoriesDialog() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Categories',
      barrierColor: Colors.black.withOpacity(0.7),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return SafeArea(
          child: Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Material(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: 500,
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                  padding: const EdgeInsets.all(16),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: categories.length,
                    itemBuilder: (context, index) {
                      final category = categories[index];
                      bool isSelected = selectedCategory == category;
                      return ListTile(
                        title: Text(
                          category,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: isSelected ? Colors.white : Colors.white70,
                          ),
                        ),
                        tileColor:
                            isSelected ? Colors.white12 : Colors.transparent,
                        onTap: () {
                          setState(() {
                            selectedCategory = category;
                            isLoading = true;
                          });
                          Navigator.of(context).pop();
                          fetchMenuItems();
                        },
                      );
                    },
                    separatorBuilder:
                        (_, __) =>
                            const Divider(color: Colors.white24, thickness: 1),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopRowButtons({double scale = 1.0}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Food Menu button — full row since Veg toggle is removed
          // (veg field doesn't exist in DrinksMenu model)
          SizedBox(
            width: double.infinity,
            height: 45,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD95326),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed:
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => MenuScreen()),
                  ),
              icon: Icon(Icons.wine_bar, color: Colors.white, size: 20 * scale),
              label: Text(
                'Food Menu',
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
          const SizedBox(height: 15),
          if (userRole == 'Admin' ||
              userRole == 'Restaurant Manager' ||
              userRole == 'Owner' ||
              userRole == 'Acting Restaurant Manager')
            SizedBox(
              width: double.infinity,
              height: 45,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD95326),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddDrinksItemsButtonPage(),
                    ),
                  ).then((updated) {
                    if (updated == true) {
                      fetchMenuItems();
                      _showSuccessSnackBar(
                        message: 'Menu Item Added successfully',
                      );
                    }
                  });
                },
                icon: Icon(Icons.add, color: Colors.white, size: 20 * scale),
                label: Text(
                  'Add Item',
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showSuccessSnackBar({required String message}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.green[600],
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showErrorSnackBar({required String message}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.red[400],
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget buildSearchBar() {
    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.7,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: TextField(
          controller: _searchController,
          style: GoogleFonts.poppins(fontSize: 12, color: Colors.black),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF8F5F2),
            hintText: 'Search Menu Items...',
            hintStyle: GoogleFonts.poppins(
              fontSize: 14,
              color: const Color(0xFF1C1917),
            ),
            prefixIcon: const Icon(Icons.search, color: Color(0xFF1C1917)),
            suffixIcon:
                searchQuery.isNotEmpty
                    ? IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          searchQuery = '';
                          isLoading = true;
                        });
                        fetchMenuItems(searchTerm: '');
                      },
                    )
                    : null,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: Color.fromARGB(255, 201, 200, 200),
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
          onChanged: (value) {
            if (_debounce?.isActive ?? false) _debounce!.cancel();
            setState(() => searchQuery = value);
            final trimmed = value.trim();
            if (trimmed.length >= 3 || trimmed.isEmpty) {
              _debounce = Timer(const Duration(milliseconds: 700), () {
                if (mounted) {
                  setState(() => isLoading = true);
                  fetchMenuItems(searchTerm: trimmed);
                }
              });
            }
          },
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get sortedMenuItems {
    final items = List<Map<String, dynamic>>.from(filteredMenuItemsWithOpenBar);

    items.sort((a, b) {
      // Always keep Open Bar at the top
      if (a['isOpenBar'] == true) return -1;
      if (b['isOpenBar'] == true) return 1;

      // Then prioritize urgent items
      if (a['isUrgent'] == true && b['isUrgent'] == false) return -1;
      if (a['isUrgent'] == false && b['isUrgent'] == true) return 1;

      return 0;
    });

    return items;
  }

  Widget _buildGridView() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sortedMenuItems.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 3 / 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemBuilder:
          (context, index) => _buildMenuItemCard(sortedMenuItems[index]),
    );
  }

  void _showOpenFoodDialog() {
  final nameCtrl = TextEditingController();
  final priceCtrl = TextEditingController();
  bool applyVat = true;

  showDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            title: Text(
              'Add Open Bar',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [

                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Enter Item Name',
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 12),

                TextField(
                  controller: priceCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    hintText: 'Enter Price',
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 12),

                /// VAT TOGGLE
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    "Apply VAT",
                    style: GoogleFonts.poppins(fontSize: 13),
                  ),
                  value: applyVat,
                  onChanged: (val) {
                    setStateDialog(() {
                      applyVat = val;
                    });
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.red)),
                onPressed: () => Navigator.pop(context),
              ),

              ElevatedButton(
                child: const Text('Add'),
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  final priceText = priceCtrl.text.trim();

                  if (name.isNotEmpty &&
                      double.tryParse(priceText) != null) {

                    Navigator.pop(context);

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OrderSummaryPage(
                          itemId:
                              'open-bar-${DateTime.now().millisecondsSinceEpoch}',
                          itemName: name,
                          itemPrice: double.parse(priceText),

                          /// SEND VAT VALUE
                          applyVat: applyVat,
                        ),
                      ),
                    ).then((_) {
                      if (!mounted) return;
                      setState(() =>
                          itemCount = CartService().getCartItemCount());
                    });
                  }
                },
              ),
            ],
          );
        },
      );
    },
  );
}

  Widget _buildMenuItemCard(Map<String, dynamic> item) {
    final int stockAvailable =
        int.tryParse(item['stock_available']?.toString() ?? '0') ?? 0;

    if (item['isOpenBar'] == true) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        color: Colors.blueGrey.shade50,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: InkWell(
          onTap: _showOpenFoodDialog,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_box, size: 18, color: Colors.black87),
                  const SizedBox(height: 10),
                  Text(
                    'Open Bar',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: const Color(0xFF1C1917),
                    ),
                  ),
                  Text(
                    'Enter custom name & price',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 2,
      color:
          item['outOfStock'] == true
              ? Colors.grey.shade200
              : item['isUrgent'] == true
              ? Colors.red.shade100
              : item['isOffer'] == true
              ? Colors.amber.shade100
              : Colors.white,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        // FIX 1: Removed setState() wrapping fetchDrinkCategoriesAndMenu() to prevent
        // setState-during-layout crash. Also added mounted guard and null-safe price parsing.
        onTap: () async {
          final price = double.tryParse(item['price']?.toString() ?? '');
          if (price == null) return;
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (_) => OrderSummaryPage(
                    itemId: item['id'].toString(),
                    itemName: item['name'],
                    itemPrice: price,
                  ),
            ),
          );
          if (!mounted) return;
          setState(() => itemCount = CartService().getCartItemCount());
          fetchDrinkCategoriesAndMenu();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // FIX 2: Replaced Flexible (invalid outside a Row/flex context at this level)
              // with a plain Text using overflow: ellipsis — achieves the same visual result
              // without causing layout assertion failures.
              Text(
                item['name'],
                style: GoogleFonts.poppins(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1C1917),
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              if (item['isOffer'] == true)
                Text(
                  "(Commission: ${item['commissionType'] == 'flat' ? '₹${item['waiterCommission']}' : '${item['waiterCommission']}%'})",
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 4),
              Text(
                'Category: ${item['category']}',
                style: GoogleFonts.poppins(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w500,
                  color: const Color.fromARGB(255, 105, 100, 95),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  item['isOffer'] == true
                      ? Row(
                        children: [
                          Text(
                            '₹${item['price']}',
                            style: GoogleFonts.poppins(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.red,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '₹${item['offerPrice']}',
                            style: GoogleFonts.poppins(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      )
                      : Text(
                        '₹${item['price']}',
                        style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.green,
                        ),
                      ),
                  if (userRole == 'Admin' ||
                      userRole == 'Captain' ||
                      userRole == 'Restaurant Manager' ||
                      userRole == 'Owner' ||
                      userRole == 'Acting Restaurant Manager')
                    _buildEditButton(item),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditButton(Map<String, dynamic> item) {
    return SizedBox(
      width: 75,
      height: 30,
      child: OutlinedButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (context) => UpdateDrinksMenuPage(
                    id: item['id'],
                    name: item['name'],
                    price: item['price'].toString(),
                    categoryId: item['categoryId'],
                    description: item['description'],
                    veg: item['veg'] ?? true,
                    isOffer: item['isOffer'] ?? false,
                    isUrgent: item['isUrgent'] ?? false,
                    waiterCommission: item['waiterCommission'] ?? '0',
                    offerPrice: item['offerPrice'] ?? '0',
                    commissionType: item['commissionType'] ?? 'flat',
                    userRole: userRole,
                    OutOfStock: item['outOfStock'] ?? false,
                  ),
            ),
          ).then((result) {
            if (result == null) return;

            if (result is Map<String, dynamic>) {
              if (result['deleted'] == true) {
                _applyOptimisticDelete(item['id']);
                _showSuccessSnackBar(message: 'Menu Item Deleted successfully');
              } else {
                _applyOptimisticUpdate({...item, ...result});
                _showSuccessSnackBar(message: 'Menu Item Updated successfully');
              }
              // Background re-sync — no spinner shown
              fetchMenuItems(silent: true);
            } else if (result == true) {
              _showSuccessSnackBar(message: 'Menu Item Updated successfully');
              fetchMenuItems(silent: true);
            }
          });
        },
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.grey.shade400, width: 1),
          backgroundColor: const Color.fromARGB(255, 243, 240, 238),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.edit, size: 14, color: Color(0xFF1C1917)),
            const SizedBox(width: 4),
            Text(
              'Edit',
              style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1C1917),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
