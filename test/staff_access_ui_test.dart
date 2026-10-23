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
  final branchIds = <String>['main'];
  final assignments = <List<String>>[];
  bool failAssignment = false;
  bool oldSchema = false;
  @override
  Future<Map<String, dynamic>> staffAccess(String businessId) async => {
    'members': [
      {'user_id': 'owner', 'email': 'owner@example.test', 'role': 'owner'},
      {
        'user_id': 'staff',
        'email': 'staff@example.test',
        'role': 'cashier',
        if (!oldSchema) 'branch_ids': List<String>.of(branchIds),
      },
    ],
    if (!oldSchema)
      'branches': [
        {'id': 'main', 'name': 'Main branch'},
        {'id': 'other', 'name': 'Second branch'},
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

  @override
  Future<void> setStaffBranches(
    String businessId,
    String userId,
    List<String> branchIds,
  ) async {
    if (failAssignment) throw StateError('Denied');
    expect(businessId, 'business');
    expect(userId, 'staff');
    assignments.add(List<String>.of(branchIds));
    this.branchIds
      ..clear()
      ..addAll(branchIds);
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
  Future<void> tapControl(WidgetTester tester, Finder target) async {
    await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> open(
    WidgetTester tester,
    StaffFixture repository, {
    double width = 360,
  }) async {
    tester.view.physicalSize = Size(width, 800);
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

  for (final width in [360.0, 1024.0]) {
    testWidgets(
      'Branch assignment fits $width and saves only the selected branches',
      (tester) async {
        final repository = StaffFixture(client);
        await open(tester, repository, width: width);
        await tester.tap(find.text('Edit branch access'));
        await tester.pumpAndSettle();
        expect(find.byType(CheckboxListTile), findsNWidgets(2));
        await tapControl(
          tester,
          find.widgetWithText(CheckboxListTile, 'Main branch'),
        );
        await tapControl(
          tester,
          find.widgetWithText(CheckboxListTile, 'Second branch'),
        );
        await tapControl(tester, find.text('Save branches'));
        await tester.pumpAndSettle();
        expect(repository.assignments, [
          ['other'],
        ]);
        expect(find.text('Branches: Second branch'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('Cancelled branch edits do not change access', (tester) async {
    final repository = StaffFixture(client);
    await open(tester, repository);
    await tester.tap(find.text('Edit branch access'));
    await tester.pumpAndSettle();
    await tapControl(
      tester,
      find.widgetWithText(CheckboxListTile, 'Main branch'),
    );
    expect(find.textContaining('No branches selected.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.assignments, isEmpty);
    expect(find.text('Branches: Main branch'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Clearing branches preserves membership and shows no branch access',
    (tester) async {
      final repository = StaffFixture(client);
      await open(tester, repository);
      await tester.tap(find.text('Edit branch access'));
      await tester.pumpAndSettle();
      await tapControl(
        tester,
        find.widgetWithText(CheckboxListTile, 'Main branch'),
      );
      await tapControl(tester, find.text('Save branches'));
      await tester.pumpAndSettle();
      expect(repository.assignments, [<String>[]]);
      expect(find.text('No branch access'), findsOneWidget);
      expect(find.text('staff@example.test'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Changing accounts closes branch editor and cannot submit old staff access',
    (tester) async {
      final repository = StaffFixture(client);
      await open(tester, repository);
      await tester.tap(find.text('Edit branch access'));
      await tester.pumpAndSettle();
      await identity('other');
      await tester.pumpAndSettle();
      expect(find.text('Save branches'), findsNothing);
      expect(find.text('staff@example.test'), findsNothing);
      expect(repository.assignments, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Denied assignment clears stale staff and does not display success',
    (tester) async {
      final repository = StaffFixture(client)..failAssignment = true;
      await open(tester, repository);
      await tester.tap(find.text('Edit branch access'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save branches'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Could not update staff access.'),
        findsOneWidget,
      );
      expect(repository.assignments, isEmpty);
      expect(find.text('staff@example.test'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Older schema cannot accidentally submit an empty branch assignment',
    (tester) async {
      await open(tester, StaffFixture(client)..oldSchema = true);
      expect(find.text('Edit branch access'), findsNothing);
      expect(
        find.textContaining('Apply the staff branch-access migration'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
