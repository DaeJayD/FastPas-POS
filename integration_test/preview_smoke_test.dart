import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vasenizzpos/preview/main.dart' as preview;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android sample sale and branch navigation', (tester) async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    preview.main();
    await tester.pumpAndSettle();
    expect(find.text('Products'), findsOneWidget);
    final water = find.byKey(const ValueKey('add-water'));
    await tapVisible(tester, water);
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Checkout'));
    expect(find.text('Review order'), findsOneWidget);
    await tapVisible(tester, find.text('Continue to payment'));
    await tapVisible(tester, find.text('Exact'));
    await tapVisible(tester, find.text('Preview receipt'));
    expect(find.text('Your receipt preview'), findsOneWidget);
    expect(find.text('₱28.00'), findsWidgets);
    await tapVisible(tester, find.text('Start a new sale'));
    await tapVisible(tester, find.text('More'));
    await tapVisible(tester, find.text('Branches & stock'));
    await tapVisible(tester, find.text('Branch Inventory'));
    expect(find.text('Select branch'), findsOneWidget);
    await tapVisible(tester, find.text('Main Branch'));
    expect(find.text('View Inventory'), findsOneWidget);
    await tapVisible(tester, find.text('View Inventory'));
    expect(find.text('Everyday'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
