import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vasenizzpos/core/fastpas_theme.dart';
import 'package:vasenizzpos/core/theme_preference.dart';
import 'package:vasenizzpos/reports/branch_cash_report.dart';
import 'package:vasenizzpos/reports/branch_cash_report_screen.dart';
import 'package:vasenizzpos/workspaces/workspace_repository.dart';

import 'support/account_fixture.dart';
import 'branch_cash_report_test.dart' show reportData;

void main() {
  late AccountFixture identity;
  late SupabaseClient client;
  var failDetails = false;
  var failReport = false;
  var empty = false;
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
  setUp(() async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    identity = AccountFixture();
    failDetails = false;
    failReport = false;
    empty = false;
    client = SupabaseClient(
      'https://overview-ui.invalid',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        final isReport = request.url.path.endsWith('/pos_branch_cash_report');
        if (failReport || failDetails && !isReport) {
          return http.Response(
            jsonEncode({'code': '42501', 'message': 'Access denied'}),
            403,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        final Object data;
        if (isReport) {
          data = reportData();
        } else if (request.url.path.endsWith('/pos_cash_sales')) {
          data = empty
              ? []
              : [
                  {
                    'id': 'sale',
                    'business_id': 'business',
                    'branch_id': 'branch',
                    'payload': {
                      'items': [
                        {
                          'product_id': 'coffee',
                          'name': 'Coffee beans',
                          'sku': 'COF',
                          'quantity': 8,
                        },
                      ],
                    },
                  },
                ];
        } else if (request.url.path.endsWith('/pos_item_stock')) {
          data = empty
              ? []
              : [
                  {
                    'product_id': 'coffee',
                    'business_id': 'business',
                    'branch_id': 'branch',
                    'quantity': 3,
                    'low_stock_threshold': 5,
                    'pos_items': {
                      'name': 'Coffee beans',
                      'sku': 'COF',
                      'active': true,
                    },
                  },
                ];
        } else {
          throw StateError('Unexpected UI test request');
        }
        return http.Response(
          jsonEncode(data),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    await client.auth.recoverSession(jsonEncode(identity.session()));
  });
  tearDown(() async {
    await client.dispose();
    await identity.close();
  });

  Future<void> open(WidgetTester tester, bool dark, Size size) async {
    SharedPreferences.setMockInitialValues({
      'fastpas.appearance': dark ? 'dark' : 'light',
    });
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      PosThemeHost(
        builder: (mode) => MaterialApp(
          theme: Volt.theme,
          darkTheme: Volt.darkTheme,
          themeMode: mode,
          debugShowCheckedModeBanner: false,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: BranchCashReportScreen(
            repository: BranchCashReportRepository(
              client,
              'business',
              AccountFixture.userId,
            ),
            branches: const [
              WorkspaceBranch(
                id: 'branch',
                businessId: 'business',
                name: 'Main branch',
              ),
            ],
          ),
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(LinearProgressIndicator).evaluate().isEmpty && i >= 2) {
        break;
      }
    }
    await tester.pumpAndSettle();
  }

  for (final dark in [false, true]) {
    for (final size in [
      const Size(320, 740),
      const Size(1024, 800),
      const Size(1440, 960),
    ]) {
      testWidgets(
        'Overview actual widgets fit $size in ${dark ? 'Forest' : 'Porcelain'}',
        (tester) async {
          await open(tester, dark, size);
          expect(find.text('Overview'), findsOneWidget);
          expect(find.text('₱15.00'), findsOneWidget);
          final directory = Platform.environment['POS_SCREENSHOT_DIR'];
          if (directory != null) {
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile(
                Uri.file(
                  '$directory/overview-${dark ? 'forest' : 'porcelain'}-${size.width.toInt()}.png',
                ),
              ),
            );
          }
          await tester.scrollUntilVisible(find.text('Top sellers'), 350);
          expect(
            find.text('Latest 1 synced receipts · units before returns'),
            findsOneWidget,
          );
          await tester.scrollUntilVisible(find.text('Low stock'), 250);
          expect(find.text('Low stock'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
    testWidgets(
      'Overview keeps authorized cash totals when supplementary data fails $dark',
      (tester) async {
        failDetails = true;
        await open(tester, dark, const Size(360, 800));
        expect(find.text('₱15.00'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Retry overview details').hitTestable(),
          300,
        );
        expect(
          find.textContaining('Overview details unavailable'),
          findsOneWidget,
        );
        failDetails = false;
        await tester.tap(find.text('Retry overview details'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Overview details unavailable'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
    testWidgets(
      'Overview empty details and denied report never show sample metrics $dark',
      (tester) async {
        empty = true;
        await open(tester, dark, const Size(360, 800));
        await tester.scrollUntilVisible(find.text('No synced sales'), 350);
        expect(find.text('No synced sales'), findsOneWidget);
        failReport = true;
        await tester.drag(find.byType(ListView).first, const Offset(0, 2000));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Run report'));
        await tester.pumpAndSettle();
        expect(find.text('₱15.00'), findsNothing);
        expect(
          find.text('A branch owner or assigned manager can view this report.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
