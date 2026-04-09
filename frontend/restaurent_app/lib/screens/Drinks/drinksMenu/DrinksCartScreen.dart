import 'package:Neevika/services/cart_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:Neevika/screens/Drinks/drinksMenu/DrinksMenuScreen.dart';
import 'DrinksCartModel.dart';
import '../../../services/drinks_cart_service.dart';

class CartPage extends StatefulWidget {
  const CartPage({super.key});

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  final DrinksCartService _cartService = DrinksCartService();

  List<dynamic> _sections = [];
  List<dynamic> _filteredTables = [];

  String? _selectedSectionId;
  dynamic _selectedRestaurantTableId;
  dynamic _selectedTableId;

  @override
  void initState() {
    super.initState();
    _fetchSections();
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

  void _increaseQuantity(DrinksCartItem item) {
    setState(() {
      item.quantity++;
    });
  }

  void _decreaseQuantity(DrinksCartItem item) {
    if (item.quantity > 1) {
      setState(() {
        item.quantity--;
      });
    }
  }

  void _placeOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwtToken');
    if (token == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Please Login to place Order')));
      print('No token found. User might not be logged in.');
      return;
    }

    final decodedToken = JwtDecoder.decode(token);
    final userId = decodedToken['id'];
    final userRole = decodedToken['role'];

    if (_selectedSectionId == null || _selectedTableId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select both section and table')),
      );
      return;
    }

    final cartItems = _cartService.cartItems;

    if (cartItems.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cart is empty')));
      return;
    }

    final order = {
      'userId': userId,
      'sectionId': _selectedSectionId,
      'restaurantTableId': _selectedRestaurantTableId,
      'tableId': _selectedTableId['id'],
      'items':
          cartItems
              .map(
                (item) => {
                  'itemId':
                      item.itemId == "open-bar"
                          ? null
                          : int.tryParse(item.itemId.toString()) ?? item.itemId,
                  'itemName': item.itemName,
                  'quantity': item.quantity,
                  'price': item.itemPrice,
                  'description': item.description,
                  'is_custom': true,
                },
              )
              .toList(),
    };

    print('Order payload: ${jsonEncode(order)}'); // for debugging

    try {
      final response = await http.post(
        Uri.parse('${dotenv.env['API_URL']}/drinks-orders'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(order),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Order placed successfully
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Order placed successfully!')));

        // Clear the cart
        _cartService.clearCart();

        ScaffoldMessenger.of(context).clearSnackBars();

        Navigator.pop(context);

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => DrinksMenuScreen()),
        );

        // Or simply call setState to update the current page state
        setState(() {});
      } else {
        // Handle error response
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to place order: ${response.reasonPhrase}'),
          ),
        );
      }
    } catch (e) {
      // Handle connection errors
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error placing order: $e')));
    }
  }

  Widget _buildDropdowns(bool isLargeScreen) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child:
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
    );
  }

  Widget _buildSectionDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Section',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 12),
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
              style: GoogleFonts.poppins(fontSize: 10),
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
                      style: GoogleFonts.poppins(fontSize: 10),
                    ),
                  );
                }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildTableDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Table',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 12),
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
              style: GoogleFonts.poppins(fontSize: 10),
            ),
            isExpanded: true,
            underline: SizedBox(),
            onChanged: (value) {
              setState(() {
                _selectedTableId = value;
                _selectedRestaurantTableId = _filteredTables.indexOf(value) + 1;
              });
            },
            items:
                _filteredTables.map<DropdownMenuItem<dynamic>>((table) {
                  return DropdownMenuItem<dynamic>(
                    value: table,
                    child: Text(
                      'Table ${_filteredTables.indexOf(table) + 1} - ${table['status']}',
                      style: GoogleFonts.poppins(fontSize: 10),
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
            hint: Text(
              'Please select',
              style: GoogleFonts.poppins(fontSize: 10),
            ),
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
    final isLargeScreen = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F5F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F5F2),
        title: Text(
          ' Drinks Cart',
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
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              ElevatedButton(
                                onPressed: _placeOrder,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.lightGreen,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
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

  Widget _buildCartItemCard(DrinksCartItem item, bool isLargeScreen) {
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
              fontSize: isLargeScreen ? 12 : 10,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }
}
