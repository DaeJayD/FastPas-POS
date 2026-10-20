import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vasenizzpos/hybrid/local_store.dart';
import 'package:vasenizzpos/hybrid/sync_service.dart';
import 'package:vasenizzpos/workspaces/workspace_cache.dart';
import 'package:vasenizzpos/workspaces/workspace_repository.dart';

void main() {
  sqfliteFfiInit();
  const user = '10000000-0000-4000-8000-000000000001';
  const business = '20000000-0000-4000-8000-000000000001';
  const branch = '30000000-0000-4000-8000-000000000001';
  late Directory directory;
  late LocalStore store;
  late SupabaseClient client;
  var received = <Map<String, dynamic>>[];
  var loseFirstReply = false;
  var membershipRevoked = false;
  var denySale = false;
  var offline = false;
  var denyDirectory = false;
  Completer<void>? stockRequested, releaseStock;
  var revokeDuringCatalog = false;
  Future<void> restoreIdentity(String id) async {
    String encode(Object data) =>
        base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
    final expiry =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000;
    await client.auth.recoverSession(
      jsonEncode({
        'access_token':
            '${encode({'alg': 'HS256'})}.${encode({'sub': id, 'exp': expiry})}.signature',
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'expires_at': expiry,
        'user': {
          'id': id,
          'app_metadata': {},
          'user_metadata': {},
          'aud': 'authenticated',
          'created_at': '2026-10-21T00:00:00Z',
        },
      }),
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    received = [];
    loseFirstReply = false;
    membershipRevoked = false;
    denySale = false;
    offline = false;
    denyDirectory = false;
    stockRequested = null;
    releaseStock = null;
    revokeDuringCatalog = false;
    directory = await Directory.systemTemp.createTemp('fastpas-sync-');
    store = await LocalStore.open(
      userId: user,
      businessId: business,
      branchId: branch,
      directory: directory.path,
      factory: databaseFactoryFfi,
    );
    await store.replaceSnapshot([
      {
        'id': 'p1',
        'name': 'Coffee',
        'sku': 'COF',
        'price_cents': 100,
        'quantity': 5,
      },
    ], 'cashier');
    client = SupabaseClient(
      'https://example.supabase.co',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (offline) throw http.ClientException('Offline');
        if (denyDirectory) {
          return http.Response(
            jsonEncode({'code': '42501', 'message': 'Access denied'}),
            403,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        final route = request.url.path;
        Object? response;
        if (route.endsWith('/pos_memberships')) {
          response = membershipRevoked ? null : {'role': 'cashier'};
        } else if (route.endsWith('/pos_branches')) {
          response = membershipRevoked ? null : {'id': branch};
        } else if (route.endsWith('/pos_sync_cash_sale')) {
          final payload =
              (jsonDecode(request.body) as Map<String, dynamic>)['sale']
                  as Map<String, dynamic>;
          received.add(payload);
          if (loseFirstReply && received.length == 1) {
            throw http.ClientException('Reply lost');
          }
          if (denySale) {
            return http.Response(
              jsonEncode({'code': '22023', 'message': 'Catalog changed'}),
              400,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }
          response = payload['id'];
        } else if (route.endsWith('/pos_item_stock')) {
          stockRequested?.complete();
          if (releaseStock != null) await releaseStock!.future;
          if (revokeDuringCatalog) membershipRevoked = true;
          response = [
            {
              'product_id': 'p1',
              'quantity': received.isEmpty || denySale ? 5 : 3,
              'pos_items': {
                'id': 'p1',
                'name': 'Coffee',
                'sku': 'COF',
                'price_cents': 100,
                'active': true,
              },
            },
          ];
        } else {
          throw StateError('Unexpected request $route');
        }
        return http.Response(
          jsonEncode(response),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await restoreIdentity(user);
  });
  tearDown(() async {
    await client.dispose();
    await store.close();
    await directory.delete(recursive: true);
  });
  test('Lost acknowledgement retries the same business-bound sale without double local deduction', () async {
    final id = await store.checkout({'p1': 2}, 200);
    loseFirstReply = true;
    await expectLater(
      SyncService(client, store).synchronize(),
      throwsA(isA<http.ClientException>()),
    );
    expect((await store.receipts()).single['status'], 'pending');
    await SyncService(client, store).synchronize();
    expect(received.length, 2);
    expect(received.first, received.last);
    expect(received.last['id'], id);
    expect(received.last['business_id'], business);
    expect((await store.receipts()).single['status'], 'synced');
    expect((await store.products()).single['quantity'], 3);
  });
  test('Server validation failure retains sale for review', () async {
    await store.checkout({'p1': 2}, 200);
    denySale = true;
    await SyncService(client, store).synchronize();
    expect((await store.receipts()).single['status'], 'blocked');
    expect((await store.products()).single['quantity'], 3);
  });
  test('Membership revocation disables offline selling but preserves pending receipts', () async {
    await store.checkout({'p1': 2}, 200);
    membershipRevoked = true;
    await expectLater(
      SyncService(client, store).synchronize(),
      throwsStateError,
    );
    expect(received, isEmpty);
    expect(await store.canSell(), isFalse);
    expect((await store.receipts()).single['status'], 'pending');
  });
  test('Changing accounts cannot upload the previous account queue', () async {
    await store.checkout({'p1': 2}, 200);
    await restoreIdentity('10000000-0000-4000-8000-000000000002');
    await expectLater(
      SyncService(client, store).synchronize(),
      throwsStateError,
    );
    expect(received, isEmpty);
  });
  test(
    'Offline business discovery uses only the signed-in account cache',
    () async {
      await WorkspaceCache().save(user, 'businesses', [
        {'id': business, 'name': 'Store A', 'role': 'owner'},
      ]);
      offline = true;
      final repository = WorkspaceRepository(client);
      expect((await repository.businesses()).single.id, business);
      expect(repository.lastReadOffline, isTrue);
      await restoreIdentity('10000000-0000-4000-8000-000000000002');
      expect(await repository.businesses(), isEmpty);
    },
  );
  test('Permission denial invalidates cached discovery instead of masking it as offline', () async {
    await WorkspaceCache().save(user, 'businesses', [
      {'id': business, 'name': 'Store A', 'role': 'owner'},
    ]);
    denyDirectory = true;
    await expectLater(
      WorkspaceRepository(client).businesses(),
      throwsA(isA<PostgrestException>()),
    );
    expect(await WorkspaceCache().read(user, 'businesses'), isEmpty);
  });
  test(
    'Checkout during catalog refresh retains the new pending stock deduction',
    () async {
      await store.checkout({'p1': 2}, 200);
      stockRequested = Completer<void>();
      releaseStock = Completer<void>();
      final syncing = SyncService(client, store).synchronize();
      await stockRequested!.future;
      await store.checkout({'p1': 1}, 100);
      releaseStock!.complete();
      await syncing;
      expect((await store.products()).single['quantity'], 2);
      expect(
        (await store.receipts())
            .where((row) => row['status'] == 'pending')
            .length,
        1,
      );
      expect(received.length, 1);
    },
  );
  test(
    'Access removed during catalog download cannot renew offline permission',
    () async {
      revokeDuringCatalog = true;
      await expectLater(
        SyncService(client, store).synchronize(),
        throwsStateError,
      );
      expect(await store.canSell(), isFalse);
    },
  );
}
