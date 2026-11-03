import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vasenizzpos/catalog/catalog_screen.dart';
import 'package:vasenizzpos/core/fastpas_theme.dart';
import 'package:vasenizzpos/workspaces/workspace_repository.dart';

import 'support/account_fixture.dart';

void main() {
  late AccountFixture fixture;
  late SupabaseClient client;
  late List<http.Request> requests;
  bool missing = false, loseReply = false;
  int quantity = 10, destinationVersion = 0;
  Map? committed;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fixture = AccountFixture();
    requests = [];
    missing = false;
    loseReply = false;
    quantity = 10;
    destinationVersion = 0;
    committed = null;
    client = SupabaseClient(
      'https://example.supabase.co',
      'key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        Object? result;
        final body = request.body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(request.body) as Map;
        if (missing && path.contains('/rpc/')) {
          return http.Response(
            jsonEncode({'code': 'PGRST202', 'message': 'missing'}),
            404,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        if (path.endsWith('/pos_catalog_labels')) {
          result = {
            'business_id': 'business',
            'brands': [],
            'categories': [],
            'families': [],
          };
        } else if (path.endsWith('/pos_catalog_items')) {
          result = [
            {
              'id': 'product',
              'business_id': 'business',
              'name': 'Water',
              'base_name': 'Water',
              'sku': 'WATER',
              'price_cents': 2500,
              'active': true,
              'version': 1,
              'quantity': quantity,
              'stock_version': 1,
              'low_stock_threshold': 2,
              'variant_label': '',
              'brand_id': null,
              'category_id': null,
              'family_id': null,
            },
          ];
        } else if (path.endsWith('/pos_stock_history')) {
          result = [
            {
              'id': 'movement',
              'business_id': 'business',
              'branch_id': 'main',
              'product_name': 'Water',
              'sku': 'WATER',
              'kind': 'opening',
              'quantity_delta': 10,
              'before_quantity': 0,
              'after_quantity': 10,
              'reason': 'Opening stock',
              'created_at': '2026-11-03T00:00:00Z',
            },
          ];
        } else if (path.endsWith('/pos_branches')) {
          result = [
            {'id': 'main', 'business_id': 'business', 'name': 'Main'},
            {'id': 'second', 'business_id': 'business', 'name': 'Second'},
          ];
        } else if (path.endsWith('/pos_item_stock')) {
          result = {'stock_version': destinationVersion};
        } else if (path.endsWith('/pos_post_stock')) {
          if (committed == null) {
            committed = jsonDecode(jsonEncode(body)) as Map;
            quantity -= 3;
            destinationVersion = 2;
          } else {
            expect(body, committed);
          }
          if (loseReply) {
            loseReply = false;
            throw http.ClientException('reply lost');
          }
          result = {'quantity': quantity};
        } else {
          throw StateError('Unexpected request');
        }
        return http.Response(
          jsonEncode(result),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await client.auth.recoverSession(jsonEncode(fixture.session()));
  });
  tearDown(() async {
    await client.dispose();
    await fixture.close();
  });
  Future<void> open(WidgetTester tester, {double width = 360}) async {
    tester.view.physicalSize = Size(width, 800);
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
        home: CatalogScreen(
          client: client,
          business: const BusinessWorkspace(
            id: 'business',
            name: 'Shop',
            role: 'owner',
          ),
          branch: const WorkspaceBranch(
            id: 'main',
            businessId: 'business',
            name: 'Main',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [360.0, 1024.0]) {
    testWidgets('Catalog and movement history fit $width with larger text', (
      tester,
    ) async {
      await open(tester, width: width);
      expect(find.text('Water'), findsOneWidget);
      final tab = find.widgetWithText(Tab, 'Movements');
      await tester.ensureVisible(tab);
      await tester.tap(tab);
      await tester.pumpAndSettle();
      expect(find.text('Opening stock'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets(
    'A lost transfer reply retries the same request and destination version',
    (tester) async {
      await open(tester);
      loseReply = true;
      await tester.tap(find.byTooltip('Product actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transfer stock'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('Quantity')), '3');
      await tester.enterText(
        find.byKey(const ValueKey('Reason')),
        'Rebalance stock',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.text('Connection unavailable. Reconnect and try again.'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextFormField, 'Rebalance stock'),
        findsOneWidget,
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final writes = requests
          .where((r) => r.url.path.endsWith('/pos_post_stock'))
          .toList();
      expect(writes.length, 2);
      expect(jsonDecode(writes[0].body), jsonDecode(writes[1].body));
      expect(
        requests.where((r) => r.url.path.endsWith('/pos_item_stock')).length,
        1,
      );
      expect(find.text('7 in stock'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('Missing migration disables catalog mutations', (tester) async {
    missing = true;
    await open(tester);
    expect(
      find.textContaining('Catalog and inventory are not available yet'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Add product'),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'Account change closes a stock editor and prevents stale writes',
    (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Product actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Receive stock'));
      await tester.pumpAndSettle();
      await client.auth.recoverSession(
        jsonEncode(fixture.session('10000000-0000-4000-8000-000000000002')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Water'), findsNothing);
      expect(
        requests.where((r) => r.url.path.endsWith('/pos_post_stock')),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
