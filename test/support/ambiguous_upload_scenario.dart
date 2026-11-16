import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vasenizzpos/hybrid/local_store.dart';
import 'package:vasenizzpos/hybrid/sync_service.dart';

const _user = '10000000-0000-4000-8000-000000000001';
const _business = '20000000-0000-4000-8000-000000000001';
const _branch = '30000000-0000-4000-8000-000000000001';

/// Native/desktop SQLite share this contract. Only the external HTTP boundary
/// is simulated: this scenario never contacts Auth or a hosted database.
Future<void> verifyAmbiguousUpload(DatabaseFactory factory) async {
  final directory = await Directory.systemTemp.createTemp('fastpas-recovery-');
  Future<LocalStore> open() => LocalStore.open(
    userId: _user,
    businessId: _business,
    branchId: _branch,
    directory: directory.path,
    factory: factory,
  );
  final server = _CommitThenDisconnect();
  final client = SupabaseClient(
    'https://recovery-test.invalid',
    'local-test-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: server.transport,
  );
  LocalStore? store;
  LocalStore? secondConnection;
  try {
    await _restoreTestIdentity(client);
    store = await open();
    await store.replaceSnapshot([
      {
        'id': 'coffee',
        'name': 'Coffee',
        'sku': 'COF',
        'price_cents': 100,
        'quantity': 5,
      },
    ], 'cashier');
    final device = await store.deviceId;
    final id = await store.checkout({'coffee': 2}, 200);
    final originalPayload = (await store.receipt(id))['payload'];
    var now = DateTime.now();

    await expectLater(
      SyncService(client, store, clock: () => now).synchronize(),
      throwsA(isA<http.ClientException>()),
    );
    await store.close();
    store = await open();
    final retained = await store.receipt(id);
    expect(retained['status'], 'pending');
    expect(retained['payload'], originalPayload);
    expect(retained['upload_attempts'], 1);
    expect(
      retained['retry_after_ms'],
      now.add(const Duration(seconds: 30)).millisecondsSinceEpoch,
    );
    expect(await store.deviceId, device);
    expect((await store.products()).single['quantity'], 3);
    expect(
      await SyncService(client, store, clock: () => now).synchronize(),
      SyncOutcome.waiting,
    );
    expect((await store.receipt(id))['status'], 'pending');

    // Independent route connections must serialize the upload and snapshot.
    secondConnection = await open();
    now = now.add(const Duration(seconds: 30));
    final outcomes = await Future.wait([
      SyncService(client, store, clock: () => now).synchronize(),
      SyncService(client, secondConnection, clock: () => now).synchronize(),
    ]);
    expect(outcomes, everyElement(SyncOutcome.synchronized));
    expect((await store.receipt(id))['status'], 'synced');
    expect((await store.receipt(id))['payload'], originalPayload);
    expect((await store.receipts()).single['id'], id);
    expect((await store.products()).single['quantity'], 3);
    expect((await secondConnection.products()).single['quantity'], 3);
    expect(server.committedReceipts, hasLength(1));
    expect(server.stock, 3);
    expect(server.submittedPayloads, hasLength(2));
    expect(server.submittedPayloads[0], server.submittedPayloads[1]);
    expect(server.registeredDevices, {device});

    // A different account's file never inherits this receipt or stock.
    final unrelated = await LocalStore.open(
      userId: 'unrelated-user',
      businessId: _business,
      branchId: _branch,
      directory: directory.path,
      factory: factory,
    );
    try {
      expect(await unrelated.receipts(), isEmpty);
      expect(await unrelated.products(), isEmpty);
      expect(await unrelated.deviceId, isNot(device));
      await expectLater(
        SyncService(client, unrelated).synchronize(),
        throwsStateError,
      );
    } finally {
      await unrelated.close();
    }
  } finally {
    await secondConnection?.close();
    await store?.close();
    await client.dispose();
    await directory.delete(recursive: true);
  }
}

class _CommitThenDisconnect {
  late final http.Client transport = MockClient(_respond);
  final committedReceipts = <String, String>{};
  final submittedPayloads = <String>[];
  final registeredDevices = <String>{};
  var stock = 5;
  var _dropReply = true;

  Future<http.Response> _respond(http.Request request) async {
    if (request.url.origin != 'https://recovery-test.invalid') {
      throw StateError('Recovery test tried to leave its isolated transport.');
    }
    final route = request.url.path;
    Object? response;
    if (route == '/rest/v1/pos_memberships') {
      response = {'role': 'cashier'};
    } else if (route == '/rest/v1/pos_branches') {
      response = {'id': _branch, 'business_id': _business, 'name': 'Main'};
    } else if (route == '/rest/v1/pos_businesses') {
      response = {'id': _business, 'name': 'Recovery fixture'};
    } else if (route == '/rest/v1/rpc/pos_sync_cash_sale') {
      final sale = (jsonDecode(request.body) as Map)['sale'] as Map;
      final id = sale['id'] as String;
      final payload = jsonEncode(sale);
      submittedPayloads.add(payload);
      if (committedReceipts.containsKey(id)) {
        if (committedReceipts[id] != payload) {
          throw StateError('Retry changed the original receipt.');
        }
      } else {
        committedReceipts[id] = payload;
        stock -= 2;
      }
      if (_dropReply) {
        _dropReply = false;
        throw http.ClientException('Committed response was interrupted');
      }
      response = id;
    } else if (route == '/rest/v1/pos_item_stock') {
      response = [
        {
          'product_id': 'coffee',
          'quantity': stock,
          'pos_items': {
            'id': 'coffee',
            'name': 'Coffee',
            'sku': 'COF',
            'price_cents': 100,
            'active': true,
          },
        },
      ];
    } else if (route == '/rest/v1/rpc/pos_register_selling_device') {
      final device = (jsonDecode(request.body) as Map)['p_device'] as String;
      registeredDevices.add(device);
      response = device;
    } else {
      throw StateError('Unexpected recovery test endpoint: $route');
    }
    return http.Response(
      jsonEncode(response),
      200,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

Future<void> _restoreTestIdentity(SupabaseClient client) async {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final expiry =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
      1000;
  await client.auth.recoverSession(
    jsonEncode({
      'access_token':
          '${encode({'alg': 'HS256'})}.${encode({'sub': _user, 'exp': expiry})}.test-signature',
      'refresh_token': 'local-test-refresh',
      'token_type': 'bearer',
      'expires_at': expiry,
      'user': {
        'id': _user,
        'app_metadata': {},
        'user_metadata': {},
        'aud': 'authenticated',
        'created_at': '2026-10-21T00:00:00Z',
      },
    }),
  );
}
