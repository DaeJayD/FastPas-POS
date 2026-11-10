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
  var committed = <String, int>{};
  var stockReads = 0;
  var loseFirstReply = false;
  var denyUploadAccess = false;
  var wrongAcknowledgment = false;
  var pagedCatalog = false;
  var membershipRevoked = false;
  var branchRevoked = false;
  var denySale = false;
  var offline = false;
  var denyDirectory = false;
  Completer<void>? stockRequested, releaseStock;
  Completer<void>? uploadRequested, releaseUpload;
  String? uploadAuthorization;
  var revokeDuringCatalog = false;
  var registrationRequests = <Map<String, dynamic>>[];
  var registrationUnavailable = false;
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
    committed = {};
    stockReads = 0;
    loseFirstReply = false;
    denyUploadAccess = false;
    wrongAcknowledgment = false;
    pagedCatalog = false;
    membershipRevoked = false;
    branchRevoked = false;
    denySale = false;
    offline = false;
    denyDirectory = false;
    stockRequested = null;
    releaseStock = null;
    uploadRequested = null;
    releaseUpload = null;
    uploadAuthorization = null;
    revokeDuringCatalog = false;
    registrationRequests = [];
    registrationUnavailable = false;
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
          response = membershipRevoked || branchRevoked
              ? null
              : {
                  'id': branch,
                  'business_id': business,
                  'name': 'Main',
                  'address': '',
                };
        } else if (route.endsWith('/pos_businesses')) {
          response = {
            'id': business,
            'name': 'Test business',
            'address': '',
            'contact_phone': '',
            'contact_email': '',
            'receipt_footer': 'Thank you',
          };
        } else if (route.endsWith('/pos_sync_cash_sale')) {
          final payload =
              (jsonDecode(request.body) as Map<String, dynamic>)['sale']
                  as Map<String, dynamic>;
          received.add(payload);
          if (denyUploadAccess) {
            return http.Response(
              jsonEncode({'code': '42501', 'message': 'Access denied'}),
              403,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }
          if (denySale) {
            return http.Response(
              jsonEncode({'code': '22023', 'message': 'Catalog changed'}),
              400,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }
          committed.putIfAbsent(
            payload['id'] as String,
            () => (payload['items'] as List).fold<int>(
              0,
              (sum, item) => sum + (item['quantity'] as int),
            ),
          );
          if (loseFirstReply && received.length == 1) {
            throw http.ClientException('Reply lost');
          }
          uploadAuthorization = request.headers['authorization'];
          uploadRequested?.complete();
          if (releaseUpload != null) await releaseUpload!.future;
          response = wrongAcknowledgment ? 'different-receipt' : payload['id'];
        } else if (route.endsWith('/pos_register_selling_device')) {
          final params = jsonDecode(request.body) as Map<String, dynamic>;
          registrationRequests.add(params);
          if (registrationUnavailable) {
            return http.Response(
              jsonEncode({'code': 'PGRST202', 'message': 'Function missing'}),
              404,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }
          response = params['p_device'];
        } else if (route.endsWith('/pos_item_stock')) {
          stockReads++;
          if (stockRequested case final signal? when !signal.isCompleted) {
            signal.complete();
          }
          final quantity =
              5 - committed.values.fold(0, (sum, amount) => sum + amount);
          if (releaseStock != null) await releaseStock!.future;
          if (revokeDuringCatalog) membershipRevoked = true;
          if (pagedCatalog) {
            final params = request.url.queryParameters;
            final cursor = params['product_id']?.substring(3);
            final offset = int.tryParse(params['offset'] ?? '') ?? 0;
            final limit = int.tryParse(params['limit'] ?? '') ?? 500;
            final ids = [
              if (stockReads > 1) 'item-000',
              for (var i = 1; i <= 501; i++)
                'item-${i.toString().padLeft(3, '0')}',
            ];
            response = ids
                .where((id) => cursor == null || id.compareTo(cursor) > 0)
                .skip(offset)
                .take(limit)
                .map(
                  (id) => {
                    'product_id': id,
                    'quantity': 1,
                    'pos_items': {
                      'id': id,
                      'name': id,
                      'sku': id,
                      'price_cents': 100,
                      'active': true,
                    },
                  },
                )
                .toList();
          } else {
            response = [
              {
                'product_id': 'p1',
                'quantity': quantity,
                'pos_items': {
                  'id': 'p1',
                  'name': 'Coffee',
                  'sku': 'COF',
                  'price_cents': 100,
                  'active': true,
                  if ((request.url.queryParameters['select'] ?? '').contains(
                    'pos_categories',
                  )) ...{
                    'category_id': 'drinks',
                    'category': {'name': 'Drinks'},
                  },
                },
              },
            ];
          }
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

  test(
    'Registers the receipt device and keeps its check interval after reopening',
    () async {
      final device = await store.deviceId;
      final id = await store.checkout({'p1': 1}, 100);
      var now = DateTime.utc(2026, 11, 11);
      await SyncService(client, store, clock: () => now).synchronize();
      expect(registrationRequests.single, {
        'p_business': business,
        'p_branch': branch,
        'p_device': device,
      });
      expect(received.single['device_id'], device);
      expect((await store.receipts()).single['id'], id);
      expect((await store.receipts()).single['status'], 'synced');

      await store.close();
      store = await LocalStore.open(
        userId: user,
        businessId: business,
        branchId: branch,
        directory: directory.path,
        factory: databaseFactoryFfi,
      );
      now = now.add(const Duration(minutes: 4));
      final reopened = SyncService(client, store, clock: () => now);
      await reopened.synchronize();
      expect(await store.deviceId, device);
      expect(registrationRequests, hasLength(1));
      now = now.add(const Duration(minutes: 1));
      await reopened.synchronize();
      expect(registrationRequests, hasLength(2));
      expect(registrationRequests.last['p_device'], device);
    },
  );

  test(
    'An older backend still synchronizes receipts without registration',
    () async {
      registrationUnavailable = true;
      await store.checkout({'p1': 1}, 100);
      final sync = SyncService(client, store);
      expect(await sync.synchronize(), SyncOutcome.synchronized);
      expect((await store.receipts()).single['status'], 'synced');
      await sync.synchronize();
      expect(registrationRequests, hasLength(1));
    },
  );
  test(
    'Catalog refresh caches category labels for a later offline visit',
    () async {
      await SyncService(client, store).synchronize();
      await store.close();
      offline = true;
      store = await LocalStore.open(
        userId: user,
        businessId: business,
        branchId: branch,
        directory: directory.path,
        factory: databaseFactoryFfi,
      );
      expect((await store.products()).single['category_id'], 'drinks');
      expect((await store.products()).single['category_name'], 'Drinks');
      expect(await store.canSell(), isTrue);
    },
  );

  test('Lost acknowledgment waits across reopen, then retries the same receipt without double deduction', () async {
    final id = await store.checkout({'p1': 2}, 200);
    var now = DateTime.now();
    loseFirstReply = true;
    await expectLater(
      SyncService(client, store, clock: () => now).synchronize(),
      throwsA(isA<http.ClientException>()),
    );
    await store.close();
    store = await LocalStore.open(
      userId: user,
      businessId: business,
      branchId: branch,
      directory: directory.path,
      factory: databaseFactoryFfi,
    );
    final pending = await store.receipt(id);
    expect(pending['status'], 'pending');
    expect(pending['upload_attempts'], 1);
    expect(
      pending['retry_after_ms'],
      now.add(const Duration(seconds: 30)).millisecondsSinceEpoch,
    );
    final sync = SyncService(client, store, clock: () => now);
    expect(await sync.synchronize(), SyncOutcome.waiting);
    expect(received, hasLength(1));
    expect(stockReads, 0);
    expect((await store.products()).single['quantity'], 3);
    now = now.add(const Duration(seconds: 30));
    expect(await sync.synchronize(), SyncOutcome.synchronized);
    expect(received.length, 2);
    expect(received.first, received.last);
    expect(received.last['id'], id);
    expect(received.last['business_id'], business);
    expect((await store.receipts()).single['status'], 'synced');
    expect((await store.products()).single['quantity'], 3);
  });

  test('Manual sync bypasses the wait, but an access denial keeps an ambiguous sale pending', () async {
    final id = await store.checkout({'p1': 2}, 200);
    final now = DateTime.now();
    final sync = SyncService(client, store, clock: () => now);
    loseFirstReply = true;
    await expectLater(sync.synchronize(), throwsA(isA<http.ClientException>()));
    denyUploadAccess = true;
    await expectLater(
      sync.synchronize(force: true),
      throwsA(isA<PostgrestException>()),
    );
    final pending = await store.receipt(id);
    expect(pending['status'], 'pending');
    expect(pending['upload_attempts'], 2);
    expect(
      pending['retry_after_ms'],
      now.add(const Duration(seconds: 60)).millisecondsSinceEpoch,
    );
    expect(stockReads, 0);
    denyUploadAccess = false;
    await sync.synchronize(force: true);
    expect(received, hasLength(3));
    expect(
      received.every(
        (payload) => jsonEncode(payload) == jsonEncode(received.first),
      ),
      isTrue,
    );
    expect((await store.receipt(id))['status'], 'synced');
    expect((await store.products()).single['quantity'], 3);
  });

  test(
    'A different server acknowledgment cannot clear a pending sale',
    () async {
      final id = await store.checkout({'p1': 1}, 100);
      wrongAcknowledgment = true;
      await expectLater(
        SyncService(client, store).synchronize(),
        throwsStateError,
      );
      expect((await store.receipt(id))['status'], 'pending');
      expect(stockReads, 0);
      wrongAcknowledgment = false;
      await SyncService(client, store).synchronize(force: true);
      expect((await store.receipt(id))['status'], 'synced');
      expect((await store.products()).single['quantity'], 4);
    },
  );

  test(
    'Sync uses bounded FIFO batches and refreshes stock after the queue drains',
    () async {
      final product = Map<String, Object?>.of((await store.products()).single)
        ..['quantity'] = 50;
      await store.replaceSnapshot([product], 'cashier');
      final ids = [
        for (var i = 0; i < 33; i++) await store.checkout({'p1': 1}, 100),
      ];
      final sync = SyncService(client, store);
      expect(await sync.synchronize(), SyncOutcome.queued);
      expect(received.map((sale) => sale['id']), ids.take(32));
      expect(stockReads, 0);
      expect((await store.pendingReceipts()).single['id'], ids.last);
      expect(await sync.synchronize(), SyncOutcome.synchronized);
      expect(received.map((sale) => sale['id']), ids);
      expect(stockReads, 1);
    },
  );

  test('Two branch visits cannot upload into an older visit’s in-flight catalog snapshot', () async {
    await store.checkout({'p1': 2}, 200);
    stockRequested = Completer<void>();
    releaseStock = Completer<void>();
    final first = SyncService(client, store).synchronize();
    await stockRequested!.future;
    final reopened = await LocalStore.open(
      userId: user,
      businessId: business,
      branchId: branch,
      directory: directory.path,
      factory: databaseFactoryFfi,
    );
    try {
      final next = await reopened.checkout({'p1': 1}, 100);
      final second = SyncService(client, reopened).synchronize();
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(received, hasLength(1));
      releaseStock!.complete();
      expect(await first, SyncOutcome.queued);
      expect(await second, SyncOutcome.synchronized);
      expect(received.last['id'], next);
      expect((await reopened.products()).single['quantity'], 2);
    } finally {
      if (!releaseStock!.isCompleted) releaseStock!.complete();
      await first;
      await reopened.close();
    }
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
  test('A late upload reply updates only the original receipt and skips refresh after sign-in changes', () async {
    final id = await store.checkout({'p1': 1}, 100);
    final token = client.auth.currentSession!.accessToken;
    uploadRequested = Completer<void>();
    releaseUpload = Completer<void>();
    final finished = expectLater(
      SyncService(client, store).synchronize(),
      throwsStateError,
    );
    await uploadRequested!.future;
    try {
      await restoreIdentity('10000000-0000-4000-8000-000000000002');
    } finally {
      releaseUpload!.complete();
    }
    await finished;
    expect(uploadAuthorization, 'Bearer $token');
    expect((await store.receipt(id))['status'], 'synced');
    expect(stockReads, 0);
  });
  test('Explicit branch verification denial stops offline sales and leaves uploads pending', () async {
    final id = await store.checkout({'p1': 1}, 100);
    denyDirectory = true;
    await expectLater(
      SyncService(client, store).synchronize(),
      throwsA(isA<PostgrestException>()),
    );
    expect(await store.canSell(), isFalse);
    expect((await store.receipt(id))['status'], 'pending');
    expect(received, isEmpty);
  });
  test('Branch-only revocation disables selling and retains the original pending receipt', () async {
    final receipt = await store.checkout({'p1': 2}, 200);
    branchRevoked = true;
    await expectLater(
      SyncService(client, store).synchronize(),
      throwsStateError,
    );
    expect(membershipRevoked, isFalse);
    expect(received, isEmpty);
    expect(await store.canSell(), isFalse);
    final saved = (await store.receipts()).single;
    expect(saved['id'], receipt);
    expect(saved['status'], 'pending');
    expect(
      (jsonDecode(saved['payload'] as String) as Map)['branch_id'],
      branch,
    );
    // Restoring branch access uploads the same receipt, without moving stores.
    branchRevoked = false;
    await SyncService(client, store).synchronize();
    expect(received.single['id'], receipt);
    expect((await store.receipts()).single['status'], 'synced');
    expect(await store.canSell(), isTrue);
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
      expect(registrationRequests, isEmpty);
    },
  );
  test('Catalog cursor avoids duplicate rows when stock is inserted before the next page', () async {
    pagedCatalog = true;
    await SyncService(client, store).synchronize();
    final products = await store.products();
    expect(stockReads, 2);
    expect(products, hasLength(501));
    expect(products.first['id'], 'item-001');
    expect(products.last['id'], 'item-501');
    await SyncService(client, store).synchronize();
    expect((await store.products()).first['id'], 'item-000');
  });
}
