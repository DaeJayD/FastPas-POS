import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vasenizzpos/core/fastpas_theme.dart';
import 'package:vasenizzpos/hybrid/hybrid_pos_screen.dart';
import 'package:vasenizzpos/hybrid/local_store.dart';
import 'package:vasenizzpos/hybrid/receipt_history_screen.dart';
import 'package:vasenizzpos/workspaces/workspace_repository.dart';

import 'support/account_fixture.dart';

Future<void> settleStore(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
  }
}

Future<void> settleHistory(WidgetTester tester) async {
  // Route construction and SQLite use different clocks in widget tests.
  // Allow real database work even before the route becomes onstage.
  for (var i = 0; i < 40; i++) {
    await settleStore(tester);
    await tester.pump(const Duration(milliseconds: 100));
    if (i >= 2 && find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      break;
    }
  }
  expect(find.byType(CircularProgressIndicator), findsNothing);
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();
  late AccountFixture account;
  late LocalStore store;
  late Directory directory;

  setUpAll(() async {
    final fontFile = Platform.environment['POS_TEST_FONT'];
    if (fontFile != null) {
      final bytes = await File(fontFile).readAsBytes();
      for (final family in ['Roboto', 'Ahem']) {
        await (FontLoader(
          family,
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });

  Future<void> capture(WidgetTester tester, String name) async {
    final directory = Platform.environment['POS_SCREENSHOT_DIR'];
    if (directory == null) return;
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(Uri.file('$directory/$name.png')),
    );
  }

  setUp(() async {
    account = AccountFixture();
    await account.client.auth.recoverSession(jsonEncode(account.session()));
    directory = await Directory.systemTemp.createTemp('fastpas-polish-');
    store = await LocalStore.open(
      userId: AccountFixture.userId,
      businessId: 'business',
      branchId: 'branch',
      directory: directory.path,
      factory: databaseFactoryFfi,
    );
    await store.replaceSnapshot([
      {
        'id': 'coffee',
        'name': 'Coffee',
        'sku': 'COFFEE',
        'price_cents': 2500,
        'quantity': 10,
      },
    ], 'owner');
  });
  tearDown(() async {
    await store.close();
    await account.close();
    await directory.delete(recursive: true);
  });

  Widget screen({Future<void> Function(LocalStore)? sync}) => HybridPosScreen(
    client: account.client,
    business: const BusinessWorkspace(
      id: 'business',
      name: 'Test',
      role: 'owner',
    ),
    branch: const WorkspaceBranch(
      id: 'branch',
      businessId: 'business',
      name: 'Main branch',
    ),
    openStore: () async => store,
    synchronize: sync ?? (_) async {},
  );

  Future<void> open(
    WidgetTester tester, {
    Widget? home,
    Size size = const Size(360, 740),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: Volt.theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: home ?? screen(),
      ),
    );
    await settleStore(tester);
    await tester.pump(const Duration(milliseconds: 250));
    for (
      var i = 0;
      i < 40 && find.text('Opening saved store…').evaluate().isNotEmpty;
      i++
    ) {
      await settleStore(tester);
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  for (final size in [const Size(360, 740), const Size(1024, 800)]) {
    testWidgets(
      'Selling Home fits ${size.width} with large text and a persistent cart',
      (tester) async {
        await tester.runAsync(
          () => store.replaceSnapshot([
            for (var i = 0; i < 8; i++)
              {
                'id': 'item-$i',
                'name': i == 0
                    ? 'Coffee beans with an especially long product variant name'
                    : 'Product $i',
                'sku': 'SKU-$i',
                'price_cents': 1999,
                'quantity': i == 7 ? 0 : 10,
                'category_id': i < 4 ? 'drinks' : 'food',
                'category_name': i < 4 ? 'Drinks' : 'Food',
              },
          ], 'owner'),
        );
        await open(tester, size: size);
        try {
          await tester.pumpAndSettle();
          await capture(
            tester,
            size.width < 600 ? 'selling-home-phone' : 'selling-home-tablet',
          );
          await tester.ensureVisible(find.byTooltip('Add one').first);
          await tester.tap(find.byTooltip('Add one').first);
          await tester.pumpAndSettle();
          expect(find.text('1 item in cart'), findsOneWidget);
          expect(find.text('Cash checkout · ₱19.99'), findsOneWidget);
          await tester.scrollUntilVisible(
            find.text('Product 7'),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text('Cash checkout · ₱19.99'), findsOneWidget);
          expect(
            tester
                .getRect(
                  find.widgetWithText(FilledButton, 'Cash checkout · ₱19.99'),
                )
                .bottom,
            lessThanOrEqualTo(size.height),
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await settleStore(tester);
        }
      },
    );
  }

  testWidgets('Local search matches name and SKU without losing the cart', (
    tester,
  ) async {
    await tester.runAsync(
      () => store.replaceSnapshot([
        {
          'id': 'coffee',
          'name': 'Coffee',
          'sku': 'COFFEE',
          'price_cents': 2500,
          'quantity': 10,
        },
        {
          'id': 'tea',
          'name': 'Green tea',
          'sku': 'TEA-02',
          'price_cents': 1999,
          'quantity': 0,
        },
      ], 'owner'),
    );
    await open(
      tester,
      home: screen(sync: (_) async => throw const SocketException('Offline')),
    );
    try {
      await tester.tap(find.byTooltip('Add one').first);
      await tester.pumpAndSettle();
      final search = find.widgetWithText(TextField, 'Search products or SKU');
      await tester.enterText(search, ' tea-02 ');
      await tester.pumpAndSettle();
      expect(find.text('Green tea'), findsOneWidget);
      expect(find.text('Coffee'), findsNothing);
      expect(find.text('Out of stock'), findsOneWidget);
      expect(find.text('Cash checkout · ₱25.00'), findsOneWidget);
      await tester.enterText(search, 'no matching product');
      await tester.pumpAndSettle();
      expect(find.text('No products match your search'), findsOneWidget);
      expect(find.text('Cash checkout · ₱25.00'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('Coffee'), findsOneWidget);
      expect(find.text('Cash checkout · ₱25.00'), findsOneWidget);
      expect((await tester.runAsync(store.receipts))!, isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await settleStore(tester);
    }
  });

  testWidgets('Offline category filtering keeps hidden cart selections', (
    tester,
  ) async {
    await tester.runAsync(
      () => store.replaceSnapshot([
        {
          'id': 'coffee',
          'name': 'Coffee',
          'sku': 'COFFEE',
          'price_cents': 2500,
          'quantity': 10,
          'category_id': 'drinks',
          'category_name': 'Drinks',
        },
        {
          'id': 'bread',
          'name': 'Bread',
          'sku': 'BRD',
          'price_cents': 1000,
          'quantity': 5,
          'category_id': 'food',
          'category_name': 'Food',
        },
      ], 'owner'),
    );
    await open(
      tester,
      home: screen(sync: (_) async => throw const SocketException('Offline')),
    );
    try {
      await tester.tap(find.byTooltip('Add one').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Drinks'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Drinks'));
      await tester.pumpAndSettle();
      expect(find.text('Coffee'), findsOneWidget);
      expect(find.text('Bread'), findsNothing);
      expect(find.text('Cash checkout · ₱10.00'), findsOneWidget);
      await tester.ensureVisible(
        find.widgetWithText(ChoiceChip, 'All products'),
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'All products'));
      await tester.pumpAndSettle();
      expect(find.text('Bread'), findsOneWidget);
      expect(find.text('Cash checkout · ₱10.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await settleStore(tester);
    }
  });

  testWidgets(
    'Product dialog keeps labels separated on a phone with keyboard',
    (tester) async {
      await open(tester);
      try {
        await tester.tap(find.text('Add product'));
        await tester.pumpAndSettle();
        await capture(tester, 'add-product');
        final fields = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        );
        expect(fields, findsNWidgets(4));
        for (var i = 1; i < 4; i++) {
          final previous = tester.getRect(fields.at(i - 1));
          final current = tester.getRect(fields.at(i));
          expect(
            current.top - previous.bottom,
            greaterThanOrEqualTo(12),
            reason: 'Adjacent fields must leave room for floating labels.',
          );
        }
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        await tester.ensureVisible(fields.last);
        await tester.tap(fields.last);
        await tester.enterText(fields.last, '20');
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      } finally {
        tester.view.resetViewInsets();
        await tester.pumpWidget(const SizedBox.shrink());
        await settleStore(tester);
      }
    },
  );

  testWidgets('Back navigation does not wait for background synchronization', (
    tester,
  ) async {
    final sync = Completer<void>();
    await open(
      tester,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => screen(sync: (_) => sync.future),
              ),
            ),
            child: const Text('Open branch'),
          ),
        ),
      ),
    );
    try {
      await tester.tap(find.text('Open branch'));
      await tester.pump(const Duration(milliseconds: 350));
      await settleStore(tester);
      expect(find.text('Syncing…'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(HybridPosScreen), findsNothing);
      expect(
        find.text('Open branch'),
        findsOneWidget,
        reason: 'Slow network work must not trap the user in a branch.',
      );
    } finally {
      sync.complete();
      await settleStore(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await settleStore(tester);
    }
  });

  testWidgets('A late sync cannot replace the account-change warning', (
    tester,
  ) async {
    final sync = Completer<void>();
    await open(tester, home: screen(sync: (_) => sync.future));
    try {
      await tester.runAsync(
        () => account.client.auth.recoverSession(
          jsonEncode(account.session('10000000-0000-4000-8000-000000000002')),
        ),
      );
      sync.complete();
      await settleStore(tester);
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        find.text('Account changed. Return to your businesses.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Add product'),
            )
            .onPressed,
        isNull,
      );
    } finally {
      if (!sync.isCompleted) sync.complete();
      await tester.pumpWidget(const SizedBox.shrink());
      await settleStore(tester);
    }
  });

  testWidgets(
    'Large catalog can reach its final product with bounded visible cards',
    (tester) async {
      await tester.runAsync(
        () => store.replaceSnapshot(
          List.generate(
            1000,
            (i) => {
              'id': 'item-$i',
              'name': 'Product ${i.toString().padLeft(4, '0')}',
              'sku': 'SKU-$i',
              'price_cents': 2500,
              'quantity': 10,
            },
          ),
          'owner',
        ),
      );
      await open(tester);
      try {
        expect(
          find.byType(Card).evaluate().length,
          lessThan(30),
          reason: 'Offscreen catalog rows should not be built eagerly.',
        );
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Product 0999'),
          20000,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 20,
        );
        expect(find.text('Product 0999'), findsOneWidget);
        expect(find.byType(Card).evaluate().length, lessThan(30));
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await settleStore(tester);
      }
    },
  );

  testWidgets(
    'Cash review shows frozen lines and live exact change before confirmation',
    (tester) async {
      await open(tester);
      try {
        await tester.tap(find.byTooltip('Add one'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Add one'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cash checkout · ₱50.00'));
        await tester.pumpAndSettle();
        expect(find.text('2 × Coffee'), findsOneWidget);
        await tester.enterText(find.byType(TextFormField), '60.00');
        await tester.pumpAndSettle();
        expect(find.text('Change ₱10.00'), findsOneWidget);
        expect((await tester.runAsync(store.receipts))!, isEmpty);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await settleStore(tester);
        expect(find.text('Cash checkout · ₱50.00'), findsOneWidget);
        expect((await tester.runAsync(store.receipts))!, isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await settleStore(tester);
      }
    },
  );

  testWidgets(
    'A changed price cannot silently replace the reviewed payment total',
    (tester) async {
      await open(tester);
      try {
        await tester.tap(find.byTooltip('Add one'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cash checkout · ₱25.00'));
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => store.replaceSnapshot([
            {
              'id': 'coffee',
              'name': 'Coffee',
              'sku': 'COFFEE',
              'price_cents': 2000,
              'quantity': 10,
            },
          ], 'owner'),
        );
        await tester.tap(find.text('Complete sale'));
        await settleStore(tester);
        await tester.pump(const Duration(milliseconds: 350));
        expect((await tester.runAsync(store.receipts))!, isEmpty);
        expect(
          find.text(
            'Items changed. Cancel and review your cart before paying.',
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField))
              .controller!
              .text,
          '25.00',
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await settleStore(tester);
      }
    },
  );

  testWidgets('Repeated checkout entry opens only one payment form', (
    tester,
  ) async {
    await open(tester);
    try {
      await tester.tap(find.byTooltip('Add one'));
      await tester.pumpAndSettle();
      final begin = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Cash checkout · ₱25.00'),
          )
          .onPressed!;
      begin();
      begin();
      await tester.pumpAndSettle();
      expect(find.text('Cash payment', skipOffstage: false), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await settleStore(tester);
    }
  });

  testWidgets(
    'An account change closes the previous payment without saving it',
    (tester) async {
      await open(tester);
      try {
        await tester.tap(find.byTooltip('Add one'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cash checkout · ₱25.00'));
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => account.client.auth.recoverSession(
            jsonEncode(account.session('10000000-0000-4000-8000-000000000002')),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect((await tester.runAsync(store.receipts))!, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await settleStore(tester);
      }
    },
  );

  testWidgets('Changed stock requests review and keeps the payment editable', (
    tester,
  ) async {
    await open(tester);
    try {
      await tester.tap(find.byTooltip('Add one'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cash checkout · ₱25.00'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => store.replaceSnapshot([
          {
            'id': 'coffee',
            'name': 'Coffee',
            'sku': 'COFFEE',
            'price_cents': 2500,
            'quantity': 0,
          },
        ], 'owner'),
      );
      await tester.tap(find.text('Complete sale'));
      await settleStore(tester);
      await tester.pumpAndSettle();
      expect(
        find.text('Items changed. Cancel and review your cart before paying.'),
        findsOneWidget,
      );
      expect((await tester.runAsync(store.receipts))!, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await settleStore(tester);
    }
  });

  testWidgets('A saved checkout receipt closes when the account changes', (
    tester,
  ) async {
    await open(tester);
    try {
      await tester.tap(find.byTooltip('Add one'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cash checkout · ₱25.00'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Complete sale'));
      await settleStore(tester);
      await tester.pump(const Duration(milliseconds: 350));
      for (
        var i = 0;
        i < 40 && find.text('Sale saved on this device').evaluate().isEmpty;
        i++
      ) {
        await settleStore(tester);
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Sale saved on this device'), findsOneWidget);
      await tester.runAsync(
        () => account.client.auth.recoverSession(
          jsonEncode(account.session('10000000-0000-4000-8000-000000000002')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await settleStore(tester);
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(AlertDialog), findsNothing);
      expect((await tester.runAsync(store.receipts))!.length, 1);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await settleStore(tester);
    }
  });

  testWidgets(
    'Clear cart removes selections without recording a sale or changing stock',
    (tester) async {
      await open(tester);
      try {
        await tester.tap(find.byTooltip('Add one'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Clear cart'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Cash checkout · ₱0.00'),
              )
              .onPressed,
          isNull,
        );
        expect((await tester.runAsync(store.receipts))!, isEmpty);
        expect((await tester.runAsync(store.products))!.single['quantity'], 10);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await settleStore(tester);
      }
    },
  );

  testWidgets(
    'Receipt history filters review sales without rewriting their payloads',
    (tester) async {
      final ids = await tester.runAsync(() async {
        final first = await store.checkout({'coffee': 1}, 2500);
        final second = await store.checkout({'coffee': 1}, 2500);
        await store.setStatus(first, 'synced');
        await store.setStatus(second, 'blocked', error: 'Catalog changed');
        return [first, second];
      });
      final original = (await tester.runAsync(
        () => store.receipt(ids![1]),
      ))!['payload'];
      await open(tester);
      try {
        await tester.tap(find.byTooltip('Saved receipts'));
        await settleHistory(tester);
        await tester.ensureVisible(
          find.widgetWithText(ChoiceChip, 'Needs review'),
        );
        await tester.tap(find.widgetWithText(ChoiceChip, 'Needs review'));
        await settleHistory(tester);
        expect(find.text('₱25.00 · Needs review'), findsOneWidget);
        expect(find.text('₱25.00 · Synced'), findsNothing);
        await tester.tap(find.text('₱25.00 · Needs review'));
        await settleStore(tester);
        await tester.pumpAndSettle();
        expect(find.text('Receipt · Needs review'), findsOneWidget);
        expect(find.textContaining('Catalog changed'), findsWidgets);
        expect(
          (await tester.runAsync(() => store.receipt(ids![1])))!['payload'],
          original,
        );
        expect((await tester.runAsync(store.products))!.single['quantity'], 8);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await settleStore(tester);
      }
    },
  );

  testWidgets('Opening history after an account change shows no previous records or endless loader', (tester) async {
    await tester.runAsync(() => store.checkout({'coffee': 1}, 2500));
    await tester.runAsync(() => account.client.auth.recoverSession(jsonEncode(account.session('10000000-0000-4000-8000-000000000002'))));
    await open(tester, home: ReceiptHistoryScreen(client: account.client, store: store, branchName: 'Main branch', onSync: () async {}));
    try {
      expect(find.text('Account changed. Return to your businesses.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('₱25.00'), findsNothing);
      expect((await tester.runAsync(store.receipts))!.length, 1);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await settleStore(tester);
    }
  });

  testWidgets('Receipt history loads older receipts on demand', (tester) async {
    final ids = await tester.runAsync(() async {
      await store.replaceSnapshot([
        {
          'id': 'coffee',
          'name': 'Coffee',
          'sku': 'COFFEE',
          'price_cents': 2500,
          'quantity': 40,
        },
      ], 'owner');
      final ids = <String>[];
      for (var i = 0; i < 31; i++) {
        ids.add(await store.checkout({'coffee': 1}, 2500));
      }
      return ids;
    });
    await open(tester);
    try {
      await tester.tap(find.byTooltip('Saved receipts'));
      await settleHistory(tester);
      await tester.scrollUntilVisible(
        find.text('Load more receipts'),
        10000,
        maxScrolls: 10,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(ids!.first), findsNothing);
      await tester.ensureVisible(find.text('Load more receipts'));
      await tester.tap(find.text('Load more receipts'));
      await settleHistory(tester);
      await tester.scrollUntilVisible(
        find.text(ids.first),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(ids.first), findsOneWidget);
      expect(find.text('Load more receipts'), findsNothing);
      expect((await tester.runAsync(store.receiptCounts))!.total, 31);
      expect((await tester.runAsync(store.products))!.single['quantity'], 9);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await settleStore(tester);
    }
  });

  testWidgets('An opened saved receipt closes when its account changes', (
    tester,
  ) async {
    await tester.runAsync(() => store.checkout({'coffee': 1}, 2500));
    await open(tester);
    try {
      await tester.tap(find.byTooltip('Saved receipts'));
      await settleHistory(tester);
      final receipt = find.text('₱25.00 · Pending upload');
      await tester.scrollUntilVisible(
        receipt,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(tester.element(receipt), alignment: .5);
      await tester.pumpAndSettle();
      await tester.tap(receipt);
      for (
        var i = 0;
        i < 40 && find.text('Receipt · Pending upload').evaluate().isEmpty;
        i++
      ) {
        await settleStore(tester);
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(find.text('Receipt · Pending upload'), findsOneWidget);
      await tester.runAsync(
        () => account.client.auth.recoverSession(
          jsonEncode(account.session('10000000-0000-4000-8000-000000000002')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect((await tester.runAsync(store.receipts))!.length, 1);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await settleStore(tester);
    }
  });

  testWidgets('Cash dialog validates in place above the phone keyboard', (
    tester,
  ) async {
    await open(tester);
    try {
      await tester.tap(find.byTooltip('Add one'));
      await tester.pumpAndSettle();
      await capture(tester, 'selling');
      await tester.tap(find.text('Cash checkout · ₱25.00'));
      await tester.pumpAndSettle();
      await capture(tester, 'cash-payment');
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      final cash = find.byType(TextFormField);
      await tester.enterText(cash, '1.00');
      await tester.tap(find.text('Complete sale'));
      await tester.pumpAndSettle();
      expect(find.text('Cash must cover the total due.'), findsOneWidget);
      expect((await tester.runAsync(store.receipts))!, isEmpty);
      await tester.enterText(cash, '30.00');
      await tester.tap(find.text('Complete sale'));
      await settleStore(tester);
      await tester.pump(const Duration(milliseconds: 350));
      for (
        var i = 0;
        i < 40 && find.text('Sale saved on this device').evaluate().isEmpty;
        i++
      ) {
        await settleStore(tester);
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Sale saved on this device'), findsOneWidget);
      expect(find.textContaining('Change ₱5.00'), findsOneWidget);
      expect((await tester.runAsync(store.receipts))!.length, 1);
      expect(tester.takeException(), isNull);
    } finally {
      tester.view.resetViewInsets();
      await tester.pumpWidget(const SizedBox.shrink());
      await settleStore(tester);
    }
  });

  testWidgets(
    'A product form from a previous account cannot submit after an account switch',
    (tester) async {
      await open(tester);
      try {
        await tester.tap(find.text('Add product'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const ValueKey('Name')), 'Tea');
        await tester.enterText(find.byKey(const ValueKey('SKU')), 'TEA');
        await tester.enterText(find.byKey(const ValueKey('Price')), '25.00');
        await tester.runAsync(
          () => account.client.auth.recoverSession(
            jsonEncode(account.session('10000000-0000-4000-8000-000000000002')),
          ),
        );
        await tester.pump();
        await tester.tap(find.text('Save'));
        await tester.pump(const Duration(milliseconds: 350));
        await settleStore(tester);
        expect(account.calls('/pos_add_item'), isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await settleStore(tester);
      }
    },
  );
}
