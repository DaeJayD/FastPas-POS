import 'dart:convert';
import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_store.dart';

/// Bound to one immutable user/business/branch context for its entire lifetime.
class SyncService {
  SyncService(this.client, this.store, {this.isActive});
  final SupabaseClient client;
  final LocalStore store;
  final bool Function()? isActive;
  bool _running = false;

  void _checkIdentity() {
    if (isActive?.call() == false) {
      throw StateError('Store was closed. Pending records are retained.');
    }
    if (client.auth.currentUser?.id != store.userId) {
      throw StateError('Sign in with the account that created these sales.');
    }
  }

  Future<void> synchronize() async {
    if (_running) return;
    _running = true;
    try {
      await _verifiedRole();
      for (final row in await store.pendingReceipts()) {
        _checkIdentity();
        final payload =
            jsonDecode(row['payload'] as String) as Map<String, dynamic>;
        if (payload['business_id'] != store.businessId ||
            payload['branch_id'] != store.branchId) {
          throw StateError('Queued sale does not belong to this store.');
        }
        try {
          await client
              .rpc('pos_sync_cash_sale', params: {'sale': payload})
              .timeout(const Duration(seconds: 8));
          await store.setStatus(row['id'] as String, 'synced');
        } on PostgrestException catch (error) {
          if ([
            '22023',
            '22P02',
            '23503',
            '23514',
            '42501',
          ].contains(error.code)) {
            await store.setStatus(
              row['id'] as String,
              'blocked',
              error: error.message,
            );
          } else {
            rethrow;
          }
        }
      }
      await _refreshCatalog();
    } finally {
      _running = false;
    }
  }

  Future<String> _verifiedRole() async {
    _checkIdentity();
    final access = await Future.wait([
      client
          .from('pos_memberships')
          .select('role')
          .eq('business_id', store.businessId)
          .eq('user_id', store.userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 8)),
      client
          .from('pos_branches')
          .select('id')
          .eq('business_id', store.businessId)
          .eq('id', store.branchId)
          .maybeSingle()
          .timeout(const Duration(seconds: 8)),
    ]);
    _checkIdentity();
    final membership = access[0], branch = access[1];
    if (membership == null || branch == null) {
      await store.setMeta('revoked', 'true');
      throw StateError(
        'Workspace access was removed. Pending records are retained.',
      );
    }
    _checkIdentity();
    return membership['role'] as String;
  }

  Future<void> _refreshCatalog() async {
    _checkIdentity();
    // Page large catalogs explicitly; the server's default row cap is not a catalog limit.
    final rows = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += 500) {
      final page = await client
          .from('pos_item_stock')
          .select(
            'product_id,quantity,pos_items!inner(id,name,sku,price_cents,active)',
          )
          .eq('business_id', store.businessId)
          .eq('branch_id', store.branchId)
          .order('product_id')
          .range(offset, offset + 499)
          .timeout(const Duration(seconds: 8));
      rows.addAll(page);
      if (page.length < 500) break;
    }
    _checkIdentity();
    final role = await _verifiedRole();
    await store.replaceSnapshot([
      for (final row in rows)
        if ((row['pos_items'] as Map)['active'] == true)
          {
            'id': row['product_id'],
            'name': row['pos_items']['name'],
            'sku': row['pos_items']['sku'],
            'price_cents': row['pos_items']['price_cents'],
            'quantity': row['quantity'],
          },
    ], role);
  }
}
