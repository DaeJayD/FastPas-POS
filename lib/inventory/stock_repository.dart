import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/store_connection.dart';

class StockAdjustment {
  const StockAdjustment({
    required this.productId,
    required this.branchId,
    required this.previousStock,
    required this.delta,
    required this.userId,
    required this.username,
  });
  final String productId, branchId, userId, username;
  final int previousStock, delta;
  int get newStock => previousStock + delta;
  void validate() {
    if (productId.isEmpty ||
        branchId.isEmpty ||
        previousStock < 0 ||
        delta == 0 ||
        newStock < 0) {
      throw ArgumentError('Invalid stock adjustment');
    }
  }
}

/// Retains the current sequential stock/movement contract. Phase 5 moves the
/// pair into a server transaction to handle failures and concurrent changes.
class StockRepository {
  StockRepository({SupabaseClient? client})
    : _client = client ?? StoreConnection.client;
  final SupabaseClient _client;
  Future<void> adjust(StockAdjustment adjustment) async {
    adjustment.validate();
    await _client
        .from('branch_stock')
        .update({
          'current_stock': adjustment.newStock,
          'last_updated': DateTime.now().toIso8601String(),
        })
        .eq('product_id', adjustment.productId)
        .eq('branch_id', adjustment.branchId);
    await _client.from('inventory_movements').insert({
      'product_id': adjustment.productId,
      'branch_id': adjustment.branchId,
      'movement_type': adjustment.delta > 0 ? 'in' : 'out',
      'quantity': adjustment.delta.abs(),
      'previous_stock': adjustment.previousStock,
      'new_stock': adjustment.newStock,
      'user_id': adjustment.userId,
      'username': adjustment.username,
      'reason': 'Manual stock adjustment',
    });
  }
}
