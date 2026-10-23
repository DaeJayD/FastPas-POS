import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vasenizzpos/workspaces/workspace_account.dart';

import 'support/account_fixture.dart';

void main() {
  late AccountFixture fixture;
  setUp(() => fixture = AccountFixture());
  tearDown(() => fixture.close());

  test(
    'Invalid email and weak registration passwords fail before contacting Auth',
    () async {
      await expectLater(
        fixture.account.signUp('invalid', 'long-password'),
        throwsFormatException,
      );
      await expectLater(
        fixture.account.signUp('owner@example.test', 'short'),
        throwsFormatException,
      );
      await expectLater(
        fixture.account.signIn('owner@example.test', ''),
        throwsFormatException,
      );
      expect(fixture.requests, isEmpty);
    },
  );
  test('Password reset sends the mobile callback and creates an SDK PKCE challenge', () async {
    await fixture.account.sendPasswordReset(' owner@example.test ');
    final request = fixture.calls('/recover').single;
    final body = jsonDecode(request.body) as Map;
    expect(
      request.url.queryParameters['redirect_to'],
      WorkspaceAccount.callbackUrl,
    );
    expect(body['email'], 'owner@example.test');
    expect(body['code_challenge_method'], 's256');
    expect(body['code_challenge'], isNotEmpty);
    expect(fixture.storage.values.values.single, endsWith('/passwordRecovery'));
  });
  test(
    'Verification resend uses the same registered mobile callback',
    () async {
      await fixture.account.resendVerification('owner@example.test');
      final request = fixture.calls('/resend').single;
      expect((jsonDecode(request.body) as Map)['type'], 'signup');
      expect(
        request.url.queryParameters['redirect_to'],
        WorkspaceAccount.callbackUrl,
      );
    },
  );
  test(
    'SDK recovery callback gates new-password validation and successful update',
    () async {
      await fixture.recover();
      expect(fixture.account.recoveringPassword, isTrue);
      expect(fixture.storage.values, isEmpty);
      await expectLater(
        fixture.account.finishRecovery('password1', 'different'),
        throwsFormatException,
      );
      await expectLater(
        fixture.account.finishRecovery('short', 'short'),
        throwsFormatException,
      );
      expect(fixture.calls('/user'), isEmpty);
      await fixture.account.finishRecovery('password1', 'password1');
      expect(fixture.account.recoveringPassword, isFalse);
      expect(fixture.client.auth.currentUser!.id, AccountFixture.userId);
      expect(
        (jsonDecode(fixture.calls('/user').single.body) as Map)['password'],
        'password1',
      );
    },
  );
  test('Normal sign-up confirmation cannot turn into recovery through a URL parameter', () async {
    await fixture.account.signUp('owner@example.test', 'password1');
    final succeeded = await fixture.account.openAuthLink(
      Uri.parse(
        '${WorkspaceAccount.callbackUrl}?code=signup-code&type=recovery',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(succeeded, isTrue);
    expect(fixture.account.recoveringPassword, isFalse);
    await expectLater(
      fixture.account.finishRecovery('password2', 'password2'),
      throwsStateError,
    );
  });
  test('Concurrent duplicate callbacks exchange a code once', () async {
    await fixture.account.sendPasswordReset('owner@example.test');
    final uri = Uri.parse('${WorkspaceAccount.callbackUrl}?code=recovery-code');
    expect(
      await Future.wait([
        fixture.account.openAuthLink(uri),
        fixture.account.openAuthLink(uri),
      ]),
      [true, false],
    );
    expect(fixture.calls('/token').length, 1);
  });
  test('Initial-link recovery survives before a screen subscribes', () async {
    await fixture.account.sendPasswordReset('owner@example.test');
    final uri = Uri.parse('${WorkspaceAccount.callbackUrl}?code=initial-code');
    final stream = StreamController<Uri>.broadcast();
    final ready = Completer<void>();
    fixture.account.addListener(() {
      if (fixture.account.recoveringPassword && !ready.isCompleted) {
        ready.complete();
      }
    });
    fixture.account.attachLinks(stream.stream, Future.value(uri));
    await ready.future.timeout(const Duration(seconds: 3));
    stream.add(uri);
    await Future<void>.delayed(Duration.zero);
    expect(fixture.calls('/token').length, 1);
    await stream.close();
  });
  test(
    'Only the exact callback destination with a code is processed',
    () async {
      for (final text in [
        'https://example.test/?code=x',
        'fastpas://other?code=x',
        'fastpas://auth-callback/unexpected?code=x',
        'fastpas://user@auth-callback?code=x',
        'fastpas://auth-callback:123?code=x',
        WorkspaceAccount.callbackUrl,
      ]) {
        expect(await fixture.account.openAuthLink(Uri.parse(text)), isFalse);
      }
      expect(fixture.requests, isEmpty);
    },
  );
  test('An expired code does not open recovery or create a session', () async {
    await fixture.account.sendPasswordReset('owner@example.test');
    fixture.failToken = true;
    expect(
      await fixture.account.openAuthLink(
        Uri.parse('${WorkspaceAccount.callbackUrl}?code=expired'),
      ),
      isFalse,
    );
    expect(fixture.account.recoveringPassword, isFalse);
    expect(fixture.client.auth.currentSession, isNull);
    expect(fixture.account.notice, contains('fresh email'));
  });
  test(
    'Rejected password updates retain recovery mode for correction',
    () async {
      await fixture.recover();
      fixture.failUpdate = true;
      await expectLater(
        fixture.account.finishRecovery('password1', 'password1'),
        throwsA(isA<AuthException>()),
      );
      expect(fixture.account.recoveringPassword, isTrue);
    },
  );
  test(
    'Cancelling clears local recovery even when server logout is offline',
    () async {
      await fixture.recover();
      fixture.failLogout = true;
      await fixture.account.cancelRecovery();
      expect(fixture.account.recoveringPassword, isFalse);
      expect(fixture.client.auth.currentSession, isNull);
    },
  );
  test('Account switch invalidates the previous recovery form', () async {
    await fixture.recover();
    await fixture.client.auth.recoverSession(
      jsonEncode(fixture.session('10000000-0000-4000-8000-000000000002')),
    );
    await Future<void>.delayed(Duration.zero);
    expect(fixture.account.recoveringPassword, isFalse);
    await expectLater(
      fixture.account.finishRecovery('password1', 'password1'),
      throwsStateError,
    );
    expect(fixture.calls('/user'), isEmpty);
  });
  test(
    'Disposal before initial-link delivery cannot create a new session',
    () async {
      final initial = Completer<Uri?>();
      fixture.account.attachLinks(const Stream.empty(), initial.future);
      fixture.closeAccount();
      initial.complete(Uri.parse('${WorkspaceAccount.callbackUrl}?code=late'));
      await Future<void>.delayed(Duration.zero);
      expect(fixture.requests, isEmpty);
    },
  );
}
