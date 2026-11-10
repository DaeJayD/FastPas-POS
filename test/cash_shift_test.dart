import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vasenizzpos/core/fastpas_theme.dart';
import 'package:vasenizzpos/hybrid/cash_return_repository.dart';
import 'package:vasenizzpos/hybrid/cash_shift_repository.dart';
import 'package:vasenizzpos/hybrid/hybrid_pos_screen.dart';
import 'package:vasenizzpos/hybrid/local_store.dart';
import 'package:vasenizzpos/workspaces/workspace_repository.dart';

import 'support/account_fixture.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late LocalStore store;
  late SupabaseClient client;
  late AccountFixture identity;
  late List<Map<String, dynamic>> requests;
  Map<String, Object?>? drawer;
  String? loseReply;

  Future<LocalStore> openStore() => LocalStore.open(
    userId: AccountFixture.userId,
    businessId: 'business',
    branchId: 'branch',
    directory: directory.path,
    factory: databaseFactoryFfi,
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fastpas-shift-');
    store = await openStore();
    await store.replaceSnapshot([
      {
        'id': 'coffee',
        'name': 'Coffee',
        'sku': 'COFFEE',
        'price_cents': 2500,
        'quantity': 10,
      },
    ], 'owner');
    requests = [];
    drawer = null;
    loseReply = null;
    identity = AccountFixture();
    client = SupabaseClient(
      'https://example.supabase.co',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        final rpc = request.url.pathSegments.last;
        final params = jsonDecode(request.body) as Map<String, dynamic>;
        requests.add({'rpc': rpc, ...params});
        Object? result;
        switch (rpc) {
          case 'pos_cash_shift_status':
            result = drawer;
          case 'pos_open_cash_shift':
            result = drawer = {
              'id': params['p_request'],
              'opening_cents': params['p_opening'],
              'sales_cents': 0,
              'refunds_cents': 0,
              'cash_in_cents': 0,
              'cash_out_cents': 0,
              'expected_cents': params['p_opening'],
              'counted_cents': null,
              'variance_cents': null,
              'recent_movements': [],
            };
          case 'pos_record_shift_return':
            result = {'id': params['p_request'], 'total_cents': 2500};
          case 'pos_close_cash_shift':
            result = drawer = {
              ...drawer!,
              'counted_cents': params['p_counted'],
              'variance_cents':
                  (params['p_counted'] as int) -
                  (drawer!['expected_cents'] as int),
            };
          default:
            fail('Unexpected RPC $rpc');
        }
        if (loseReply == rpc) {
          loseReply = null;
          throw http.ClientException('Reply lost');
        }
        return http.Response(
          jsonEncode(result),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await client.auth.recoverSession(jsonEncode(identity.session()));
  });

  tearDown(() async {
    await client.dispose();
    await identity.close();
    await store.close();
    await directory.delete(recursive: true);
  });

  test('close waits for linked receipts and returns, and a lost close reply survives a reopen', () async {
    final unassigned = await store.checkout({'coffee': 1}, 2500);
    var repository = CashShiftRepository(client, store);
    expect(await repository.status(), isNull);
    final opened = await repository.submit(
      CashShiftAction.open,
      activeShift: null,
      cents: 10000,
      reason: '',
    );
    final sale = await store.checkout({'coffee': 1}, 2500);
    Future<CashShiftSummary> close() => repository.submit(
      CashShiftAction.close,
      activeShift: opened.id,
      cents: 9800,
      reason: '',
    );
    final payload =
        jsonDecode((await store.receipt(sale))['payload'] as String) as Map;
    expect(payload['cash_shift_id'], opened.id);
    await expectLater(close(), throwsFormatException);
    await store.setStatus(sale, 'blocked', error: 'Needs review');
    await expectLater(close(), throwsFormatException);
    await store.setStatus(sale, 'synced');

    final returns = CashReturnRepository(client, store, sale);
    loseReply = 'pos_record_shift_return';
    await expectLater(
      returns.record('Damaged', [
        {'product_id': 'coffee', 'quantity': 1, 'restock': false},
      ]),
      throwsA(isA<http.ClientException>()),
    );
    await expectLater(close(), throwsFormatException);
    final originalReturn = requests.last;
    expect(originalReturn['p_shift'], opened.id);
    expect(originalReturn['p_device'], payload['device_id']);
    await returns.retry();
    expect(requests.last, originalReturn);

    loseReply = 'pos_close_cash_shift';
    await expectLater(close(), throwsA(isA<http.ClientException>()));
    final originalClose = requests.last;
    await store.close();
    store = await openStore();
    repository = CashShiftRepository(client, store);
    await expectLater(
      store.checkout({'coffee': 1}, 2500),
      throwsFormatException,
    );
    final closed = await repository.retry();
    expect(requests.last, originalClose);
    expect(closed.isOpen, isFalse);
    expect(closed.variance, -200);
    expect(await repository.pending(), isNull);
    expect((await store.receipt(unassigned))['status'], 'pending');
    final next = await store.checkout({'coffee': 1}, 2500);
    expect(
      jsonDecode((await store.receipt(next))['payload'] as String),
      isNot(contains('cash_shift_id')),
    );
  });

  testWidgets(
    'selling screen opens and counts a cash shift on a phone layout',
    (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: Volt.theme,
          home: HybridPosScreen(
            client: client,
            business: const BusinessWorkspace(
              id: 'business',
              name: 'Shop',
              role: 'owner',
            ),
            branch: const WorkspaceBranch(
              id: 'branch',
              businessId: 'business',
              name: 'Main',
            ),
            openStore: () async => store,
            synchronize: (_) async {},
          ),
        ),
      );
      Future<void> waitFor(Finder target) async {
        for (var i = 0; i < 40; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump(const Duration(milliseconds: 100));
          if (target.evaluate().isNotEmpty) break;
        }
        expect(target, findsOneWidget);
        await tester.pump(const Duration(milliseconds: 350));
      }

      await waitFor(find.text('Connected · changes synchronized'));
      await tester.tap(find.byTooltip('Cash shift'));
      final open = find.widgetWithText(FilledButton, 'Open shift');
      await waitFor(open);
      await tester.enterText(
        find.widgetWithText(TextField, 'Opening cash'),
        '100.00',
      );
      await tester.tap(open);
      await waitFor(find.text('Shift open'));
      final closeChip = find.widgetWithText(ChoiceChip, 'Close shift');
      await tester.ensureVisible(closeChip);
      await tester.tap(closeChip);
      await tester.pump();
      final counted = find.widgetWithText(TextField, 'Counted cash');
      await tester.ensureVisible(counted);
      await tester.enterText(counted, '98.00');
      await tester.tap(find.widgetWithText(FilledButton, 'Close shift'));
      await waitFor(find.text('Last shift closed'));
      expect(find.text('Expected cash ₱100.00'), findsOneWidget);
      expect(find.text('Variance ₱-2.00'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
