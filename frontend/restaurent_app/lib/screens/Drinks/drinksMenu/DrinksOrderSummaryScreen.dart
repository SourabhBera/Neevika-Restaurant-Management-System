import 'package:Neevika/services/cart_service.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:Neevika/screens/Drinks/drinksMenu/DrinksCartModel.dart';
import 'package:Neevika/services/notification_service.dart';
import 'package:Neevika/services/drinks_cart_service.dart';
import 'package:Neevika/screens/Food/menu/MenuCartModel.dart';

class OrderSummaryPage extends StatefulWidget {
  final String itemName;
  final String itemId;
  final double itemPrice; // <-- changed from String to double
  final bool applyVat;

  const OrderSummaryPage({
    super.key,
    required this.itemId,
    required this.itemName,
    required this.itemPrice,
    this.applyVat = false,

  });

  @override
  _OrderSummaryPageState createState() => _OrderSummaryPageState();
}

class _OrderSummaryPageState extends State<OrderSummaryPage> {
  final TextEditingController _descriptionController = TextEditingController();
  int quantity = 1;
 

  void _increaseQuantity() {
    setState(() => quantity++);
  }

  void _decreaseQuantity() {
    if (quantity > 1) setState(() => quantity--);
  }

  Future<void> _addToCart() async {
  String description = _descriptionController.text.trim();

  final cartItem = CartItem(
    itemId: widget.itemId,
    itemName: widget.itemName,
    itemPrice: widget.itemPrice,
    quantity: quantity,
    description: description,
    type: 'drink',
    applyVat: widget.applyVat,
  );

  CartService().addItem(cartItem);
  CartService().getCartItemCount();

  
  Navigator.pop(context, {
    "message": "${widget.itemName} added to cart.",
    "total": (quantity * widget.itemPrice).toStringAsFixed(2),
  });

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Item added to cart!',
        style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
      ),
      backgroundColor: Colors.green,
    ),
  );
}

  @override
Widget build(BuildContext context) {
  final size = MediaQuery.of(context).size;
  final isLargeScreen = size.width > 600;
  final padding = isLargeScreen ? size.width * 0.15 : 20.0;
  double totalPrice = quantity * widget.itemPrice;

  return Scaffold(
    backgroundColor: const Color(0xFFF8F5F2),
    appBar: AppBar(
      backgroundColor: const Color(0xFFF8F5F2),
      elevation: 0,
      title: Text(
        'Order Summary',
        style: GoogleFonts.poppins(
          fontSize: isLargeScreen ? 24 : 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    body: SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Text('Selected Item', style: _sectionTitleStyle(size)),
          ),
          SizedBox(height: 8),
          _buildSelectedItemCard(size),
          SizedBox(height: 20),
          _buildInputField("Note", "Enter order notes (optional)", _descriptionController, isLargeScreen),
          SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total:', style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: size.width > 600 ? 16 : 13.3,
                )),
                Text(
                  '₹${totalPrice.toStringAsFixed(2)}',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: isLargeScreen ? 16 : 12.8,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 30),
          _buildPlaceOrderButton(size),
        ],
      ),
    ),
  );
}


  Widget _buildInputField(String label, String hint, TextEditingController controller, bool isLargeScreen) {
  return Center(
    child: SizedBox(
      width: MediaQuery.of(context).size.width * 0.88,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _sectionTitleStyle(MediaQuery.of(context).size)),
          SizedBox(height: 6),
          TextField(
            controller: controller,
            style: GoogleFonts.poppins(fontSize: isLargeScreen ? 16 : 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.poppins(fontSize: isLargeScreen ? 14 : 12),
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ],
      ),
    ),
  );
}
  Widget _buildSelectedItemCard(Size size) {
  final isLargeScreen = size.width > 600;

  return Center(
    child: Container(
      width: MediaQuery.of(context).size.width * 0.88,
      height: MediaQuery.of(context).size.width * 0.15,
      padding: EdgeInsets.all(isLargeScreen ? 20 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              widget.itemName,
              style: GoogleFonts.poppins(
                fontSize: isLargeScreen ? 14 : 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Row(
            children: [
              IconButton(onPressed: _decreaseQuantity, icon: Icon(Icons.remove), iconSize: 18,),
              Text(
                quantity.toString(),
                style: GoogleFonts.poppins(fontSize: isLargeScreen ? 14 : 11.8, fontWeight: FontWeight.w600),
              ),
              IconButton(onPressed: _increaseQuantity, icon: Icon(Icons.add), iconSize: 18,),
            ],
          ),
        ],
      ),
    ),
  );
}


  Widget _buildPlaceOrderButton(Size size) {
  final isLargeScreen = size.width > 600;

  return Center(
    child: SizedBox(
      width: MediaQuery.of(context).size.width * 0.88,
      child: ElevatedButton.icon(
        onPressed:  _addToCart,
        icon: Icon(Icons.add_shopping_cart, color: Colors.black),
        label: Text(
          'Add to Cart',
          style: GoogleFonts.poppins(
            fontSize: isLargeScreen ? 16 : 14,
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.lightGreen,
          padding: EdgeInsets.symmetric(vertical: isLargeScreen ? 18 : 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    ),
  );
}


  TextStyle _sectionTitleStyle(Size size) {
  return GoogleFonts.poppins(
    fontWeight: FontWeight.w600,
    fontSize: size.width > 600 ? 16 : 12,
  );
}

}
