import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vasenizzpos/core/fastpas_theme.dart';
import 'package:vasenizzpos/workspaces/staff_access_screen.dart';
import 'package:vasenizzpos/workspaces/workspace_repository.dart';

class StaffFixture extends WorkspaceRepository {
  StaffFixture(super.client);
  int changes = 0;
  @override
  Future<Map<String, dynamic>> staffAccess(String businessId) async => {
    'members': [
      {'user_id': 'owner', 'email': 'owner@example.test', 'role': 'owner'},
      {'user_id': 'staff', 'email': 'staff@example.test', 'role': 'cashier'},
    ],
    'invitations': [],
  };
  @override
  Future<void> changeStaffAccess(
    String businessId,
    String userId,
    String? role,
  ) async {
    changes++;
  }
}

void main() {
  late SupabaseClient client;
  Future<void> identity(String id) async {
    String encode(Object o) =>
        base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
    final expiry =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000;
    await client.auth.recoverSession(
      jsonEncode({
        'access_token':
            '${encode({'alg': 'HS256'})}.${encode({'sub': id, 'exp': expiry})}.sig',
        'refresh_token': 'test',
        'expires_at': expiry,
        'token_type': 'bearer',
        'user': {
          'id': id,
          'aud': 'authenticated',
          'app_metadata': {},
          'user_metadata': {},
          'created_at': '2026-10-21T00:00:00Z',
        },
      }),
    );
  }

  setUpAll(() {
    client = SupabaseClient(
      'https://example.supabase.co',
      'key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });
  setUp(() => identity('owner'));
  tearDownAll(() => client.dispose());
  Future<void> open(WidgetTester tester, StaffFixture repository) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: Volt.theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: StaffAccessScreen(
          repository: repository,
          business: const BusinessWorkspace(
            id: 'business',
            name: 'Store A',
            role: 'owner',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Staff access fits phone and cancelled removal leaves access unchanged',
    (tester) async {
      final repository = StaffFixture(client);
      await open(tester, repository);
      expect(find.text('Owner'), findsOneWidget);
      expect(find.byType(DropdownButton<String>), findsOneWidget);
      await tester.ensureVisible(find.text('Remove access'));
      await tester.tap(find.text('Remove access'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep access'));
      await tester.pumpAndSettle();
      expect(repository.changes, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('Switching accounts clears staff identities and blocks refresh', (
    tester,
  ) async {
    await open(tester, StaffFixture(client));
    expect(find.text('staff@example.test'), findsOneWidget);
    await identity('other');
    await tester.pumpAndSettle();
    expect(find.text('staff@example.test'), findsNothing);
    await tester.tap(find.byTooltip('Refresh staff'));
    await tester.pumpAndSettle();
    expect(find.text('staff@example.test'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
