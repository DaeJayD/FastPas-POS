import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_store.dart';
import '../core/receipt_details.dart';

enum SyncOutcome { synchronized, queued, waiting }

/// Bound to one immutable user/business/branch context for its entire lifetime.
class SyncService {
  SyncService(
    this.client,
    this.store, {
    this.isActive,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;
  final SupabaseClient client;
  final LocalStore store;
  final bool Function()? isActive;
  final DateTime Function() _clock;
  static const _batchSize = 32;
  static const _retrySeconds = [30, 60, 120, 240, 300];
  static final _flights = <String, Future<void>>{};

  void _checkIdentity() {
    if (isActive?.call() == false) {
      throw StateError('Store was closed. Pending records are retained.');
    }
    if (client.auth.currentUser?.id != store.userId) {
      throw StateError('Sign in with the account that created these sales.');
    }
  }

  Future<SyncOutcome> synchronize({bool force = false}) async {
    final path = store.db.path;
    // Different route visits can have separate connections to the same store.
    // Wait for the previous upload and its stock snapshot as one operation.
    while (true) {
      final previous = _flights[path];
      if (previous == null) break;
      await previous;
      _checkIdentity();
    }
    _checkIdentity();
    final done = Completer<void>();
    _flights[path] = done.future;
    try {
      final access = await _verifiedAccess();
      final pending = await store.pendingReceipts(limit: _batchSize);
      if (!['owner', 'manager', 'cashier'].contains(access.role)) {
        await store.setMeta('role', access.role);
        if (pending.isNotEmpty) {
          throw StateError('Selling access is required to upload receipts.');
        }
      }
      for (final row in pending) {
        _checkIdentity();
        final id = row['id'] as String;
        final retryAfter = row['retry_after_ms'] as int?;
        if (!force && retryAfter != null) {
          final remaining = retryAfter - _clock().millisecondsSinceEpoch;
          if (remaining > 0 && remaining <= _retrySeconds.last * 1000) {
            return SyncOutcome.waiting;
          }
        }
        final payload =
            jsonDecode(row['payload'] as String) as Map<String, dynamic>;
        if (payload['id'] != id ||
            payload['business_id'] != store.businessId ||
            payload['branch_id'] != store.branchId) {
          throw StateError('Queued sale does not belong to this store.');
        }
        final session = client.auth.currentSession;
        if (session == null || session.user.id != store.userId) {
          throw StateError(
            'Sign in with the account that created these sales.',
          );
        }
        String? reviewReason;
        try {
          final acknowledgment = await client
              .rpc('pos_sync_cash_sale', params: {'sale': payload})
              .setHeader('Authorization', 'Bearer ${session.accessToken}')
              .timeout(const Duration(seconds: 8));
          if (acknowledgment != id) {
            throw StateError('The server did not acknowledge this receipt.');
          }
        } on PostgrestException catch (error) {
          if ([
            '22023',
            '22P02',
            '23503',
            '23514',
            'PT409',
          ].contains(error.code)) {
            reviewReason = error.message;
          } else {
            await _defer(row, id);
            rethrow;
          }
        } catch (_) {
          await _defer(row, id);
          rethrow;
        }
        await store.finishUpload(id, reviewReason: reviewReason);
      }
      _checkIdentity();
      // The server may have committed a still-pending receipt. Keep its local
      // stock deduction against the previous snapshot until we have its reply.
      if (await store.hasPendingReceipts()) return SyncOutcome.queued;
      final role = await _refreshCatalog();
      if (['owner', 'manager', 'cashier'].contains(role)) {
        await _registerDevice(force: force);
      }
      return await store.hasPendingReceipts()
          ? SyncOutcome.queued
          : SyncOutcome.synchronized;
    } finally {
      _flights.remove(path);
      done.complete();
    }
  }

  Future<void> _defer(Map<String, Object?> row, String id) {
    final attempts = (row['upload_attempts'] as int) + 1;
    final index = (attempts - 1).clamp(0, _retrySeconds.length - 1);
    return store.deferUpload(
      id,
      attempts,
      _clock().add(Duration(seconds: _retrySeconds[index])),
    );
  }

  Future<void> _registerDevice({required bool force}) async {
    final lastCheck = int.tryParse(
      await store.meta('device_registration_checked_ms') ?? '',
    );
    final now = _clock().millisecondsSinceEpoch;
    if (!force &&
        lastCheck != null &&
        now >= lastCheck &&
        now - lastCheck < const Duration(minutes: 5).inMilliseconds) {
      return;
    }
    final device = await store.deviceId;
    if (isActive?.call() == false) return;
    final session = client.auth.currentSession;
    if (session == null || session.user.id != store.userId) return;
    try {
      final acknowledgment = await client
          .rpc(
            'pos_register_selling_device',
            params: {
              'p_business': store.businessId,
              'p_branch': store.branchId,
              'p_device': device,
            },
          )
          .setHeader('Authorization', 'Bearer ${session.accessToken}')
          .timeout(const Duration(seconds: 3));
      if (acknowledgment != device) return;
    } on PostgrestException catch (error) {
      // Development projects can still be on the previous schema.
      if (error.code != 'PGRST202') return;
    } on TimeoutException {
      return;
    } on ClientException {
      return;
    } on SocketException {
      return;
    }
    if (client.auth.currentUser?.id == store.userId) {
      await store.setMeta(
        'device_registration_checked_ms',
        '${_clock().millisecondsSinceEpoch}',
      );
    }
  }

  Future<({String role, ReceiptDetails? details})> _verifiedAccess({
    bool includeDetails = false,
  }) async {
    _checkIdentity();
    final requests = [
      client
          .from('pos_memberships')
          .select('role')
          .eq('business_id', store.businessId)
          .eq('user_id', store.userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 8)),
      client
          .from('pos_branches')
          .select()
          .eq('business_id', store.businessId)
          .eq('id', store.branchId)
          .maybeSingle()
          .timeout(const Duration(seconds: 8)),
      if (includeDetails)
        client
            .from('pos_businesses')
            .select()
            .eq('id', store.businessId)
            .maybeSingle()
            .timeout(const Duration(seconds: 8)),
    ];
    final List<Map<String, dynamic>?> access;
    try {
      access = await Future.wait(requests);
    } on PostgrestException catch (error) {
      // maybeSingle can surface the HTTP status rather than the SQLSTATE.
      if (error.code == '42501' || error.code == '403') {
        _checkIdentity();
        await store.setMeta('revoked', 'true');
      }
      rethrow;
    }
    _checkIdentity();
    final membership = access[0], branch = access[1];
    if (membership == null ||
        branch == null ||
        (includeDetails && access[2] == null)) {
      await store.setMeta('revoked', 'true');
      throw StateError(
        'Workspace access was removed. Pending records are retained.',
      );
    }
    _checkIdentity();
    final details = includeDetails
        ? ReceiptDetails.fromRows(access[2]!, branch)
        : null;
    details?.checkScope(store.businessId, store.branchId);
    return (role: membership['role'] as String, details: details);
  }

  Future<String> _refreshCatalog() async {
    _checkIdentity();
    // Page large catalogs explicitly; the server's default row cap is not a catalog limit.
    final rows = <Map<String, dynamic>>[];
    String? after;
    while (true) {
      var query = client
          .from('pos_item_stock')
          .select(
            'product_id,quantity,pos_items!inner(id,name,sku,price_cents,active,category_id,category:pos_categories(name))',
          )
          .eq('business_id', store.businessId)
          .eq('branch_id', store.branchId);
      if (after != null) query = query.gt('product_id', after);
      final page = await query
          .order('product_id')
          .limit(500)
          .timeout(const Duration(seconds: 8));
      rows.addAll(page);
      if (page.length < 500) break;
      final next = page.last['product_id'] as String;
      if (next == after) throw StateError('Catalog cursor did not advance.');
      after = next;
    }
    _checkIdentity();
    final access = await _verifiedAccess(includeDetails: true);
    await store.replaceSnapshot(
      [
        for (final row in rows)
          if ((row['pos_items'] as Map)['active'] == true)
            {
              'id': row['product_id'],
              'name': row['pos_items']['name'],
              'sku': row['pos_items']['sku'],
              'price_cents': row['pos_items']['price_cents'],
              'quantity': row['quantity'],
              'category_id': row['pos_items']['category_id'] ?? '',
              'category_name': row['pos_items']['category']?['name'] ?? '',
            },
      ],
      access.role,
      receiptDetails: access.details,
    );
    return access.role;
  }
}
