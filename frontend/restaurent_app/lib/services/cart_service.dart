import 'package:Neevika/screens/Food/menu/MenuCartModel.dart';

class CartService {
  static final CartService _instance = CartService._internal();

  factory CartService() {
    return _instance;
  }

  CartService._internal();

  final List<CartItem> _cartItems = [];

  String? _preSelectedSectionId;
  String? _preSelectedSectionName;
  dynamic _preSelectedTableId;
  dynamic _preSelectedTable;
  dynamic _preSelectedRestaurantTableId;

  List<CartItem> get cartItems => List.unmodifiable(_cartItems);

  void setPreSelectedTable({
    required String sectionId,
    required String sectionName,
    required dynamic tableId,
    required dynamic table,
    required dynamic restaurantTableId,
  }) {
    _preSelectedSectionId = sectionId;
    _preSelectedSectionName = sectionName;
    _preSelectedTableId = tableId;
    _preSelectedTable = table;
    _preSelectedRestaurantTableId = restaurantTableId;
  }

   // NEW: Get pre-selected table info
  Map<String, dynamic>? getPreSelectedTable() {
    if (_preSelectedSectionId != null && _preSelectedTableId != null) {
      return {
        'sectionId': _preSelectedSectionId,
        'sectionName': _preSelectedSectionName,
        'tableId': _preSelectedTableId,
        'table': _preSelectedTable,
        'restaurantTableId': _preSelectedRestaurantTableId,
      };
    }
    return null;
  }

  // NEW: Clear pre-selected table info
  void clearPreSelectedTable() {
    _preSelectedSectionId = null;
    _preSelectedSectionName = null;
    _preSelectedTableId = null;
    _preSelectedTable = null;
    _preSelectedRestaurantTableId = null;
  }


  int getCartItemCount() {
    return _cartItems.length;
  }

  void addItem(CartItem item) {
    final existingIndex = _cartItems.indexWhere((element) => element.itemId == item.itemId);

    if (existingIndex != -1) {
      _cartItems[existingIndex].quantity += item.quantity;
    } else {
      _cartItems.add(item);
    }
  }

  void removeItem(String itemId) {
    _cartItems.removeWhere((item) => item.itemId == itemId);
  }

  void clearCart() {
    _cartItems.clear();
    clearPreSelectedTable();
  }

  double getTotalPrice() {
    return _cartItems.fold(0, (sum, item) => sum + item.itemPrice * item.quantity);
  }
}
