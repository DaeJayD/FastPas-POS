import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vasenizzpos/catalog/catalog_source.dart';
import 'package:vasenizzpos/core/fastpas_theme.dart';
import 'package:vasenizzpos/main.dart';
import 'package:vasenizzpos/pos/product_home_screen.dart';
import 'package:vasenizzpos/preview/sample_catalog.dart';

class FailingCatalog extends SampleCatalog {
  bool fail = true;
  @override
  Future<List<CatalogProduct>> products(String branchId) async {
    if (fail) throw StateError('Offline');
    return super.products(branchId);
  }
}

Future<void> openHome(WidgetTester tester,
    {CatalogSource? source,
    Size size = const Size(390, 844),
    double scale = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: Volt.theme,
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!),
    home: ProductHomeScreen(
        fullName: 'Alex Santos',
        role: 'owner',
        userId: 'preview',
        location: 'Main Branch',
        source: source ?? SampleCatalog()),
  ));
  await tester.pumpAndSettle();
}

Future<void> top(WidgetTester tester) async {
  final scrollable =
      tester.state<ScrollableState>(find.byType(Scrollable).first);
  scrollable.position.jumpTo(0);
  await tester.pumpAndSettle();
}

Future<void> add(WidgetTester tester, String id) async {
  final button = find.byKey(ValueKey('add-$id'));
  await tester.scrollUntilVisible(button, 180,
      scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sign-in validates empty fields without accessing the backend',
      (tester) async {
    await tester
        .pumpWidget(MaterialApp(theme: Volt.theme, home: const LoginScreen()));
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your username.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search and categories filter without losing the cart',
      (tester) async {
    await openHome(tester);
    await add(tester, 'water');
    await top(tester);
    await tester.enterText(
        find.byKey(const ValueKey('product-search')), 'ST-001');
    await tester.pumpAndSettle();
    expect(find.text('Ballpoint Pen'), findsOneWidget);
    expect(find.text('Bottled Water'), findsNothing);
    expect(find.text('₱25.00'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('product-search')), '');
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Food'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Food'));
    await tester.pumpAndSettle();
    expect(find.text('Butter Cookies'), findsOneWidget);
    expect(find.text('Bottled Water'), findsNothing);
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'All'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('remove-water')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('edited checkout quantities return to the same cart',
      (tester) async {
    await openHome(tester);
    await add(tester, 'water');
    await add(tester, 'water');
    await add(tester, 'cookies');
    expect(find.text('₱115.00'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Checkout'));
    await tester.pumpAndSettle();
    expect(find.text('Review order'), findsOneWidget);
    expect(find.text('₱128.80'), findsWidgets);
    await tester.tap(find.byTooltip('Remove one Bottled Water'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back to products'));
    await tester.pumpAndSettle();
    await top(tester);
    expect(find.text('Products'), findsOneWidget);
    expect(find.text('₱90.00'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'sample cash flow validates tender and produces a labeled receipt without Supabase',
      (tester) async {
    await openHome(tester);
    await add(tester, 'water');
    await tester.tap(find.widgetWithText(FilledButton, 'Checkout'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue to payment'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Preview receipt'));
    await tester.pumpAndSettle();
    expect(find.text('Please enter cash amount!'), findsOneWidget);
    await tester.tap(find.text('Exact'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Preview receipt'));
    await tester.pumpAndSettle();
    expect(find.text('Your receipt preview'), findsOneWidget);
    expect(find.text('Sample data only. No payment was recorded.'),
        findsOneWidget);
    expect(find.text('₱28.00'), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, 'Start a new sale'));
    await tester.pumpAndSettle();
    expect(find.text('Products'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Checkout'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'stock limit disables increment and branch changes require cart confirmation',
      (tester) async {
    await openHome(tester);
    for (var i = 0; i < 4; i++) {
      await add(tester, 'tissue');
    }
    final plus =
        tester.widget<IconButton>(find.byKey(const ValueKey('add-tissue')));
    expect(plus.onPressed, isNull);
    await top(tester);
    await tester.ensureVisible(find.text('Main Branch'));
    await tester.tap(find.text('Main Branch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('North Branch'));
    await tester.pumpAndSettle();
    expect(find.text('Switch branch?'), findsOneWidget);
    await tester.tap(find.text('Keep cart'));
    await tester.pumpAndSettle();
    expect(find.text('₱80.00'), findsWidgets);
    await tester.tap(find.text('Main Branch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('North Branch'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Switch branch'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Checkout'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed catalog can be retried and empty search can be cleared',
      (tester) async {
    final source = FailingCatalog();
    await openHome(tester, source: source);
    expect(find.text('Couldn’t load your catalog'), findsOneWidget);
    source.fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Bottled Water'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('product-search')), 'not-a-product');
    await tester.pumpAndSettle();
    expect(find.text('No matching products'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('Bottled Water'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(360, 800), const Size(1024, 768)]) {
    testWidgets('catalog and cart fit ${size.width.toInt()}px with larger text',
        (tester) async {
      await openHome(tester, size: size, scale: 1.3);
      await add(tester, 'water');
      await add(tester, 'cookies');
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Inventory').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('More').last);
      await tester.pumpAndSettle();
      expect(find.text('Your store'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
