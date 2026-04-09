import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:Neevika/screens/Food/menu/MenuScreen.dart';
import 'package:Neevika/screens/Tables/TablesScreen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'MenuCartModel.dart';
import '../../../services/cart_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class CartPage extends StatefulWidget {
  const CartPage({super.key});

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  final CartService _cartService = CartService();

  bool _isLoading = false;

  List<dynamic> _sections = [];
  List<dynamic> _filteredTables = [];

  String? _selectedSectionId;
  dynamic _selectedRestaurantTableId;
  dynamic _selectedTableId;

  @override
  void initState() {
      super.initState();
  _fetchSections().then((_) {
    // After sections are loaded, check for pre-selected table
    final preSelected = _cartService.getPreSelectedTable();
    if (preSelected != null) {
      setState(() {
        _selectedSectionId = preSelected['sectionId'];
        
        // Find the section and set filtered tables
        final section = _sections.firstWhere(
          (sec) => sec['id'].toString() == preSelected['sectionId'],
          orElse: () => {},
        );
        
        if (section.isNotEmpty) {
          _filteredTables = section['tables'] ?? [];
          
          // Find and set the selected table
          final tableId = preSelected['tableId'];
          _selectedTableId = _filteredTables.firstWhere(
            (table) => table['id'] == tableId,
            orElse: () => null,
          );
          
          _selectedRestaurantTableId = preSelected['restaurantTableId'];
        }
      });
    }
  });
}

  Future<void> _fetchSections() async {
    final response = await http.get(
      Uri.parse('${dotenv.env['API_URL']}/sections'),
    );

    if (response.statusCode == 200) {
      setState(() {
        _sections = jsonDecode(response.body);
      });
    } else {
      // Handle error
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load sections')));
    }
  }

  void _removeItem(String itemId) {
    setState(() {
      _cartService.removeItem(itemId);
    });
  }

  void _clearCart() {
    setState(() {
      _cartService.clearCart();
    });
  }

  void _increaseQuantity(CartItem item) {
    setState(() {
      item.quantity++;
    });
  }

  void _decreaseQuantity(CartItem item) {
    if (item.quantity > 1) {
      setState(() {
        item.quantity--;
      });
    }
  }
