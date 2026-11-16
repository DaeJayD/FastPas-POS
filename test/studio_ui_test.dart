import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vasenizzpos/core/fastpas_theme.dart';
import 'package:vasenizzpos/core/theme_preference.dart';
import 'package:vasenizzpos/hybrid/checkout_cart.dart';
import 'package:vasenizzpos/hybrid/selling_product_card.dart';

const product = <String, Object?>{
  'id': 'coffee',
  'name': 'Coffee beans',
  'sku': 'COF',
  'price_cents': 2500,
  'quantity': 3,
};

void main() {
  test('Semantic text and warning roles are readable in both themes', () {
    for (final p in [PosColors.forest, PosColors.porcelain]) {
      for (final pair in [
        [p.text, p.surface],
        [p.muted, p.surface],
        [p.warning, p.warningSurface],
        [p.accentText, p.accent],
      ]) {
        final values = pair.map((c) => c.computeLuminance()).toList()..sort();
        expect(
          (values[1] + .05) / (values[0] + .05),
          greaterThanOrEqualTo(4.5),
        );
      }
    }
  });

  testWidgets('Theme selection persists without clearing a live cart', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'fastpas.appearance': 'light'});
    Widget app() => PosThemeHost(
      builder: (mode) => MaterialApp(
        theme: Volt.theme,
        darkTheme: Volt.darkTheme,
        themeMode: mode,
        home: const _CartState(),
      ),
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byTooltip('Switch to Forest dark'), findsOneWidget);
    await tester.tap(find.byTooltip('Add to cart'));
    await tester.pump();
    await tester.tap(find.byTooltip('Switch to Forest dark'));
    await tester.pumpAndSettle();
    expect(find.text('Cart: 1'), findsOneWidget);
    expect(
      (await SharedPreferences.getInstance()).getString('fastpas.appearance'),
      'dark',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byTooltip('Switch to Porcelain light'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    for (final size in [
      const Size(320, 640),
      const Size(760, 360),
      const Size(1024, 800),
    ]) {
      testWidgets(
        'Cart controls fit $size in ${dark ? 'Forest' : 'Porcelain'} with large text',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var quantity = 1;
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? Volt.darkTheme : Volt.theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.6),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: Scaffold(
                body: StatefulBuilder(
                  builder: (context, update) => CheckoutCart(
                    products: const [product],
                    cart: {'coffee': quantity},
                    total: 2500 * quantity,
                    locked: false,
                    allowed: true,
                    status: 'Not synchronized · using saved data',
                    pending: 2,
                    blocked: 1,
                    onQuantity: (_, delta) => update(() => quantity += delta),
                    onClear: () {},
                    onCheckout: () {},
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final add = find.byTooltip('Add one');
          await tester.ensureVisible(add);
          await tester.pumpAndSettle();
          await tester.tap(add);
          await tester.pumpAndSettle();
          expect(find.text('2'), findsOneWidget);
          expect(
            find.textContaining('2 pending · 1 need review'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets(
      'Product stock, disabled controls and reduced motion in both themes $dark',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? Volt.darkTheme : Volt.theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  child: SellingProductCard(
                    product: product,
                    quantity: 0,
                    onAdd: null,
                    onRemove: null,
                  ),
                ),
              ),
            ),
          ),
        );
        expect(find.text('Only 3 left'), findsOneWidget);
        expect(
          tester
              .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add))
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<AnimatedContainer>(find.byType(AnimatedContainer))
              .duration,
          Duration.zero,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _CartState extends StatefulWidget {
  const _CartState();
  @override
  State<_CartState> createState() => _CartStateState();
}

class _CartStateState extends State<_CartState> {
  int count = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(actions: const [ThemeSwitch()]),
    body: Column(
      children: [
        Text('Cart: $count'),
        IconButton(
          tooltip: 'Add to cart',
          onPressed: () => setState(() => count++),
          icon: const Icon(Icons.add),
        ),
      ],
    ),
  );
}
