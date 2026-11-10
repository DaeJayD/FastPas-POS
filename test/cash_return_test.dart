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
import 'package:vasenizzpos/hybrid/local_store.dart';
import 'package:vasenizzpos/hybrid/receipt_history_screen.dart';

import 'support/account_fixture.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late LocalStore store;
  late SupabaseClient client;
  late AccountFixture identity;
  late List<Map<String, dynamic>> submissions;
  late bool loseResponse;

  Future<LocalStore> openStore() => LocalStore.open(
    userId: AccountFixture.userId,
    businessId: 'business',
    branchId: 'branch',
    directory: directory.path,
    factory: databaseFactoryFfi,
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fastpas-return-');
    store = await openStore();
    submissions = [];
    loseResponse = false;
    identity = AccountFixture();
    client = SupabaseClient(
      'https://example.supabase.co',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        final params = jsonDecode(request.body) as Map<String, dynamic>;
        Object result;
        if (request.url.path.endsWith('/pos_cash_return_options')) {
          result = [
            {
              'product_id': 'coffee',
              'name': 'Coffee',
              'sku': 'COFFEE',
              'unit_cents': 2500,
              'quantity': 2,
              'remaining_quantity': 2,
            },
          ];
        } else {
          expect(request.url.path, endsWith('/pos_record_cash_return'));
          submissions.add(params);
          if (loseResponse) throw http.ClientException('Reply lost');
          result = {'id': params['p_request'], 'total_cents': 2500};
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

  const items = <Map<String, Object>>[
    {'product_id': 'coffee', 'quantity': 1, 'restock': false},
  ];

  test(
    'an ambiguous return retains its exact request across a database reopen',
    () async {
      loseResponse = true;
      await expectLater(
        CashReturnRepository(client, store, 'sale').record('Damaged', items),
        throwsA(isA<http.ClientException>()),
      );
      await store.close();
      store = await openStore();
      final repository = CashReturnRepository(client, store, 'sale');
      await expectLater(
        repository.record('New request', items),
        throwsFormatException,
      );
      await client.auth.recoverSession(
        jsonEncode(identity.session('10000000-0000-4000-8000-000000000002')),
      );
      await expectLater(repository.retry(), throwsFormatException);
      expect(submissions, hasLength(1));
      await client.auth.recoverSession(jsonEncode(identity.session()));
      loseResponse = false;
      final result = await repository.retry();
      expect(submissions, hasLength(2));
      expect(submissions.last, submissions.first);
      expect(result.totalCents, 2500);
      expect(await repository.pending(), isNull);
    },
  );

  testWidgets(
    'a synced receipt opens cash return and records a selected unit',
    (tester) async {
      final sale = await tester.runAsync(() async {
        await store.replaceSnapshot([
          {
            'id': 'coffee',
            'name': 'Coffee',
            'sku': 'COFFEE',
            'price_cents': 2500,
            'quantity': 10,
          },
        ], 'owner');
        final id = await store.checkout({'coffee': 2}, 5000);
        await store.setStatus(id, 'synced');
        return id;
      });
      var syncs = 0;
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: Volt.theme,
          home: ReceiptHistoryScreen(
            client: client,
            store: store,
            branchName: 'Main',
            canRecordReturns: true,
            onSync: () async {
              syncs++;
            },
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

      final synced = find.text('₱50.00 · Synced');
      await waitFor(synced);
      await tester.tap(synced);
      await waitFor(find.text('Cash return'));
      await tester.tap(find.text('Cash return'));
      await waitFor(find.text('Return quantity'));
      await tester.enterText(find.byType(TextFormField), '1');
      final reason = find.widgetWithText(TextField, 'Return reason');
      await tester.ensureVisible(reason);
      await tester.enterText(reason, 'Damaged');
      await tester.pump();
      expect(find.text('Cash refund ₱25.00'), findsOneWidget);
      await tester.tap(find.text('Record return'));
      await waitFor(find.text('Return recorded'));
      expect(submissions.single['p_sale'], sale);
      expect(submissions.single['p_items'], items);
      expect(submissions.single['p_reason'], 'Damaged');
      await tester.tap(find.text('Done'));
      await waitFor(synced);
      expect(syncs, 1);
      final receipt = await tester.runAsync(() => store.receipt(sale!));
      expect(receipt!['total_cents'], 5000);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
