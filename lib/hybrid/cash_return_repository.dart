import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../workspaces/workspace_repository.dart';
import 'local_store.dart';

class CashReturnLine {
  CashReturnLine(Map<String, dynamic> row)
    : id = row['product_id'] as String,
      name = row['name'] as String,
      sku = row['sku'] as String,
      unitCents = row['unit_cents'] as int,
      sold = row['quantity'] as int,
      remaining = row['remaining_quantity'] as int;

  final String id, name, sku;
  final int unitCents, sold, remaining;
}

class CashReturnResult {
  CashReturnResult(Map<String, dynamic> row)
    : id = row['id'] as String,
      totalCents = row['total_cents'] as int;
  final String id;
  final int totalCents;
}

class CashReturnRepository {
  CashReturnRepository(this.client, this.store, this.saleId);
  final SupabaseClient client;
  final LocalStore store;
  final String saleId;

  Map<String, String> get _scope => {
    'p_business': store.businessId,
    'p_branch': store.branchId,
    'p_sale': saleId,
  };

  void _checkAccount() {
    if (client.auth.currentUser?.id != store.userId) {
      throw const FormatException(
        'Account changed. Return to your businesses.',
      );
    }
  }

  Future<List<CashReturnLine>> options() async {
    _checkAccount();
    final rows = await client
        .rpc('pos_cash_return_options', params: _scope)
        .timeout(const Duration(seconds: 12));
    _checkAccount();
    return (rows as List)
        .map((row) => CashReturnLine(row as Map<String, dynamic>))
        .toList();
  }

  Future<String?> pending() async {
    _checkAccount();
    final saved = await store.pendingCashReturn(saleId);
    _checkAccount();
    return saved;
  }

  Future<CashReturnResult> record(
    String reason,
    List<Map<String, Object>> items,
  ) async {
    _checkAccount();
    final request = jsonEncode({
      ..._scope,
      'p_request': WorkspaceRepository.newRequestId(),
      'p_reason': reason,
      'p_items': items,
    });
    await store.rememberCashReturn(saleId, request);
    return _submit(request);
  }

  Future<CashReturnResult> retry() async {
    final saved = await pending();
    if (saved == null) {
      throw const FormatException('No saved return request to retry.');
    }
    return _submit(saved);
  }

  Future<CashReturnResult> _submit(String request) async {
    final params = jsonDecode(request) as Map<String, dynamic>;
    if (_scope.entries.any((entry) => params[entry.key] != entry.value)) {
      throw const FormatException(
        'Saved return belongs to a different receipt.',
      );
    }
    _checkAccount();
    try {
      final row = await client
          .rpc('pos_record_cash_return', params: params)
          .timeout(const Duration(seconds: 12));
      _checkAccount();
      final result = CashReturnResult(row as Map<String, dynamic>);
      if (result.id != params['p_request'] || result.totalCents < 0) {
        throw const FormatException(
          'Could not verify the return response. Retry the saved request.',
        );
      }
      await store.clearCashReturn(saleId, request);
      return result;
    } on PostgrestException catch (error) {
      _checkAccount();
      // A validated rejection means the RPC made no change. Connectivity,
      // deployment and access failures keep the original request recoverable.
      if (error.code == 'PT409' || error.code == '22023') {
        await store.clearCashReturn(saleId, request);
        throw const FormatException(
          'Return details changed or are invalid. Reload the receipt and check the remaining quantities.',
        );
      }
      rethrow;
    }
  }
}
