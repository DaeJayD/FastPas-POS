import 'package:supabase_flutter/supabase_flutter.dart';

import '../branches/branch_repository.dart';
import '../core/store_connection.dart';
import 'sale_models.dart';

class SavedSale {
  const SavedSale(this.id, {this.stockWarnings = 0});
  final String id;
  final int stockWarnings;
}

/// Adapter for the existing sequential sale/item/stock writes. It is not an
/// atomic checkout or a payment-provider confirmation. Phase 6 replaces it with
/// a server transaction and idempotency key.
class SalesRepository {
  SalesRepository({SupabaseClient? client})
    : _client = client ?? StoreConnection.client;
  final SupabaseClient _client;

  Future<SavedSale> record(SaleDraft draft) async {
    if (draft.session.preview || StoreConnection.isPreview) {
      throw StateError('Sample sales cannot be written');
    }
    final branches = await BranchRepository(client: _client).branches();
    final matching = branches
        .where(
          (branch) =>
              branch.location == draft.session.location ||
              branch.name == draft.session.location,
        )
        .toList();
    if (matching.length != 1) {
      throw StateError('Sale branch could not be resolved uniquely');
    }
    final branchId = matching.single.id;
    final totals = draft.totals;
    final row = await _client
        .from('sales')
        .insert({
          'total_amount': totals.total,
          'subtotal_amount': totals.subtotal,
          'tax_amount': totals.tax,
          'discount_amount': totals.discount,
          'payment_method': draft.paymentMethod.toLowerCase(),
          'created_at': DateTime.now().toIso8601String(),
          'status': 'completed',
          'cashier_name': draft.session.fullName,
          'cashier_role': draft.session.role,
          'cash_given': draft.cashGiven,
          'change': draft.change,
          'branch_location': draft.session.location,
        })
        .select()
        .single();
    final id = row['id']?.toString();
    if (id == null) throw StateError('Sale record missing its ID');
    await _client.from('sale_items').insert([
      for (final line in draft.lines)
        {
          'sale_id': id,
          'product_id': line.productId,
          'quantity': line.quantity,
          'unit_price': line.unitPrice,
          'total_price': line.amount,
        },
    ]);
    var warnings = 0;
    for (final line in draft.lines) {
      try {
        final stock = await _client
            .from('branch_stock')
            .select('current_stock, id')
            .eq('product_id', line.productId)
            .eq('branch_id', branchId)
            .single();
        await _client
            .from('branch_stock')
            .update({
              'current_stock':
                  ((stock['current_stock'] as num?)?.toInt() ?? 0) -
                  line.quantity,
            })
            .eq('id', stock['id'])
            .eq('branch_id', branchId);
      } catch (_) {
        warnings++;
      }
    }
    return SavedSale(id, stockWarnings: warnings);
  }

  Future<List<Map<String, dynamic>>> history() async => await _client
      .from('sales')
      .select()
      .order('created_at', ascending: false);

  Future<List<SaleLine>> lines(String saleId) async {
    final rows = await _client
        .from('sale_items')
        .select('product_id, quantity, unit_price, products(name)')
        .eq('sale_id', saleId);
    return [
      for (final row in rows)
        SaleLine(
          productId: row['product_id'].toString(),
          name: row['products']?['name']?.toString() ?? 'Deleted product',
          unitPrice: (row['unit_price'] as num?)?.toDouble() ?? 0,
          quantity: (row['quantity'] as num?)?.toInt() ?? 0,
        ),
    ];
  }
}
