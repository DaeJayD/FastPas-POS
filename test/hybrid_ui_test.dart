import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vasenizzpos/core/fastpas_theme.dart';
import 'package:vasenizzpos/hybrid/hybrid_pos_screen.dart';
import 'package:vasenizzpos/hybrid/local_store.dart';
import 'package:vasenizzpos/workspaces/workspace_repository.dart';

void main() {
  sqfliteFfiInit();
  late SupabaseClient client;
  late Directory directory;
  late LocalStore store;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('fastpas-hybrid-ui-');
    store = await LocalStore.open(
      userId: 'user',
      businessId: 'business',
      branchId: 'branch',
      directory: directory.path,
      factory: databaseFactoryFfi,
    );
    await store.replaceSnapshot([
      {
        'id': 'coffee',
        'name': 'Long product name for a coffee drink',
        'sku': 'COFFEE-001',
        'price_cents': 1250,
        'quantity': 5,
      },
    ], 'cashier');
    client = SupabaseClient(
      'https://example.supabase.co',
      'key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    String encode(Object o) =>
        base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
    final expiry =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000;
    await client.auth.recoverSession(
      jsonEncode({
        'access_token':
            '${encode({'alg': 'HS256'})}.${encode({'exp': expiry, 'sub': 'user'})}.sig',
        'refresh_token': 'test',
        'token_type': 'bearer',
        'expires_at': expiry,
        'user': {
          'id': 'user',
          'aud': 'authenticated',
          'app_metadata': {},
          'user_metadata': {},
          'created_at': '2026-10-21T00:00:00Z',
        },
      }),
    );
  });
  tearDownAll(() async {
    await client.dispose();
    await store.close();
    await directory.delete(recursive: true);
  });
  testWidgets('Offline cash selling fits a phone and saves a pending receipt', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: Volt.theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: HybridPosScreen(
          client: client,
          business: const BusinessWorkspace(
            id: 'business',
            name: 'A long business name',
            role: 'cashier',
          ),
          branch: const WorkspaceBranch(
            id: 'branch',
            businessId: 'business',
            name: 'Main branch',
          ),
          openStore: () async => store,
          synchronize: (_) async => throw const SocketException('Offline'),
        ),
      ),
    );
    Future<void> settleDatabase() async {
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
      }
    }

    await settleDatabase();
    await tester.pumpAndSettle();
    expect(find.text('Not synchronized · using saved data'), findsOneWidget);
    await tester.tap(find.byTooltip('Add one'));
    await tester.pump();
    await tester.tap(find.text('Cash checkout · ₱12.50'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 400));
    await settleDatabase();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Sale saved on this device'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Done'));
    await tester.pump(const Duration(milliseconds: 400));
    await settleDatabase();
    expect(
      (await tester.runAsync(store.receipts))!.single['status'],
      'pending',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await settleDatabase();
  });
}
