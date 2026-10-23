import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vasenizzpos/workspaces/workspace_repository.dart';

void main() {
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
