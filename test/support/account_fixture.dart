import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vasenizzpos/workspaces/workspace_account.dart';

class MemoryPkceStorage extends GotrueAsyncStorage {
  final values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    values.remove(key);
  }
}

/// Real SDK protocol with a local HTTP transport; no email or network requests.
class AccountFixture {
  AccountFixture() {
    client = SupabaseClient(
      'https://example.supabase.co',
      'test-key',
      authOptions: AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.pkce,
        pkceAsyncStorage: storage,
      ),
      httpClient: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        Object response;
        var status = 200;
        if (path.endsWith('/pos_memberships') ||
            path.endsWith('/pos_businesses')) {
          response = [];
        } else if (path.endsWith('/recover') || path.endsWith('/resend')) {
          response = {};
        } else if (path.endsWith('/signup')) {
          response = {'user': user()};
        } else if (path.endsWith('/token')) {
          if (failToken) {
            status = 400;
            response = {'msg': 'Expired code', 'code': 'otp_expired'};
          } else {
            response = session();
          }
        } else if (path.endsWith('/user')) {
          if (failUpdate) {
            status = 400;
            response = {'msg': 'Password rejected', 'code': 'weak_password'};
          } else {
            response = user();
          }
        } else if (path.endsWith('/logout')) {
          if (failLogout) throw http.ClientException('Offline');
          response = {};
        } else {
          throw StateError('Unexpected account request $path');
        }
        return http.Response(
          jsonEncode(response),
          status,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    account = WorkspaceAccount(client);
  }

  static const userId = '10000000-0000-4000-8000-000000000001';
  final storage = MemoryPkceStorage();
  final requests = <http.Request>[];
  late final SupabaseClient client;
  late final WorkspaceAccount account;
  bool failToken = false, failUpdate = false, failLogout = false;
  bool _closedAccount = false;

  Map<String, dynamic> user([String id = userId]) => {
    'id': id,
    'email': 'owner@example.test',
    'aud': 'authenticated',
    'app_metadata': {},
    'user_metadata': {},
    'email_confirmed_at': '2026-10-21T00:00:00Z',
    'created_at': '2026-10-21T00:00:00Z',
  };
  Map<String, dynamic> session([String id = userId]) {
    String encode(Object data) =>
        base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
    final expiry =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000;
    return {
      'access_token':
          '${encode({'alg': 'HS256'})}.${encode({'sub': id, 'exp': expiry})}.signature',
      'refresh_token': 'test-refresh',
      'expires_at': expiry,
      'expires_in': 3600,
      'token_type': 'bearer',
      'user': user(id),
    };
  }

  Iterable<http.Request> calls(String suffix) =>
      requests.where((r) => r.url.path.endsWith(suffix));
  Future<void> recover() async {
    await account.sendPasswordReset('owner@example.test');
    await account.openAuthLink(
      Uri.parse('${WorkspaceAccount.callbackUrl}?code=recovery-code'),
    );
    await Future<void>.delayed(Duration.zero);
  }

  void closeAccount() {
    if (_closedAccount) return;
    _closedAccount = true;
    account.dispose();
  }

  Future<void> close() async {
    closeAccount();
    await client.dispose();
  }
}
