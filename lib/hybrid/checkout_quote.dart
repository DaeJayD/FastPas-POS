import '../workspaces/workspace_repository.dart';

class CheckoutChanged extends FormatException {
  const CheckoutChanged()
    : super('Items changed. Cancel and review your cart before paying.');
}

class CheckoutLine {
  const CheckoutLine({
    required this.id,
    required this.name,
    required this.sku,
    required this.quantity,
    required this.unitCents,
    required this.available,
  });
  final String id, name, sku;
  final int quantity, unitCents, available;

  bool matches(Map<String, Object?> row) =>
      row['id'] == id &&
      row['name'] == name &&
      row['sku'] == sku &&
      row['price_cents'] == unitCents &&
      row['quantity'] == available;
}

/// A frozen review of one cart in one account, business and branch.
class CheckoutQuote {
  CheckoutQuote._(
    this.userId,
    this.businessId,
    this.branchId,
    List<CheckoutLine> lines,
  ) : lines = List.unmodifiable(lines),
      attemptId = WorkspaceRepository.newRequestId();
  final String userId, businessId, branchId;
  final String attemptId;
  final List<CheckoutLine> lines;
  int get totalCents =>
      lines.fold(0, (sum, line) => sum + line.quantity * line.unitCents);

  factory CheckoutQuote.capture({
    required String userId,
    required String businessId,
    required String branchId,
    required Iterable<Map<String, Object?>> products,
    required Map<String, int> quantities,
  }) {
    if (quantities.isEmpty || quantities.length > 200) {
      throw ArgumentError('Empty or oversized cart');
    }
    final catalog = {for (final row in products) row['id'] as String: row};
    final lines = <CheckoutLine>[];
    for (final entry in quantities.entries) {
      final row = catalog[entry.key];
      if (row == null ||
          entry.value < 1 ||
          entry.value > 100000 ||
          (row['quantity'] as int) < entry.value) {
        throw const CheckoutChanged();
      }
      lines.add(
        CheckoutLine(
          id: entry.key,
          name: row['name'] as String,
          sku: row['sku'] as String,
          quantity: entry.value,
          unitCents: row['price_cents'] as int,
          available: row['quantity'] as int,
        ),
      );
    }
    return CheckoutQuote._(userId, businessId, branchId, lines);
  }

  void checkScope(String user, String business, String branch) {
    if (userId != user || businessId != business || branchId != branch) {
      throw StateError('Checkout belongs to another store.');
    }
  }

  void checkQuantities(Map<String, int> quantities) {
    if (quantities.length != lines.length ||
        lines.any((line) => quantities[line.id] != line.quantity)) {
      throw const CheckoutChanged();
    }
  }

  bool matchesSaved(Map<String, dynamic> payload, int cash) {
    final saved = payload['items'];
    return payload['business_id'] == businessId &&
        payload['branch_id'] == branchId &&
        payload['cash_cents'] == cash &&
        saved is List &&
        saved.length == lines.length &&
        lines.every(
          (line) =>
              saved
                  .where(
                    (item) =>
                        item is Map &&
                        item['product_id'] == line.id &&
                        item['name'] == line.name &&
                        item['sku'] == line.sku &&
                        item['quantity'] == line.quantity &&
                        item['unit_cents'] == line.unitCents,
                  )
                  .length ==
              1,
        );
  }
}
