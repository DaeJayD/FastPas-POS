import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  setUpAll(() async {
    final font = Platform.environment['POS_TEST_FONT'];
    if (font == null) return;
    final bytes = await File(font).readAsBytes();
    for (final family in ['Roboto', 'Ahem']) {
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  Future<void> capture(WidgetTester tester, String name) async {
    final directory = Platform.environment['POS_SCREENSHOT_DIR'];
    if (directory != null) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(Uri.file('$directory/$name.png')),
      );
    }
  }

  late AccountFixture fixture;
  late SupabaseClient client;
  late List<http.Request> requests;
  bool missing = false, loseReply = false;
  int quantity = 10, destinationVersion = 0;
  Map? committed;
  Map<String, dynamic>? savedItem;
  late Map<String, List<Map<String, dynamic>>> labels;
  bool conflict = false;
  Future<Object?> Function(Map)? catalogReply;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fixture = AccountFixture();
    requests = [];
    missing = false;
    loseReply = false;
    quantity = 10;
    destinationVersion = 0;
    committed = null;
    savedItem = null;
    conflict = false;
    catalogReply = null;
    labels = {'brands': [], 'categories': [], 'families': []};
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
        if ((missing && path.contains('/rpc/')) ||
            (conflict && path.endsWith('/pos_post_stock'))) {
          return http.Response(
            jsonEncode({
              'code': missing ? 'PGRST202' : 'PT409',
              'message': 'unavailable',
            }),
            missing ? 404 : 409,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        if (path.endsWith('/pos_catalog_labels')) {
          result = {'business_id': 'business', ...labels};
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
              ...?savedItem,
            },
          ];
          if (catalogReply != null) result = await catalogReply!(body);
        } else if (path.endsWith('/pos_stock_history')) {
          result = [
            {
              'id': 'movement',
              'business_id': 'business',
              'branch_id': body['branch'],
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
        } else if (path.endsWith('/pos_save_catalog_label')) {
          final table = {
            'brand': 'brands',
            'category': 'categories',
            'family': 'families',
          }[body['kind']]!;
          final rows = labels[table]!;
          rows.removeWhere((row) => row['id'] == body['label_id']);
          rows.add({
            'id': body['label_id'],
            'business_id': body['business'],
            'name': body['label_name'],
            'active': body['enabled'],
            'version': (body['expected_version'] as int) + 1,
          });
          result = {};
        } else if (path.endsWith('/pos_save_catalog_item')) {
          final item = Map<String, dynamic>.from(body['item'] as Map);
          final variant = item['variant_label'] as String;
          savedItem = {
            ...item,
            'base_name': item['name'],
            'name': '${item['name']}${variant.isEmpty ? '' : ' · $variant'}',
            'version': (item['version'] as int) + 1,
          };
          result = {};
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
  Future<void> open(
    WidgetTester tester, {
    double width = 360,
    bool waitForJson = false,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
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
    if (waitForJson) {
      // Large SDK responses decode on a real isolate, outside the test clock.
      for (
        var i = 0;
        i < 100 && find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
    }
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Future<void> action(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip('Product actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> select(WidgetTester tester, String field, String option) async {
    final finder = find.byKey(ValueKey(field));
    await reveal(tester, finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Product edits preserve archived classifications and exact variant prices',
    (tester) async {
      for (final entry in {
        'brands': 'Acme',
        'categories': 'Clothing',
        'families': 'Shirts',
      }.entries) {
        labels[entry.key]!.add({
          'id': entry.key,
          'business_id': 'business',
          'name': entry.value,
          'active': true,
          'version': 1,
        });
      }
      await open(tester);
      await action(tester, 'Edit product');
      await tester.enterText(
        find.byKey(const ValueKey('Product name')),
        'Shirt',
      );
      await tester.enterText(find.byKey(const ValueKey('Price')), '19.99');
      await select(tester, 'Brand', 'Acme');
      await select(tester, 'Category', 'Clothing');
      await select(tester, 'Product family', 'Shirts');
      final variant = find.byKey(const ValueKey('Variant (size / color)'));
      await reveal(tester, variant);
      await tester.enterText(variant, 'Blue / Large');
      await capture(tester, 'catalog-product-editor');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final write = jsonDecode(
        requests
            .singleWhere((r) => r.url.path.endsWith('/pos_save_catalog_item'))
            .body,
      ) as Map;
      expect(write['business'], 'business');
      expect(write['item'], {
        'id': 'product',
        'version': 1,
        'name': 'Shirt',
        'sku': 'WATER',
        'price_cents': 1999,
        'active': true,
        'brand_id': 'brands',
        'category_id': 'categories',
        'family_id': 'families',
        'variant_label': 'Blue / Large',
      });
      expect(find.text('Shirt · Blue / Large'), findsOneWidget);
      labels['brands']!.single['active'] = false;
      await tester.tap(find.byTooltip('Refresh inventory'));
      await tester.pumpAndSettle();
      await action(tester, 'Edit product');
      expect(find.text('Acme (archived)'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('Product name')))
            .controller!
            .text,
        'Shirt',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('Price')))
            .controller!
            .text,
        '19.99',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Adding a product sends opening stock to the selected branch once',
    (tester) async {
      await open(tester);
      await select(tester, 'main', 'Second');
      await tester.tap(find.text('Add product'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('Product name')),
        'Notebook',
      );
      await tester.enterText(find.byKey(const ValueKey('SKU')), 'NOTE-1');
      await tester.enterText(find.byKey(const ValueKey('Price')), '12.34');
      final opening = find.byKey(const ValueKey('Opening stock'));
      await reveal(tester, opening);
      await tester.enterText(opening, '6');
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      await reveal(tester, opening);
      expect(tester.getRect(opening).bottom, lessThan(520));
      await capture(tester, 'catalog-add-product-keyboard');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final writes = requests
          .where((r) => r.url.path.endsWith('/pos_save_catalog_item'))
          .toList();
      expect(writes.length, 1);
      final body = jsonDecode(writes.single.body) as Map;
      final item = body['item'] as Map;
      expect(body['business'], 'business');
      expect(item['branch_id'], 'second');
      expect(item['version'], 0);
      expect(item['opening_quantity'], 6);
      expect(item['price_cents'], 1234);
      expect(item['name'], 'Notebook');
      expect(item['sku'], 'NOTE-1');
      expect(item['brand_id'], isNull);
      expect(item['family_id'], isNull);
      expect(body['request_id'], matches(RegExp(r'^[a-f0-9-]{36}$')));
      expect(find.text('Notebook'), findsOneWidget);
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Loading more products retains the first page and scopes both pages to the branch',
    (tester) async {
      Map<String, dynamic> row(int index) => {
        'id': 'product-$index',
        'business_id': 'business',
        'name': 'Product $index',
        'base_name': 'Product $index',
        'sku': 'SKU-$index',
        'price_cents': 100,
        'active': true,
        'version': 1,
        'quantity': 10,
        'stock_version': 1,
        'low_stock_threshold': 0,
        'variant_label': '',
      };
      catalogReply = (args) async =>
          args['page_offset'] == 0 ? List.generate(50, row) : [row(50)];
      await open(tester, waitForJson: true);
      await tester.scrollUntilVisible(
        find.text('Load more products'),
        500,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
        maxScrolls: 30,
      );
      await tester.tap(find.text('Load more products'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('51 products loaded.'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Product 50'), findsOneWidget);
      final reads = requests
          .where((r) => r.url.path.endsWith('/pos_catalog_items'))
          .map((r) => jsonDecode(r.body) as Map)
          .toList();
      expect(reads.map((r) => r['page_offset']), [0, 50]);
      expect(
        reads.every(
          (r) =>
              r['business'] == 'business' &&
              r['branch'] == 'main' &&
              r['page_size'] == 50,
        ),
        true,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('A variant requires a family before any product write', (
    tester,
  ) async {
    await open(tester);
    await action(tester, 'Edit product');
    final variant = find.byKey(const ValueKey('Variant (size / color)'));
    await reveal(tester, variant);
    await tester.enterText(variant, 'Large');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Choose a product family'), findsOneWidget);
    expect(
      requests.where((r) => r.url.path.endsWith('/pos_save_catalog_item')),
      isEmpty,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Classifications can be created and archived with the current version',
    (tester) async {
      await open(tester);
      final tab = find.widgetWithText(Tab, 'Classifications');
      await tester.ensureVisible(tab);
      await tester.tap(tab);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add classification'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('Name')), 'Drinks');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Drinks'), findsOneWidget);
      await tester.tap(find.byTooltip('Edit classification'));
      await tester.pumpAndSettle();
      await select(tester, 'Status', 'Archived');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Archived'), findsOneWidget);
      final writes = requests
          .where((r) => r.url.path.endsWith('/pos_save_catalog_label'))
          .map((r) => jsonDecode(r.body) as Map)
          .toList();
      expect(writes.length, 2);
      expect(writes[0]['kind'], 'category');
      expect(writes[0]['expected_version'], 0);
      expect(writes[1]['expected_version'], 1);
      expect(writes[1]['label_id'], writes[0]['label_id']);
      expect(writes[1]['enabled'], false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'A rejected stale count retains the counted quantity without changing stock',
    (tester) async {
      conflict = true;
      await open(tester);
      await action(tester, 'Set physical count');
      await tester.enterText(
        find.byKey(const ValueKey('Counted quantity')),
        '8',
      );
      await tester.enterText(
        find.byKey(const ValueKey('Reason')),
        'Shelf count',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This record changed. Cancel and refresh before trying again.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('Counted quantity')),
            )
            .controller!
            .text,
        '8',
      );
      expect(quantity, 10);
      expect(committed, isNull);
      await capture(tester, 'catalog-stale-count');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('An older search response cannot replace newer search results', (
    tester,
  ) async {
    final older = Completer<Object?>();
    catalogReply = (args) async =>
        args['search_text'] == 'old' ? older.future : [];
    await open(tester);
    final search = find.widgetWithText(TextField, 'Search name or SKU');
    await tester.enterText(search, 'old');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(search, 'latest');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('No matching products.'), findsOneWidget);
    older.complete([
      {'invalid': 'older response must be ignored'},
    ]);
    await tester.pumpAndSettle();
    expect(find.text('No matching products.'), findsOneWidget);
    expect(find.textContaining('Could not complete'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final width in [360.0, 1024.0]) {
    testWidgets('Catalog and movement history fit $width with larger text', (
      tester,
    ) async {
      await open(tester, width: width);
      expect(find.text('Water'), findsOneWidget);
      await capture(tester, 'catalog-$width');
      final tab = find.widgetWithText(Tab, 'Movements');
      await tester.ensureVisible(tab);
      await tester.tap(tab);
      await tester.pumpAndSettle();
      expect(find.text('Opening stock'), findsOneWidget);
      await capture(tester, 'movements-$width');
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
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Add product'),
            )
            .onPressed,
        isNull,
      );
      expect(
        requests.where((r) => r.url.path.endsWith('/pos_post_stock')),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
