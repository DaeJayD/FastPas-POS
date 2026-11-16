import 'package:supabase_flutter/supabase_flutter.dart';

class OverviewSeller {
  OverviewSeller(this.id, this.name, this.sku, this.quantity);
  final String id, name, sku;
  int quantity;
}

class OverviewStock {
  OverviewStock(this.name, this.sku, this.quantity, this.threshold);
  final String name, sku;
  final int quantity, threshold;
}

class OverviewDetails {
  OverviewDetails(this.itemsSold, this.receiptCount, this.sellers, this.stock);
  final int itemsSold, receiptCount;
  final List<OverviewSeller> sellers;
  final List<OverviewStock> stock;
}

/// Read-only supplements to the existing, authorized cash report. Sales ranking
/// explicitly covers the latest 200 synced receipts, not a timezone/date total.
class OverviewDetailsRepository {
  OverviewDetailsRepository(this.client, this.business, this.actor);
  final SupabaseClient client;
  final String business, actor;
  void _check() {
    if (client.auth.currentUser?.id != actor) {
      throw const FormatException(
        'Account changed. Return to your businesses.',
      );
    }
  }

  Future<OverviewDetails> load(String branch) async {
    _check();
    final receipts = await client
        .from('pos_cash_sales')
        .select('id,business_id,branch_id,payload')
        .eq('business_id', business)
        .eq('branch_id', branch)
        .order('received_at', ascending: false)
        .order('id', ascending: false)
        .limit(200)
        .timeout(const Duration(seconds: 12));
    _check();
    final sellers = <String, OverviewSeller>{};
    var units = 0;
    for (final row in receipts) {
      if (row['business_id'] != business || row['branch_id'] != branch) {
        throw const FormatException(
          'Overview scope changed. Reload the report.',
        );
      }
      for (final line in (row['payload'] as Map)['items'] as List) {
        final quantity = line['quantity'] as int;
        if (quantity < 0) {
          throw const FormatException('Invalid receipt quantities.');
        }
        units += quantity;
        final id = line['product_id'] as String;
        final seller = sellers.putIfAbsent(
          id,
          () => OverviewSeller(
            id,
            line['name'] as String,
            line['sku'] as String,
            0,
          ),
        );
        seller.quantity += quantity;
      }
    }
    final stock = <OverviewStock>[];
    String? after;
    while (true) {
      var query = client
          .from('pos_item_stock')
          .select(
            'business_id,branch_id,product_id,quantity,low_stock_threshold,pos_items!inner(name,sku,active)',
          )
          .eq('business_id', business)
          .eq('branch_id', branch);
      if (after != null) query = query.gt('product_id', after);
      final page = await query
          .order('product_id')
          .limit(500)
          .timeout(const Duration(seconds: 12));
      _check();
      for (final row in page) {
        if (row['business_id'] != business || row['branch_id'] != branch) {
          throw const FormatException(
            'Overview scope changed. Reload the report.',
          );
        }
        final item = row['pos_items'] as Map;
        final quantity = (row['quantity'] as num).toInt();
        final threshold = (row['low_stock_threshold'] as num).toInt();
        if (item['active'] == true &&
            (quantity <= 0 || threshold > 0 && quantity <= threshold)) {
          stock.add(
            OverviewStock(
              item['name'] as String,
              item['sku'] as String,
              quantity,
              threshold,
            ),
          );
        }
      }
      if (page.length < 500) break;
      final next = page.last['product_id'] as String;
      if (after == next) {
        throw const FormatException('Stock cursor did not advance.');
      }
      after = next;
    }
    final ranked = sellers.values.toList()
      ..sort((a, b) {
        final byQuantity = b.quantity.compareTo(a.quantity);
        return byQuantity == 0 ? a.name.compareTo(b.name) : byQuantity;
      });
    stock.sort((a, b) => a.quantity.compareTo(b.quantity));
    return OverviewDetails(
      units,
      receipts.length,
      ranked.take(5).toList(),
      stock,
    );
  }
}
