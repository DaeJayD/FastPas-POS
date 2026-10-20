import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vasenizzpos/core/store_connection.dart';
import 'package:vasenizzpos/pos/product_home_screen.dart';
import 'package:vasenizzpos/preview/main.dart' as preview;
import 'package:vasenizzpos/preview/management_samples.dart';

void main() {
  setUp(enableManagementSamples);
  tearDown(() async {
    await StoreConnection.previewClient?.dispose();
    StoreConnection.previewClient = null;
  });
  for (final size in [const Size(360, 800), const Size(1024, 768)]) {
    testWidgets(
      'sample banner leaves correct route geometry at ${size.width}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        await tester.pumpWidget(const preview.FastPasPreviewApp());
        await tester.pumpAndSettle();
        final home = tester.element(find.byType(ProductHomeScreen));
        expect(
          MediaQuery.sizeOf(home).height,
          closeTo(tester.getSize(find.byType(Navigator)).height, .1),
        );
        expect(MediaQuery.paddingOf(home).top, 0);
        final add = find.byKey(const ValueKey('add-water'));
        await tester.ensureVisible(add);
        await tester.pumpAndSettle();
        await tester.tap(add);
        await tester.pumpAndSettle();
        expect(find.widgetWithText(FilledButton, 'Checkout'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
