import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vasenizzpos/workspaces/workspace_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/account_fixture.dart';

void main() {
  test(
    'Business discovery starts independent reads without a second network wait',
    () async {
      SharedPreferences.setMockInitialValues({});
      final release = Completer<void>();
      final paths = <String>[];
      final fixture = AccountFixture();
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          await release.future;
          return http.Response(
            jsonEncode(
              request.url.path.endsWith('pos_memberships')
                  ? [
                      {'business_id': 'b1', 'role': 'owner'},
                    ]
                  : [
                      {'id': 'b1', 'name': 'Test'},
                    ],
            ),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await client.auth.recoverSession(jsonEncode(fixture.session()));
      final loading = WorkspaceRepository(client).businesses();
      try {
        await Future<void>.delayed(Duration.zero);
        expect(
          paths,
          containsAll(['/rest/v1/pos_memberships', '/rest/v1/pos_businesses']),
          reason: 'Business loading should need one network round-trip window, not two.',
        );
      } finally {
        release.complete();
        final businesses = await loading;
        expect(businesses.single.role, 'owner');
        await client.dispose();
        await fixture.close();
      }
    },
  );
  test('Branch permissions retain business and member scope, including an explicit empty list', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          'null',
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    try {
      final repository = WorkspaceRepository(client);
      await repository.setStaffBranches('business-a', 'staff-a', ['branch-a']);
      await repository.setStaffBranches('business-a', 'staff-a', []);
      expect(
        requests.map((r) => r.url.path),
        everyElement('/rest/v1/rpc/pos_set_staff_branches'),
      );
      expect(jsonDecode(requests.first.body), {
        'business': 'business-a',
        'member': 'staff-a',
        'branches': ['branch-a'],
      });
      expect(jsonDecode(requests.last.body), {
        'business': 'business-a',
        'member': 'staff-a',
        'branches': <String>[],
      });
    } finally {
      await client.dispose();
    }
  });
}