void _placeOrder() async {
  setState(() {
    _isLoading = true;
  });

  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwtToken');
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please Login to place Order')),
      );
      return;
    }

    final decodedToken = JwtDecoder.decode(token);
    final userId = decodedToken['id'];

    if (_selectedSectionId == null || _selectedTableId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select both section and table')),
      );
      return;
    }

    final cartItems = _cartService.cartItems;

    if (cartItems.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cart is empty')));
      return;
    }

    // Decide what to send as restaurantTableId:
    // - If selected table has split_name (non-empty), use that string
    // - Else use _selectedRestaurantTableId (visual numeric index)
    // - Fallback to selected table's id if both above are null
    dynamic restaurantTableIdValue;
    try {
      final splitName = _selectedTableId != null ? (_selectedTableId['split_name'] ?? '').toString().trim() : '';
      if (splitName.isNotEmpty) {
        restaurantTableIdValue = splitName;
      } else if (_selectedRestaurantTableId != null) {
        restaurantTableIdValue = _selectedRestaurantTableId;
      } else {
        restaurantTableIdValue = _selectedTableId != null ? _selectedTableId['id'] : null;
      }
    } catch (e) {
      // defensive fallback
      restaurantTableIdValue = _selectedRestaurantTableId ?? (_selectedTableId != null ? _selectedTableId['id'] : null);
    }

    // Separate food and drink items
    final foodItems = cartItems.where((item) => item.type == 'food').toList();
    final drinkItems = cartItems.where((item) => item.type == 'drink').toList();

    // Send food order if any food items present
    if (foodItems.isNotEmpty) {
      final foodOrder = {
        'userId': userId,
        'sectionId': _selectedSectionId,
        'restaurantTableId': restaurantTableIdValue,
        'tableId': _selectedTableId['id'],
        'items': foodItems.map((item) => {
              // Check if itemId starts with 'open-food-' to identify custom items
              'itemId': item.itemId.startsWith('open-food-') ? null : item.itemId,
              'itemName': item.itemName,
              'quantity': item.quantity,
              'price': item.itemPrice,
              'description': item.description,
              'type': item.type,
              'is_custom': item.itemId.startsWith('open-food-'),
            }).toList(),
      };

      final foodResponse = await http.post(
        Uri.parse('${dotenv.env['API_URL']}/orders'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(foodOrder),
      );

      if (foodResponse.statusCode != 200 && foodResponse.statusCode != 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to place food order')),
        );
        return;
      }
    }

    // Send drink order if any drink items present
    if (drinkItems.isNotEmpty) {
      final drinkOrder = {
        'userId': userId,
        'sectionId': _selectedSectionId,
        'restaurantTableId': restaurantTableIdValue,
        'tableId': _selectedTableId['id'],
        'items': drinkItems.map((item) => {
              // Check if itemId starts with 'open-bar-' to identify custom drinks
              'itemId': item.itemId.startsWith('open-bar-') ? null : item.itemId,
              'itemName': item.itemName,
              'quantity': item.quantity,
              'price': item.itemPrice,
              'description': item.description,
              'type': item.type,
              'is_custom': item.itemId.startsWith('open-bar-'),
              'applyVat': item.applyVat,
            }).toList(),
      };

      final drinkResponse = await http.post(
        Uri.parse('${dotenv.env['API_URL']}/drinks-orders'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(drinkOrder),
      );

      if (drinkResponse.statusCode != 200 && drinkResponse.statusCode != 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to place drink order')),
        );
        return;
      }
    }

    // Success
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Order placed successfully!')),
    );

    _cartService.clearCart();
    Navigator.pop(context);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => ViewTableScreen()),
    );
    setState(() {});
  } catch (e) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Error placing order: $e')));
  } finally {
    // ALWAYS reset loading state
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }
}

  Widget _buildDropdowns(bool isLargeScreen) {
  final preSelected = _cartService.getPreSelectedTable();
  final isPreSelected = preSelected != null;

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Column(
      children: [
        // Show info banner if table is pre-selected
        if (isPreSelected)
          Container(
            padding: EdgeInsets.all(12),
            margin: EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.green.shade700, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Table pre-selected. You can change it below if needed.',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.green.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        
        // Existing dropdown layout
        isLargeScreen
            ? Row(
                children: [
                  Expanded(child: _buildSectionDropdown()),
                  SizedBox(width: 16),
                  Expanded(child: _buildTableDropdown()),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionDropdown(),
                  SizedBox(height: 12),
                  _buildTableDropdown(),
                ],
              ),
      ],
    ),
  );
}


  Widget _buildSectionDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Section',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 13.3,
          ),
        ),
        SizedBox(height: 6),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade400),
          ),
          child: DropdownButton<String>(
            value: _selectedSectionId,
            hint: Text(
              'Please select',
              style: GoogleFonts.poppins(fontSize: 12.8),
            ),
            isExpanded: true,
            underline: SizedBox(),
            onChanged: (value) {
              setState(() {
                _selectedSectionId = value;
                final section = _sections.firstWhere(
                  (sec) => sec['id'].toString() == value,
                  orElse: () => {},
                );
                _filteredTables = section['tables'] ?? [];
                _selectedTableId = null;
                _selectedRestaurantTableId = null;
              });
            },
            items:
                _sections.map<DropdownMenuItem<String>>((section) {
                  return DropdownMenuItem<String>(
                    value: section['id'].toString(),
                    child: Text(
                      section['name'],
                      style: GoogleFonts.poppins(fontSize: 13.5),
                    ),
                  );
                }).toList(),
          ),
        ),
      ],
    );
  }

 Widget _buildTableDropdown() {
  // Find current section name (if any)
  final currentSection = _sections.firstWhere(
    (sec) => sec['id'].toString() == (_selectedSectionId ?? ''),
    orElse: () => null,
  );
  final sectionName = currentSection != null ? currentSection['name']?.toString() ?? '' : '';

  // Build ordered meta list from _filteredTables: roots followed by their splits
  final List<Map<String, dynamic>> orderedMeta = [];
  if (_filteredTables.isNotEmpty) {
    // Group splits by parent and collect roots
    final Map<int, List<dynamic>> splitsByParent = {};
    final List<dynamic> roots = [];

    for (var t in _filteredTables) {
      final parentId = t['parent_table_id'];
      if (parentId == null) {
        roots.add(t);
      } else {
        final pid = parentId is int ? parentId : int.tryParse(parentId?.toString() ?? '');
        if (pid == null) {
          roots.add(t); // treat as root if parent id invalid
        } else {
          splitsByParent.putIfAbsent(pid, () => []).add(t);
        }
      }
    }

    // Sort roots deterministically by id
    roots.sort((a, b) {
      final ai = a['id'] is int ? a['id'] as int : int.tryParse(a['id']?.toString() ?? '') ?? 0;
      final bi = b['id'] is int ? b['id'] as int : int.tryParse(b['id']?.toString() ?? '') ?? 0;
      return ai.compareTo(bi);
    });

    // Assign sequential root numbers and build ordered list
    for (var i = 0; i < roots.length; i++) {
      final root = roots[i];
      final rootNum = i + 1;
      orderedMeta.add({
        'table': root,
        'isSplit': false,
        'rootNumber': rootNum,
        'splitIndex': null,
      });

      final children = splitsByParent[root['id']] ?? [];
      if (children.isNotEmpty) {
        // sort children for deterministic order (by split_name or id)
        children.sort((a, b) {
          final sa = (a['split_name'] ?? '').toString();
          final sb = (b['split_name'] ?? '').toString();
          if (sa.isNotEmpty && sb.isNotEmpty) return sa.compareTo(sb);
          final ai = a['id'] is int ? a['id'] as int : int.tryParse(a['id']?.toString() ?? '') ?? 0;
          final bi = b['id'] is int ? b['id'] as int : int.tryParse(b['id']?.toString() ?? '') ?? 0;
          return ai.compareTo(bi);
        });

        for (var c = 0; c < children.length; c++) {
          orderedMeta.add({
            'table': children[c],
            'isSplit': true,
            'rootNumber': rootNum,
            'splitIndex': c,
          });
        }
        splitsByParent.remove(root['id']);
      }
    }

    // Append any orphan splits (parents not present)
    if (splitsByParent.isNotEmpty) {
      splitsByParent.values.forEach((list) {
        list.forEach((child) {
          orderedMeta.add({
            'table': child,
            'isSplit': true,
            'rootNumber': null,
            'splitIndex': null,
          });
        });
      });
    }
  }

  // Helper to capitalize status
  String _cap(String? s) {
    if (s == null || s.isEmpty) return '';
    return s[0].toUpperCase() + s.substring(1);
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Select Table',
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.w600,
          fontSize: 13.5,
        ),
      ),
      SizedBox(height: 6),
      Container(
        padding: EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade400),
        ),
        child: DropdownButton<dynamic>(
          value: _selectedTableId,
          hint: Text(
            'Please select',
            style: GoogleFonts.poppins(fontSize: 12.8),
          ),
          isExpanded: true,
          underline: SizedBox(),
          onChanged: (value) {
            // value is the table object (same as before)
            setState(() {
              _selectedTableId = value;
              // compute restaurant table id as the visual index+1 within orderedMeta
              final selIndex = orderedMeta.indexWhere((m) {
                final tbl = m['table'];
                return tbl != null && tbl['id'] == value['id'];
              });
              _selectedRestaurantTableId = selIndex >= 0 ? selIndex + 1 : null;
            });
          },
          items: orderedMeta.map<DropdownMenuItem<dynamic>>((meta) {
            final table = meta['table'] as Map<String, dynamic>;
            final bool isSplit = meta['isSplit'] == true;
            final int? rootNumber = meta['rootNumber'] as int?;
            final int? splitIndex = meta['splitIndex'] as int?;
            final statusRaw = table['status']?.toString() ?? '';
            final status = _cap(statusRaw);

            // inner label logic: Table X for root; for split use split_name or X(A/B)
            String innerLabel;
            if (!isSplit) {
              innerLabel = "Table ${rootNumber ?? (orderedMeta.indexOf(meta) + 1)}";
            } else {
              final splitName = ("Table ${table['parent_table_id']} ${table['split_name']}" ?? '').toString();
              if (splitName.isNotEmpty) {
                innerLabel = splitName;
              } else if (rootNumber != null && splitIndex != null) {
                final suffix = String.fromCharCode(65 + (splitIndex % 26)); // A,B,C...
                innerLabel = "${rootNumber}$suffix";
              } else {
                innerLabel = ("Table ${table['parent_table_id']} ${table['split_name']}"?? "Split").toString();
              }
            }

            final base = sectionName.isNotEmpty ? "$innerLabel" : innerLabel;
            final displayLabel = status.isNotEmpty ? "$base  ($status)" : base;

            return DropdownMenuItem<dynamic>(
              value: table,
              child: Text(
                displayLabel,
                style: GoogleFonts.poppins(fontSize: 13.5),
              ),
            );
          }).toList(),
        ),
      ),
    ],
  );
}


  Widget _buildDropdown(
    String label,
    List<String> items,
    String? selectedValue,
    ValueChanged<String?> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        SizedBox(height: 6),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade400),
          ),
          child: DropdownButton<String>(
            value: selectedValue,
            hint: Text('Please select', style: GoogleFonts.poppins()),
            isExpanded: true,
            underline: SizedBox(),
            onChanged: onChanged,
            items:
                items.map((item) {
                  return DropdownMenuItem<String>(
                    value: item,
                    child: Text(item, style: GoogleFonts.poppins(fontSize: 10)),
                  );
                }).toList(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = _cartService.cartItems;
    print('\n\nCart items: $cartItems');
    final isLargeScreen = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F5F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F5F2),
        title: Text(
          'Cart',
          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (cartItems.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete),
              iconSize: 18,
              onPressed: _clearCart,
              tooltip: 'Clear Cart',
            ),
        ],
      ),
      body:
          cartItems.isEmpty
              ? Center(
                child: Text(
                  'Your cart is empty',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
              : Center(
                child: SizedBox(
                  width: MediaQuery.of(context).size.width * 0.95,
                  child: Column(
                    children: [
                      _buildDropdowns(isLargeScreen), // <-- Add dropdowns here
                      Expanded(
                        child: ListView.builder(
                          itemCount: cartItems.length,
                          itemBuilder: (context, index) {
                            final item = cartItems[index];
                            return _buildCartItemCard(item, isLargeScreen);
                          },
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Total: ₹${_cartService.getTotalPrice().toStringAsFixed(2)}',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              ElevatedButton(
                                onPressed:
                                    _isLoading ||
                                            _selectedSectionId == null ||
                                            _selectedTableId == null
                                        ? null
                                        : _placeOrder,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.lightGreen,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 34,
                                    vertical: 12,
                                  ),
                                ),
                                child: Text(
                                  'Checkout',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
    );
  }

  Widget _buildCartItemCard(CartItem item, bool isLargeScreen) {
    return Container(
      width: MediaQuery.of(context).size.width * 0.88,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: EdgeInsets.all(isLargeScreen ? 20 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: Item name and quantity controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  item.itemName,
                  style: GoogleFonts.poppins(
                    fontSize: isLargeScreen ? 14 : 12,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.remove),
                    iconSize: 18,
                    onPressed: () => _decreaseQuantity(item),
                  ),
                  Text(
                    item.quantity.toString(),
                    style: GoogleFonts.poppins(
                      fontSize: isLargeScreen ? 14 : 11.8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.add),
                    iconSize: 18,
                    onPressed: () => _increaseQuantity(item),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete),
                    iconSize: 18,
                    onPressed: () => _removeItem(item.itemId),
                    color: Colors.red,
                  ),
                ],
              ),
            ],
          ),

          // Bottom row: Description
          Text(
            item.description,
            style: GoogleFonts.poppins(
              fontSize: isLargeScreen ? 14 : 10,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }
}
