import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vasenizzpos/core/fastpas_theme.dart';
import 'package:vasenizzpos/workspaces/business_settings_screen.dart';
import 'package:vasenizzpos/workspaces/workspace_repository.dart';

import 'support/account_fixture.dart';

void main() {
  setUpAll(() async {
    final fontFile = Platform.environment['POS_TEST_FONT'];
    if (fontFile == null) return;
    final bytes = await File(fontFile).readAsBytes();
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
    if (directory == null) return;
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(Uri.file('$directory/$name.png')),
    );
  }

  late AccountFixture fixture;
  late SupabaseClient client;
  late Map<String, dynamic> data;
  late List<http.Request> requests;
  bool loseBranchReply = false,
      conflict = false,
      denied = false,
      missing = false;
  setUp(() async {
    fixture = AccountFixture();
    requests = [];
    loseBranchReply = false;
    conflict = false;
    denied = false;
    missing = false;
    data = {
      'business': {
        'id': 'business',
        'name': 'Corner shop',
        'address': 'Cagayan de Oro',
        'contact_phone': '',
        'contact_email': 'shop@example.test',
        'receipt_footer': 'Come again',
        'settings_version': 1,
      },
      'branches': [
        {
          'id': 'branch',
          'business_id': 'business',
          'name': 'Main',
          'address': 'Uptown',
          'settings_version': 1,
        },
      ],
    };
    data = jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
    client = SupabaseClient(
      'https://example.supabase.co',
      'key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        final body = jsonDecode(request.body) as Map;
        Object? result;
        var status = 200;
        if (denied || missing || conflict) {
          status = denied
              ? 403
              : missing
              ? 404
              : 400;
          result = {
            'code': denied
                ? '42501'
                : missing
                ? 'PGRST202'
                : '40001',
            'message': 'Unavailable',
          };
        } else if (request.url.path.endsWith('/pos_business_settings')) {
          result = data;
        } else if (request.url.path.endsWith('/pos_create_branch')) {
          final branches = data['branches'] as List;
          if (!branches.any((b) => b['id'] == body['request_id'])) {
            branches.add({
              'id': body['request_id'],
              'business_id': body['business'],
              'name': body['branch_name'],
              'address': body['branch_address'],
              'settings_version': 1,
            });
          }
          if (loseBranchReply) {
            loseBranchReply = false;
            throw http.ClientException('Reply lost');
          }
          result = body['request_id'];
        } else if (request.url.path.endsWith('/pos_update_business')) {
          final business = data['business'] as Map;
          business.addAll({
            'name': body['business_name'],
            'address': body['business_address'],
            'contact_phone': body['phone_number'],
            'contact_email': body['email_address'],
            'receipt_footer': body['footer'],
            'settings_version': 2,
          });
          result = 2;
        } else if (request.url.path.endsWith('/pos_update_branch')) {
          final branch = (data['branches'] as List).firstWhere(
            (b) => b['id'] == body['branch'],
          );
          branch.addAll({
            'name': body['branch_name'],
            'address': body['branch_address'],
            'settings_version': 2,
          });
          result = 2;
        } else {
          throw StateError('Unexpected request');
        }
        return http.Response(
          jsonEncode(result),
          status,
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
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        theme: Volt.theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: BusinessSettingsScreen(
          repository: WorkspaceRepository(client),
          business: const BusinessWorkspace(
            id: 'business',
            name: 'Corner shop',
            role: 'owner',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  for (final width in [360.0, 1024.0]) {
    testWidgets(
      'Settings and receipt preview fit width $width with larger text',
      (tester) async {
        await open(tester, width: width);
        expect(find.text('Corner shop'), findsOneWidget);
        await capture(tester, 'settings-$width');
        await reveal(tester, find.text('Receipt preview'));
        await tester.tap(find.text('Receipt preview'));
        await tester.pumpAndSettle();
        expect(find.textContaining('SAMPLE · Main'), findsOneWidget);
        expect(find.textContaining('Come again'), findsOneWidget);
        await capture(tester, 'receipt-$width');
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Edit business details'),
          -120,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.text('Edit business details'));
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await tester.pumpAndSettle();
        expect(find.text('Save').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture(tester, 'business-editor-$width');
        await tester.tap(find.text('Cancel'));
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets('Branch retry preserves its request identity and typed values', (
    tester,
  ) async {
    await open(tester);
    loseBranchReply = true;
    await tester.tap(find.widgetWithText(FilledButton, 'Add branch'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('Branch name')),
      'Downtown',
    );
    await tester.enterText(
      find.byKey(const ValueKey('Branch address')),
      'City center',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Could not complete this action'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextFormField, 'Downtown'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final writes = requests
        .where((r) => r.url.path.endsWith('/pos_create_branch'))
        .toList();
    expect(writes.length, 2);
    expect(
      (jsonDecode(writes[0].body) as Map)['request_id'],
      (jsonDecode(writes[1].body) as Map)['request_id'],
    );
    expect((data['branches'] as List).length, 2);
    expect(find.text('Downtown'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Version conflict retains business edits for review', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Edit business details'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('Business name')),
      'My updated shop',
    );
    conflict = true;
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await reveal(
      tester,
      find.textContaining('Settings changed on another device'),
    );
    expect(
      find.textContaining('Settings changed on another device'),
      findsOneWidget,
    );
    expect((data['business'] as Map)['name'], 'Corner shop');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'Business save sends its version and reloads the updated profile',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Edit business details'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('Business name')),
        'Updated shop',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Updated shop'), findsOneWidget);
      final request = requests.singleWhere(
        (r) => r.url.path.endsWith('/pos_update_business'),
      );
      expect((jsonDecode(request.body) as Map)['expected_version'], 1);
      expect((jsonDecode(request.body) as Map)['business'], 'business');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('Editing a branch retains its business and branch identity', (
    tester,
  ) async {
    await open(tester);
    await reveal(tester, find.text('Edit branch'));
    await tester.tap(find.text('Edit branch'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('Branch name')),
      'Renamed branch',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Renamed branch'), findsOneWidget);
    final request = requests.singleWhere(
      (r) => r.url.path.endsWith('/pos_update_branch'),
    );
    expect(jsonDecode(request.body), {
      'business': 'business',
      'branch': 'branch',
      'expected_version': 1,
      'branch_name': 'Renamed branch',
      'branch_address': 'Uptown',
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'Account change closes settings editor and blocks stale submission',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Edit business details'));
      await tester.pumpAndSettle();
      await client.auth.recoverSession(
        jsonEncode(fixture.session('10000000-0000-4000-8000-000000000002')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.text('Account changed. Return to your businesses.'),
        findsOneWidget,
      );
      expect(
        requests.where((r) => r.url.path.endsWith('/pos_update_business')),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Missing migration disables settings without exposing editable defaults',
    (tester) async {
      missing = true;
      await open(tester);
      expect(
        find.textContaining('Business settings are not available yet'),
        findsOneWidget,
      );
      expect(find.text('Edit business details'), findsNothing);
      expect(find.text('Add branch'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('Revoked Owner access clears settings on refresh', (
    tester,
  ) async {
    await open(tester);
    denied = true;
    await tester.tap(find.byTooltip('Refresh settings'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Owner access is required'), findsOneWidget);
    expect(find.text('Corner shop'), findsNothing);
    expect(find.text('Edit business details'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
