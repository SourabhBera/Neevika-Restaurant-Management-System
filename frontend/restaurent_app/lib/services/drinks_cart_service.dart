import 'package:Neevika/screens/Drinks/drinksMenu/DrinksCartModel.dart';

class DrinksCartService {
  static final DrinksCartService _drinksInstance = DrinksCartService._internal();

  factory DrinksCartService() {
    return _drinksInstance;
  }

  DrinksCartService._internal();

  final List<DrinksCartItem> _drinkCartItems = [];

  List<DrinksCartItem> get cartItems => List.unmodifiable(_drinkCartItems);

  int getCartItemCount() {
    return _drinkCartItems.length;
  }

  void addItem(DrinksCartItem item) {
    final existingIndex = _drinkCartItems.indexWhere((element) => element.itemId == item.itemId);

    if (existingIndex != -1) {
      _drinkCartItems[existingIndex].quantity += item.quantity;
    } else {
      _drinkCartItems.add(item);
    }
  }

  void removeItem(String itemId) {
    _drinkCartItems.removeWhere((item) => item.itemId == itemId);
  }

  void clearCart() {
    _drinkCartItems.clear();
  }

  double getTotalPrice() {
    return _drinkCartItems.fold(0, (sum, item) => sum + item.itemPrice * item.quantity);
  }
}
