class CartItem {
  final String itemId;
  final String itemName;
  final double itemPrice;
  int quantity;
  final String description;
  final String type;
  final bool applyVat;

  CartItem({
    required this.itemId,
    required this.itemName,
    required this.itemPrice,
    required this.quantity,
    this.description = '',
    this.type = '',
    this.applyVat = false,
  });

  @override
  String toString() {
    return 'CartItem('
        'itemId: $itemId, '
        'itemName: $itemName, '
        'price: $itemPrice, '
        'quantity: $quantity, '
        'type: $type, '
        'description: $description)';
  }
}