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

  Future<void> open(WidgetTester tester, {Widget? home}) async {
    tester.view.physicalSize = const Size(360, 740);
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
  }

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
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Cash must cover the total due.'), findsOneWidget);
      expect((await tester.runAsync(store.receipts))!, isEmpty);
      await tester.enterText(cash, '30.00');
      await tester.tap(find.text('Save'));
      await settleStore(tester);
      await tester.pump(const Duration(milliseconds: 350));
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
