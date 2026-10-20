import '../core/pos_session.dart';

class SaleLine {
  const SaleLine({
    required this.productId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
    this.stock = 0,
  });
  final String productId, name;
  final double unitPrice;
  final int quantity, stock;
  factory SaleLine.fromCart(Map<String, dynamic> item) => SaleLine(
    productId: item['id'].toString(),
    name: item['name']?.toString() ?? 'Product',
    unitPrice: (item['price'] as num?)?.toDouble() ?? 0,
    quantity: (item['cart_quantity'] as num?)?.toInt() ?? 0,
    stock: (item['stock'] as num?)?.toInt() ?? 0,
  );
  double get amount => unitPrice * quantity;
  Map<String, dynamic> toCart() => {
    'id': productId,
    'name': name,
    'price': unitPrice,
    'cart_quantity': quantity,
    'stock': stock,
  };
}

class SaleTotals {
  const SaleTotals({
    required this.subtotal,
    required this.tax,
    required this.discount,
    required this.total,
  });
  final double subtotal, tax, discount, total;

  /// Retains the current 12% tax and subtotal discount contract. Exact monetary
  /// representation and configurable tax belong to the transaction phase.
  factory SaleTotals.calculate(
    Iterable<SaleLine> lines, {
    double discountPercent = 0,
    double taxRate = .12,
  }) {
    if (!discountPercent.isFinite ||
        discountPercent < 0 ||
        discountPercent > 100 ||
        !taxRate.isFinite ||
        taxRate < 0) {
      throw ArgumentError('Invalid pricing rate');
    }
    var subtotal = 0.0;
    for (final line in lines) {
      if (line.quantity < 0 || !line.unitPrice.isFinite || line.unitPrice < 0) {
        throw ArgumentError('Invalid sale line');
      }
      subtotal += line.amount;
    }
    final tax = subtotal * taxRate, discount = subtotal * discountPercent / 100;
    return SaleTotals(
      subtotal: subtotal,
      tax: tax,
      discount: discount,
      total: subtotal + tax - discount,
    );
  }
}

class SaleDraft {
  const SaleDraft({
    required this.session,
    required this.lines,
    required this.totals,
    required this.paymentMethod,
    required this.cashGiven,
    required this.change,
  });
  final PosSession session;
  final List<SaleLine> lines;
  final SaleTotals totals;
  final String paymentMethod;
  final double cashGiven, change;
}
