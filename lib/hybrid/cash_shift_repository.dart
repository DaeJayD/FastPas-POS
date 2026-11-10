import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../workspaces/workspace_repository.dart';
import 'local_store.dart';

class CashShiftSummary {
  CashShiftSummary(Map<String, dynamic> row)
    : id = row['id'] as String,
      opening = row['opening_cents'] as int,
      sales = row['sales_cents'] as int,
      refunds = row['refunds_cents'] as int,
      cashIn = row['cash_in_cents'] as int,
      cashOut = row['cash_out_cents'] as int,
      expected = row['expected_cents'] as int,
      counted = row['counted_cents'] as int?,
      variance = row['variance_cents'] as int?,
      recentMovements = [
        for (final movement in row['recent_movements'] as List)
          (
            cents: movement['cents'] as int,
            reason: movement['reason'] as String,
          ),
      ];

  final String id;
  final int opening, sales, refunds, cashIn, cashOut, expected;
  final int? counted, variance;
  final List<({int cents, String reason})> recentMovements;
  bool get isOpen => counted == null;
}

enum CashShiftAction { open, cashIn, cashOut, close }

class CashShiftRepository {
  CashShiftRepository(this.client, this.store);
  final SupabaseClient client;
  final LocalStore store;

  void _checkAccount() {
    if (client.auth.currentUser?.id != store.userId) {
      throw const FormatException(
        'Account changed. Return to your businesses.',
      );
    }
  }

  Future<Map<String, String>> _scope() async {
    _checkAccount();
    final device = (await store.meta('device_id'))!;
    _checkAccount();
    return {
      'p_business': store.businessId,
      'p_branch': store.branchId,
      'p_device': device,
    };
  }

  Future<String?> pending() async {
    _checkAccount();
    final request = await store.pendingCashShift();
    _checkAccount();
    return request;
  }

  Future<CashShiftSummary?> status() async {
    final scope = await _scope();
    final previousShift = await store.meta('cash_shift_id');
    final drawer = await _read(scope);
    await store.updateCashShift(
      drawer?.isOpen == true ? drawer!.id : null,
      previousShift: previousShift,
    );
    return drawer;
  }

  Future<CashShiftSummary?> _read(Map<String, String> scope) async {
    _checkAccount();
    final row = await client
        .rpc('pos_cash_shift_status', params: scope)
        .timeout(const Duration(seconds: 12));
    _checkAccount();
    return row == null ? null : CashShiftSummary(row as Map<String, dynamic>);
  }

  Future<CashShiftSummary> submit(
    CashShiftAction action, {
    required String? activeShift,
    required int cents,
    required String reason,
  }) async {
    if ((action == CashShiftAction.open) != (activeShift == null)) {
      throw const FormatException('Refresh the cash shift before continuing.');
    }
    final scope = await _scope();
    final requestId = WorkspaceRepository.newRequestId();
    final params = <String, Object>{
      ...scope,
      'p_request': requestId,
      if (activeShift != null) 'p_shift': activeShift,
    };
    final String rpc;
    switch (action) {
      case CashShiftAction.open:
        rpc = 'pos_open_cash_shift';
        params['p_opening'] = cents;
      case CashShiftAction.close:
        rpc = 'pos_close_cash_shift';
        params['p_counted'] = cents;
      case CashShiftAction.cashIn:
      case CashShiftAction.cashOut:
        rpc = 'pos_post_cash_movement';
        params['p_cents'] = action == CashShiftAction.cashOut ? -cents : cents;
        params['p_reason'] = reason;
    }
    final request = jsonEncode({'rpc': rpc, 'params': params});
    await store.rememberCashShift(
      request,
      activeShift: activeShift,
      closing: action == CashShiftAction.close,
    );
    return _send(request);
  }

  Future<CashShiftSummary> retry() async {
    final request = await pending();
    if (request == null) {
      throw const FormatException('No saved cash shift request to retry.');
    }
    return _send(request);
  }

  Future<CashShiftSummary> _send(String request) async {
    final saved = jsonDecode(request) as Map<String, dynamic>;
    final rpc = saved['rpc'] as String;
    final params = saved['params'] as Map<String, dynamic>;
    final scope = await _scope();
    if (![
          'pos_open_cash_shift',
          'pos_close_cash_shift',
          'pos_post_cash_movement',
        ].contains(rpc) ||
        scope.entries.any((entry) => params[entry.key] != entry.value)) {
      throw const FormatException(
        'Saved request belongs to a different cash shift.',
      );
    }
    _checkAccount();
    try {
      final row = await client
          .rpc(rpc, params: params)
          .timeout(const Duration(seconds: 12));
      _checkAccount();
      final result = CashShiftSummary(row as Map<String, dynamic>);
      if (result.id != (params['p_shift'] ?? params['p_request']) ||
          (rpc == 'pos_close_cash_shift' && result.isOpen)) {
        throw const FormatException(
          'Could not verify the cash shift response. Retry the saved request.',
        );
      }
      await store.updateCashShift(
        result.isOpen ? result.id : null,
        previousShift: params['p_shift'] as String?,
        completedRequest: request,
      );
      return result;
    } on PostgrestException catch (error) {
      _checkAccount();
      if (['22023', 'PT409', '23505'].contains(error.code)) {
        final drawer = await _read(scope);
        await store.updateCashShift(
          drawer?.isOpen == true ? drawer!.id : null,
          previousShift: params['p_shift'] as String?,
          completedRequest: request,
        );
        throw const FormatException(
          'The shift request was rejected. Reload the current shift and check the details.',
        );
      }
      rethrow;
    }
  }
}
