import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vasenizzpos/core/fastpas_theme.dart';
import 'package:vasenizzpos/workspaces/workspace_screen.dart';

import 'support/account_fixture.dart';

void main() {
  late AccountFixture fixture;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fixture = AccountFixture();
  });
  tearDown(() => fixture.close());

  Future<void> reveal(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: Volt.theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.3),
            viewInsets: const EdgeInsets.only(bottom: 280),
          ),
          child: child!,
        ),
        home: WorkspaceScreen(client: fixture.client, account: fixture.account),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [360.0, 1024.0]) {
    testWidgets(
      'Recovery form fits width $width above keyboard and finishes before showing businesses',
      (tester) async {
        await tester.runAsync(fixture.recover);
        await open(tester, width);
        expect(find.text('Choose a new password'), findsOneWidget);
        expect(find.text('Your businesses'), findsNothing);
        expect(fixture.calls('/pos_businesses'), isEmpty);
        final password = find.widgetWithText(TextField, 'New password');
        final confirmation = find.widgetWithText(
          TextField,
          'Confirm new password',
        );
        await reveal(tester, password);
        await tester.enterText(password, 'password1');
        await reveal(tester, confirmation);
        await tester.enterText(confirmation, 'different');
        await reveal(tester, find.text('Update password'));
        await tester.tap(find.text('Update password'));
        await tester.pumpAndSettle();
        await reveal(tester, find.text('The passwords do not match.'));
        expect(find.text('The passwords do not match.'), findsOneWidget);
        expect(fixture.calls('/user'), isEmpty);
        await reveal(tester, confirmation);
        await tester.enterText(confirmation, 'password1');
        await reveal(tester, find.text('Update password'));
        await tester.tap(find.text('Update password'));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView), const Offset(0, 1000));
        await tester.pumpAndSettle();
        expect(find.text('Your businesses'), findsOneWidget);
        expect(fixture.calls('/user').length, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'Reset and verification resend validate email and show generic notices',
    (tester) async {
      await open(tester, 360);
      await reveal(tester, find.text('Forgot password?'));
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Enter a valid email address.'));
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(fixture.requests, isEmpty);
      await tester.enterText(
        find.byType(TextField).at(0),
        'owner@example.test',
      );
      await reveal(tester, find.text('Forgot password?'));
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      expect(fixture.calls('/recover').length, 1);
      await reveal(tester, find.textContaining('If the account exists'));
      expect(find.textContaining('If the account exists'), findsOneWidget);
      await reveal(tester, find.text('Resend verification email'));
      await tester.tap(find.text('Resend verification email'));
      await tester.pumpAndSettle();
      expect(fixture.calls('/resend').length, 1);
      await reveal(tester, find.textContaining('If verification is needed'));
      expect(find.textContaining('If verification is needed'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Weak registration password is rejected without an Auth request',
    (tester) async {
      await open(tester, 360);
      await reveal(tester, find.text('Create an account'));
      await tester.tap(find.text('Create an account'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).at(0),
        'owner@example.test',
      );
      await tester.enterText(find.byType(TextField).at(1), 'short');
      await reveal(tester, find.text('Sign up'));
      await tester.tap(find.text('Sign up'));
      await tester.pumpAndSettle();
      await reveal(
        tester,
        find.text('Use at least 8 characters for your password.'),
      );
      expect(
        find.text('Use at least 8 characters for your password.'),
        findsOneWidget,
      );
      expect(fixture.requests, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
