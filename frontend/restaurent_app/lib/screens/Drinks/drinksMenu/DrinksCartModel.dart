class DrinksCartItem {
  final String itemId;
  final String itemName;
  final double itemPrice;
  int quantity;
  final String description;

  DrinksCartItem({
    required this.itemId,
    required this.itemName,
    required this.itemPrice,
    required this.quantity,
    this.description = '',
  });
}