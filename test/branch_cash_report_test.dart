import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vasenizzpos/core/fastpas_theme.dart';
import 'package:vasenizzpos/reports/branch_cash_report.dart';
import 'package:vasenizzpos/workspaces/workspace_screen.dart';

import 'support/account_fixture.dart';

Map<String, dynamic> reportData() => {
  'business_id': 'business',
  'branch_id': 'branch',
  'timezone': 'Asia/Manila',
  'from_day': '2026-11-01',
  'through_day': '2026-11-02',
  'days': [
    {
      'day': '2026-11-01',
      'sale_count': 1,
      'gross_cents': 1999,
      'refund_count': 0,
      'refund_cents': 0,
      'shift_count': 0,
      'expected_cents': 0,
      'counted_cents': 0,
    },
    {
      'day': '2026-11-02',
      'sale_count': 0,
      'gross_cents': 0,
      'refund_count': 1,
      'refund_cents': 499,
      'shift_count': 1,
      'expected_cents': 1500,
      'counted_cents': 1499,
    },
  ],
};

void main() {
  test(
    'cash report totals and CSV keep exact cents and quote spreadsheet labels',
    () {
      final report = BranchCashReport(reportData());
      expect(report.totals.gross, 1999);
      expect(report.totals.net, 1500);
      expect(report.totals.variance, -1);
      final rows = report.csv('=Main, "North"').split('\r\n');
      expect(
        rows[1],
        '2026-11-01,"\'=Main, ""North""","Asia/Manila",PHP,1,19.99,0,0.00,19.99,0,0.00,0.00,0.00',
      );
      expect(
        rows[2],
        '2026-11-02,"\'=Main, ""North""","Asia/Manila",PHP,0,0.00,1,4.99,-4.99,1,15.00,14.99,-0.01',
      );
    },
  );

  testWidgets(
    'owners can open branch cash reports and late data is cleared on account change',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      late final AccountFixture fixture;
      late final SupabaseClient client;
      Completer<void>? delayed;
      final calls = <Map<String, dynamic>>[];
      await tester.runAsync(() async {
        fixture = AccountFixture();
        client = SupabaseClient(
          'https://example.supabase.co',
          'test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((request) async {
            Object response;
            switch (request.url.pathSegments.last) {
              case 'pos_memberships':
                response = [
                  {'business_id': 'business', 'role': 'owner'},
                ];
              case 'pos_businesses':
                response = [
                  {'id': 'business', 'name': 'Coffee shop'},
                ];
              case 'pos_branches':
                response = [
                  {
                    'id': 'branch',
                    'business_id': 'business',
                    'name': 'Main branch',
                  },
                ];
              case 'pos_branch_cash_report':
                calls.add(jsonDecode(request.body) as Map<String, dynamic>);
                await delayed?.future;
                response = reportData();
              default:
                fail('Unexpected request ${request.url.path}');
            }
            return http.Response(
              jsonEncode(response),
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        await client.auth.recoverSession(jsonEncode(fixture.session()));
      });
      addTearDown(client.dispose);
      addTearDown(fixture.close);
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: Volt.theme,
          home: WorkspaceScreen(client: client),
        ),
      );

      Future<void> waitFor(Finder target) async {
        for (var i = 0; i < 30 && target.evaluate().isEmpty; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(target, findsOneWidget);
        await tester.pump(const Duration(milliseconds: 350));
      }

      await waitFor(find.text('Coffee shop'));
      await tester.tap(find.text('Coffee shop'));
      await waitFor(find.text('Cash reports'));
      await tester.ensureVisible(find.text('Cash reports'));
      await tester.tap(find.text('Cash reports'));
      await waitFor(find.text('Net cash sales ₱15.00'));
      expect(calls.single, {
        'p_business': 'business',
        'p_branch': 'branch',
        'p_timezone': 'Asia/Manila',
        'p_from': null,
        'p_through': null,
      });
      expect(find.text('Drawer variance ₱-0.01'), findsOneWidget);
      expect(find.text('Save CSV'), findsOneWidget);

      delayed = Completer<void>();
      await tester.tap(find.text('Run report'));
      await tester.pump();
      expect(calls, hasLength(2));
      await tester.runAsync(
        () => client.auth.recoverSession(
          jsonEncode(fixture.session('10000000-0000-4000-8000-000000000002')),
        ),
      );
      delayed.complete();
      await waitFor(find.text('Account changed. Return to your businesses.'));
      expect(find.text('Net cash sales ₱15.00'), findsNothing);
      expect(find.text('Save CSV'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
