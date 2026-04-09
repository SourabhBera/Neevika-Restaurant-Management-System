import 'dart:async';
import 'package:Neevika/screens/Drinks/drinksMenu/DrinksMenuScreen.dart';
import 'package:Neevika/screens/home/MyOrdersScreen.dart';
import 'package:Neevika/widgets/sidebar.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:Neevika/screens/Food/menu/AddMenuScreen.dart';
import 'package:Neevika/screens/Food/menu/AddScreen.dart';
import 'package:Neevika/screens/Food/menu/EditMenuScreen.dart';
import 'package:Neevika/screens/Food/menu/MenuCartScreen.dart';
import 'package:Neevika/screens/Food/menu/MenuOrderSummaryScreen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:Neevika/services/cart_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class MenuScreen extends StatefulWidget {
  final String? selectedCategoryName;
  final String? preSelectedSectionId;
  final String? preSelectedSectionName;
  final dynamic preSelectedTableId;
  final dynamic preSelectedTable;
  final dynamic preSelectedRestaurantTableId;

  const MenuScreen({
    super.key,
    this.selectedCategoryName,
    this.preSelectedSectionId,
    this.preSelectedSectionName,
    this.preSelectedTableId,
    this.preSelectedTable,
    this.preSelectedRestaurantTableId,
  });

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  List<Map<String, dynamic>> menuItems = [];
  Map<int, String> categoryMap = {};
  String selectedCategory = 'All';
  String searchQuery = '';
  bool isLoading = true;
  bool hasErrorOccurred = false;
  bool showVegOnly = false;
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
    if (widget.preSelectedSectionId != null &&
        widget.preSelectedTableId != null) {
      CartService().setPreSelectedTable(
        sectionId: widget.preSelectedSectionId!,
        sectionName: widget.preSelectedSectionName ?? '',
        tableId: widget.preSelectedTableId,
        table: widget.preSelectedTable,
        restaurantTableId: widget.preSelectedRestaurantTableId,
      );
    }
    fetchCategoriesAndMenu();
    print(itemCount);
  }

  // ─────────────────────────────────────────────────────────────
  //  Optimistic helpers — instant UI update, no spinner
  // ─────────────────────────────────────────────────────────────

  /// Merge [patch] fields into the matching item in [menuItems] immediately,
  /// then fire a silent background re-sync so other devices catch up.
  void _applyOptimisticUpdate(Map<String, dynamic> patch) {
    final idx = menuItems.indexWhere((m) => m['id'] == patch['id']);
    if (idx == -1) return;
    setState(() {
      final merged = Map<String, dynamic>.from(menuItems[idx])..addAll(patch);
      // Re-resolve the display category name if categoryId changed
      if (patch.containsKey('categoryId')) {
        merged['category'] =
            categoryMap[patch['categoryId']] ?? menuItems[idx]['category'];
      }
      menuItems[idx] = merged;
    });
  }

  /// Remove the deleted item from [menuItems] immediately.
  void _applyOptimisticDelete(int itemId) {
    setState(() {
      menuItems.removeWhere((m) => m['id'] == itemId);
    });
  }

  // ─────────────────────────────────────────────────────────────

  Future<void> fetchCategoriesAndMenu() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedCategories = prefs.getString('cached_categories');
    final cacheTimestamp = prefs.getInt('categories_cache_time') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    bool shouldUseCachedCategories =
        cachedCategories != null && (now - cacheTimestamp) < 3600000;

    if (shouldUseCachedCategories) {
      final List<dynamic> data = json.decode(cachedCategories);
      setState(() {
        categoryMap = {for (var c in data) c['id']: c['name']};
      });
      await fetchMenuItems();
      _refreshCategoriesInBackground(prefs, now);
      return;
    }

    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 6), () {
      if (isLoading) {
        setState(() {
          isLoading = false;
          hasErrorOccurred = true;
        });
      }
    });

    try {
      final results = await Future.wait([
        http.get(Uri.parse('${dotenv.env['API_URL']}/categories/')),
        _fetchMenuItemsRequest(),
      ]);

      final categoriesResponse = results[0];
      final menuResponse = results[1];

      if (categoriesResponse.statusCode == 200) {
        final List<dynamic> data = json.decode(categoriesResponse.body);
        await prefs.setString('cached_categories', categoriesResponse.body);
        await prefs.setInt('categories_cache_time', now);
        setState(() {
          categoryMap = {for (var c in data) c['id']: c['name']};
        });
      }

      _processMenuResponse(menuResponse);
    } catch (e) {
      print('Error fetching categories and menu: $e');
      setState(() {
        isLoading = false;
        hasErrorOccurred = true;
      });
    }
  }

  // [silent] skips showing the loading spinner — used for background re-syncs
  Future<void> fetchMenuItems({String? searchTerm, bool silent = false}) async {
    try {
      if (searchTerm != null) searchQuery = searchTerm;
      final res = await _fetchMenuItemsRequest();
      _processMenuResponse(res);
    } catch (e) {
      print("Error fetching menu: $e");
      if (!silent) {
        setState(() {
          isAuthorized = true;
          isLoading = false;
          hasErrorOccurred = true;
        });
      }
    }
  }

  void _refreshCategoriesInBackground(SharedPreferences prefs, int now) async {
    try {
      final res = await http
          .get(Uri.parse('${dotenv.env['API_URL']}/categories/'));
      if (res.statusCode == 200) {
        await prefs.setString('cached_categories', res.body);
        await prefs.setInt('categories_cache_time', now);
      }
    } catch (e) {
      print('Background category refresh failed: $e');
    }
  }

  Future<http.Response> _fetchMenuItemsRequest() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwtToken');

    if (token == null) throw Exception('No token found');

    final decodedToken = JwtDecoder.decode(token);
    userId = decodedToken['id'].toString();
    userRole = decodedToken['role'];

    final queryParams = <String, String>{};

    if (searchQuery.isNotEmpty) queryParams['search'] = searchQuery;

    if (selectedCategory != 'All') {
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

    if (showVegOnly) queryParams['vegOnly'] = 'true';
    queryParams['limit'] = '100';

    final uri = Uri.parse('${dotenv.env['API_URL']}/menu/')
        .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

    print('➡️ GET ${uri.toString()}');

    return http.get(uri, headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    });
  }

  void _processMenuResponse(http.Response res) {
    if (res.statusCode == 200 ||
        res.statusCode == 201 ||
        res.statusCode == 204) {
      final List<dynamic> data = json.decode(res.body);
      setState(() {
        menuItems = data.map<Map<String, dynamic>>((item) {
          return {
            'id': item['id'],
            'name': item['name'],
            'description': item['description'] ?? 'No description',
            'price': item['price'],
            'veg': item['veg'],
            'categoryId': item['categoryId'],
            'category': categoryMap[item['categoryId']] ?? 'Uncategorized',
            'isOffer': item['isOffer'] ?? false,
            'isUrgent': item['isUrgent'] ?? false,
            'waiterCommission': item['waiterCommission']?.toString() ?? '0',
            'offerPrice': item['offerPrice']?.toString() ?? '0',
            'commissionType': item['commissionType']?.toString() ?? 'flat',
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
      final matchesSearch = searchQuery.isEmpty ||
          item['name'].toLowerCase().contains(searchQuery.toLowerCase());

      final matchesCategory = selectedCategory == 'All' ||
          (selectedCategory == 'Offer' && item['isOffer'] == true) ||
          (selectedCategory == 'Urgent Sale' && item['isUrgent'] == true) ||
          item['category'] == selectedCategory;

      final matchesVeg =
          searchQuery.isNotEmpty || !showVegOnly || item['veg'] == true;

      if (searchQuery.isNotEmpty) return matchesSearch && matchesVeg;
      return matchesCategory && matchesSearch && matchesVeg;
    }).toList();
  }

  List<Map<String, dynamic>> get filteredMenuItemsWithOpenFood {
    return [
      {
        'id': null,
        'name': 'Open Food',
        'price': null,
        'veg': null,
        'category': 'Custom',
        'isOffer': false,
        'isUrgent': false,
        'isOpenFood': true,
      },
      ...filteredMenuItems,
    ];
  }

  List<Map<String, dynamic>> get displayedMenuItems {
    return [
      {
        'id': null,
        'name': 'Open Food',
        'price': null,
        'veg': null,
        'category': 'Custom',
        'isOffer': false,
        'isUrgent': false,
        'isOpenFood': true,
      },
      ...menuItems,
    ];
  }

  List<Map<String, dynamic>> get sortedMenuItems => displayedMenuItems;

  Widget _buildCartSnackBar() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: GestureDetector(
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (context) => CartPage())),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1C1917),
              borderRadius: BorderRadius.circular(12),
            ),
            padding:
                const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.shopping_cart_outlined,
                        color: Colors.white),
                    const SizedBox(width: 10),
                    Text('View Cart',
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                  ],
                ),
                Text('$itemCount items',
                    style: GoogleFonts.poppins(
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                        fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _timeoutTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F5F2),
        drawer: const Sidebar(),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF8F5F2),
          elevation: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text('Menu',
                  style: GoogleFonts.poppins(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Manage restaurant menu',
                  style:
                      GoogleFonts.poppins(fontSize: 10, color: Colors.grey)),
              const SizedBox(height: 4),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 20),
              child: IconButton(
                icon: const Icon(Icons.checklist_rounded, color: Colors.black),
                tooltip: 'My Orders',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          MyOrdersScreen(userId: userId!.toString()),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        body: isLoading
            ? Center(
                child: LoadingAnimationWidget.staggeredDotsWave(
                    color: Colors.black, size: 40))
            : hasErrorOccurred
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.alertTriangle,
                              size: 60, color: Color(0xFFEF4444)),
                          const SizedBox(height: 16),
                          Text(
                            isAuthorized
                                ? "Something went wrong"
                                : "You are not authorized to access this page",
                            style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF1F2937)),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isAuthorized
                                ? "Please check your connection or try again."
                                : "You don't have permission to view this content.",
                            style: GoogleFonts.poppins(
                                fontSize: 13, color: Colors.grey[600]),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                isLoading = true;
                                hasErrorOccurred = false;
                              });
                              fetchCategoriesAndMenu();
                            },
                            icon: const Icon(LucideIcons.refreshCw,
                                size: 20, color: Colors.white),
                            label: Text("Retry",
                                style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
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
                        padding:
                            const EdgeInsets.symmetric(horizontal: 20),
                        child: ListView(
                          children: [
                            const SizedBox(height: 10),
                            buildSearchBar(),
                            _buildTopRowButtons(scale: 1.1),
                            if (isWideScreen)
                              _buildGridView()
                            else
                              ...sortedMenuItems
                                  .map((item) => _buildMenuItemCard(item)),
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
            hintText: 'Search ...',
            hintStyle: GoogleFonts.poppins(
                fontSize: 14, color: const Color(0xFF1C1917)),
            prefixIcon:
                const Icon(Icons.search, color: Color(0xFF1C1917)),
            suffixIcon: searchQuery.isNotEmpty
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
                  color: Color.fromARGB(255, 201, 200, 200), width: 1.3),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: Color(0xFFE5E5E5), width: 1.5),
            ),
          ),
          onChanged: (value) {
            if (_debounce?.isActive ?? false) _debounce!.cancel();
            setState(() => searchQuery = value);
            final trimmed = value.trim();
            if (trimmed.length >= 2 || trimmed.isEmpty) {
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
                        title: Text(category,
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white70)),
                        tileColor: isSelected
                            ? Colors.white12
                            : Colors.transparent,
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
                    separatorBuilder: (_, __) =>
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
    final toggleWidth = 140 * scale;
    final toggleHeight = 42 * scale;
    final segmentWidth = (toggleWidth - 4) / 2;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TweenAnimationBuilder<Color?>(
                duration: const Duration(milliseconds: 200),
                tween: ColorTween(
                  begin: isDark
                      ? Colors.grey.shade800
                      : const Color(0xFFEDEBE9),
                  end: showVegOnly
                      ? const Color.fromARGB(255, 181, 245, 212)
                      : (isDark
                          ? Colors.grey.shade800
                          : const Color(0xFFEDEBE9)),
                ),
                builder: (context, backgroundColor, child) {
                  return Container(
                    width: toggleWidth,
                    height: toggleHeight,
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark
                            ? Colors.grey.shade600
                            : Colors.grey.shade400,
                        width: 1,
                      ),
                    ),
                    child: Stack(
                      children: [
                        AnimatedAlign(
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeInOut,
                          alignment: showVegOnly
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeInOut,
                            width: segmentWidth,
                            height: toggleHeight - 6,
                            margin: const EdgeInsets.symmetric(
                                horizontal: 2, vertical: 3),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.grey.shade200
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            _buildSegmentWithIcon(
                              icon: Icons.restaurant_menu,
                              label: 'All',
                              selected: !showVegOnly,
                              onTap: () {
                                if (showVegOnly) {
                                  HapticFeedback.lightImpact();
                                  setState(() => showVegOnly = false);
                                }
                              },
                              iconSize: 15 * scale,
                              textSize: 12,
                              isDark: isDark,
                            ),
                            _buildSegmentWithIcon(
                              icon: Icons.eco,
                              label: 'Veg',
                              selected: showVegOnly,
                              onTap: () {
                                if (!showVegOnly) {
                                  HapticFeedback.lightImpact();
                                  setState(() => showVegOnly = true);
                                }
                              },
                              iconSize: 14 * scale,
                              textSize: 12,
                              isDark: isDark,
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 160 * scale,
                height: 45,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD95326),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: EdgeInsets.symmetric(
                        horizontal: 24 * scale, vertical: 5),
                  ),
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => DrinksMenuScreen())),
                  icon: Icon(Icons.wine_bar,
                      color: Colors.white, size: 20 * scale),
                  label: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text('Drinks Menu',
                        style: GoogleFonts.poppins(
                            color: Colors.white, fontSize: 11)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 35),
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
                      borderRadius: BorderRadius.circular(8)),
                  padding: EdgeInsets.symmetric(
                      horizontal: 24 * scale, vertical: 5),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => AddItemsButtonPage()),
                  ).then((updated) {
                    if (updated == true) {
                      fetchMenuItems();
                      _showSuccessSnackBar(
                          message: 'Food Item Added successfully');
                    }
                  });
                },
                icon: Icon(Icons.add, color: Colors.white, size: 20 * scale),
                label: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text('Add Item',
                      style: GoogleFonts.poppins(
                          color: Colors.white, fontSize: 11)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSegmentWithIcon({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required double iconSize,
    required double textSize,
    required bool isDark,
  }) {
    final Color activeColor =
        isDark ? Colors.black : const Color(0xFF1C1917);
    final Color inactiveColor =
        isDark ? Colors.grey.shade300 : const Color(0xFF78726D);

    return Expanded(
      child: GestureDetector(
        onTap: () {
          onTap();
          setState(() => isLoading = true);
          fetchMenuItems();
        },
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(
              begin: inactiveColor,
              end: selected ? activeColor : inactiveColor),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          builder: (context, color, child) {
            return Container(
              alignment: Alignment.center,
              height: double.infinity,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: iconSize, color: color),
                  const SizedBox(width: 4),
                  Text(label,
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: textSize,
                          color: color)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _showSuccessSnackBar({required String message}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message,
          style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.white)),
      backgroundColor: Colors.green[600],
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 2),
    ));
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
      itemBuilder: (context, index) =>
          _buildMenuItemCard(sortedMenuItems[index]),
    );
  }

  Widget _buildMenuItemCard(Map<String, dynamic> item) {
    if (item['isOpenFood'] == true) {
      return Card(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        color: Colors.blueGrey.shade50,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: InkWell(
          onTap: _showOpenFoodDialog,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_box, size: 18, color: Colors.black87),
                  const SizedBox(height: 10),
                  Text('Open Food',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: const Color(0xFF1C1917))),
                  Text('Enter custom name & price',
                      style: GoogleFonts.poppins(
                          fontSize: 10, color: Colors.grey[600])),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Card(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 2,
      color: item['isUrgent'] == true
          ? Colors.red.shade100
          : (item['isOffer'] == true ? Colors.amber.shade100 : Colors.white),
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OrderSummaryPage(
                itemId: item['id'].toString(),
                itemName: item['name'],
                itemPrice: double.parse(item['price'].toString()),
              ),
            ),
          );
          setState(() {
            fetchCategoriesAndMenu();
            itemCount = CartService().getCartItemCount();
          });
        },
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Image.asset(
                    item['veg'] == true
                        ? 'lib/assets/VegLogo.png'
                        : 'lib/assets/NonVegLogo.png',
                    width: 20,
                    height: 20,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(item['name'],
                        style: GoogleFonts.poppins(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1C1917)),
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 10),
                  if (item['isOffer'] == true)
                    Flexible(
                      child: Text(
                        "(Commission: ${item['commissionType'] == 'flat' ? '₹${item['waiterCommission']}' : '${item['waiterCommission']}%'})",
                        style: GoogleFonts.poppins(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1C1917)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.only(left: 6.0),
                child: Text('Category: ${item['category']}',
                    style: GoogleFonts.poppins(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                        color:
                            const Color.fromARGB(255, 105, 100, 95))),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 6.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    (item['isOffer'] == true &&
                            item['offerPrice'] != null &&
                            double.tryParse(
                                    item['offerPrice'].toString()) !=
                                double.tryParse(item['price'].toString()))
                        ? Row(children: [
                            Text('₹${item['price']}',
                                style: GoogleFonts.poppins(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.red,
                                    decoration:
                                        TextDecoration.lineThrough)),
                            const SizedBox(width: 5),
                            Text('₹${item['offerPrice']}',
                                style: GoogleFonts.poppins(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: const Color.fromARGB(
                                        255, 28, 155, 33))),
                          ])
                        : Text('₹${item['price']}',
                            style: GoogleFonts.poppins(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.green)),
                    Row(
                      children: [
                        if (userRole == 'Admin' ||
                            userRole == 'Captain' ||
                            userRole == 'Restaurant Manager' ||
                            userRole == 'Acting Restaurant Manager')
                          _buildEditButton(item),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOpenFoodDialog() {
    final nameController = TextEditingController();
    final priceController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Add Open Food',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameController,
                decoration: const InputDecoration(
                    hintText: 'Enter Item Name',
                    border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: priceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    hintText: 'Enter Price',
                    border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.red)),
              onPressed: () => Navigator.pop(context)),
          ElevatedButton(
            child: const Text('Add'),
            onPressed: () {
              final name = nameController.text.trim();
              final priceText = priceController.text.trim();
              if (name.isNotEmpty && double.tryParse(priceText) != null) {
                Navigator.pop(context);
                final uniqueId =
                    'open-food-${DateTime.now().millisecondsSinceEpoch}';
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OrderSummaryPage(
                      itemId: uniqueId,
                      itemName: name,
                      itemPrice: double.parse(priceText),
                    ),
                  ),
                ).then((_) {
                  setState(
                      () => itemCount = CartService().getCartItemCount());
                });
              }
            },
          ),
        ],
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
              builder: (context) => UpdateMenuPage(
                id: item['id'],
                name: item['name'],
                price: item['price'].toString(),
                categoryId: item['categoryId'],
                description: item['description'],
                veg: item['veg'],
                isOffer: item['isOffer'] ?? false,
                isUrgent: item['isUrgent'] ?? false,
                waiterCommission: item['waiterCommission'] ?? '0',
                offerPrice: item['offerPrice'] ?? '0',
                commissionType: item['commissionType'] ?? 'flat',
                userRole: userRole,
              ),
            ),
          ).then((result) {
            if (result == null) return;

            if (result is Map<String, dynamic>) {
              if (result['deleted'] == true) {
                // ✅ Optimistic delete — item disappears instantly
                _applyOptimisticDelete(item['id']);
                _showSuccessSnackBar(
                    message: 'Menu Item Deleted successfully');
              } else {
                // ✅ Optimistic update — offer badge / price changes instantly
                _applyOptimisticUpdate({...item, ...result});
                _showSuccessSnackBar(
                    message: 'Menu Item Updated successfully');
              }
              // Delay the background re-sync until AFTER the server cache
              // has expired (TTL = 10s). If we fire immediately, the GET
              // still hits the cached (pre-change) response and rolls back
              // the optimistic update we just applied.
              Future.delayed(const Duration(seconds: 11), () {
                if (mounted) fetchMenuItems(silent: true);
              });
            } else if (result == true) {
              // Legacy fallback (older EditMenuScreen versions)
              _showSuccessSnackBar(
                  message: 'Menu Item Updated successfully');
              Future.delayed(const Duration(seconds: 11), () {
                if (mounted) fetchMenuItems(silent: true);
              });
            }
          });
        },
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.grey.shade400, width: 1),
          backgroundColor: const Color.fromARGB(255, 243, 240, 238),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.edit, size: 14, color: Color(0xFF1C1917)),
            const SizedBox(width: 4),
            Text('Edit',
                style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1C1917))),
          ],
        ),
      ),
    );
  }
}