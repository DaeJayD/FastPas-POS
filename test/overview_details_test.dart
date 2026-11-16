import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vasenizzpos/reports/overview_details.dart';

import 'support/account_fixture.dart';

void main() {
  late AccountFixture identity;
  late SupabaseClient client;
  late OverviewDetailsRepository repository;
  var receipts = <Map<String, dynamic>>[];
  var stock = <Map<String, dynamic>>[];
  final requests = <http.Request>[];
  Completer<void>? requested;
  Completer<void>? release;
  var paged = false;

  Map<String, dynamic> item(
    String id,
    int quantity,
    int threshold, {
    bool active = true,
  }) => {
    'business_id': 'business',
    'branch_id': 'branch',
    'product_id': id,
    'quantity': quantity,
    'low_stock_threshold': threshold,
    'pos_items': {'name': id, 'sku': id.toUpperCase(), 'active': active},
  };
  Map<String, dynamic> sale(String id, List<Map<String, dynamic>> lines) => {
    'id': id,
    'business_id': 'business',
    'branch_id': 'branch',
    'payload': {'items': lines},
  };
  Map<String, dynamic> line(String id, int quantity) => {
    'product_id': id,
    'name': id,
    'sku': id.toUpperCase(),
    'quantity': quantity,
  };

  setUp(() async {
    identity = AccountFixture();
    requests.clear();
    receipts = [];
    stock = [];
    requested = null;
    release = null;
    paged = false;
    client = SupabaseClient(
      'https://overview-test.invalid',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        Object data;
        if (request.url.path.endsWith('/pos_cash_sales')) {
          requested?.complete();
          await release?.future;
          data = receipts;
        } else if (request.url.path.endsWith('/pos_item_stock')) {
          if (paged) {
            data = request.url.queryParameters['product_id'] == null
                ? [
                    for (var i = 0; i < 500; i++)
                      item('item-${i.toString().padLeft(3, '0')}', 10, 0),
                  ]
                : [item('item-500', 1, 2)];
          } else {
            data = stock;
          }
        } else {
          throw StateError('Unexpected overview endpoint');
        }
        return http.Response(
          jsonEncode(data),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    await client.auth.recoverSession(jsonEncode(identity.session()));
    repository = OverviewDetailsRepository(
      client,
      'business',
      AccountFixture.userId,
    );
  });
  tearDown(() async {
    await client.dispose();
    await identity.close();
  });

  test('Overview ranks actual receipt units and stock thresholds within its stated scope', () async {
    receipts = [
      sale('one', [line('coffee', 2), line('bread', 1)]),
      sale('two', [line('coffee', 3)]),
    ];
    stock = [
      item('healthy', 10, 2),
      item('low', 2, 3),
      item('empty', 0, 0),
      item('shortage', -1, 0),
      item('archived', 0, 0, active: false),
    ];
    final result = await repository.load('branch');
    expect(result.itemsSold, 6);
    expect(result.receiptCount, 2);
    expect(result.sellers.map((s) => '${s.name}:${s.quantity}'), [
      'coffee:5',
      'bread:1',
    ]);
    expect(result.stock.map((s) => s.name), ['shortage', 'empty', 'low']);
    expect(
      requests.every(
        (r) =>
            r.url.queryParameters['business_id'] == 'eq.business' &&
            r.url.queryParameters['branch_id'] == 'eq.branch',
      ),
      isTrue,
    );
    expect(requests.first.url.queryParameters['limit'], '200');
    expect(
      requests.first.url.queryParameters['order'],
      allOf(contains('received_at.desc'), contains('id.desc')),
    );
  });

  test('Overview stock counts include pages beyond the API row cap', () async {
    paged = true;
    final result = await repository.load('branch');
    expect(result.stock.single.name, 'item-500');
    final pages = requests
        .where((r) => r.url.path.endsWith('/pos_item_stock'))
        .toList();
    expect(pages, hasLength(2));
    expect(pages.last.url.queryParameters['product_id'], 'gt.item-499');
  });

  test(
    'Overview rejects an account switch while receipts are loading',
    () async {
      requested = Completer();
      release = Completer();
      final result = repository.load('branch');
      final rejected = expectLater(result, throwsFormatException);
      await requested!.future;
      await client.auth.recoverSession(
        jsonEncode(identity.session('different-user')),
      );
      release!.complete();
      await rejected;
      expect(requests, hasLength(1));
    },
  );

  test('Overview rejects foreign business or branch responses instead of displaying them', () async {
    receipts = [
      {...sale('foreign', []), 'business_id': 'other-business'},
    ];
    await expectLater(repository.load('branch'), throwsFormatException);
    receipts = [];
    stock = [
      {...item('foreign', 0, 0), 'branch_id': 'other-branch'},
    ];
    await expectLater(repository.load('branch'), throwsFormatException);
  });

  test(
    'No receipts or stock is an actual empty overview, not sample values',
    () async {
      final result = await repository.load('branch');
      expect(result.itemsSold, 0);
      expect(result.receiptCount, 0);
      expect(result.sellers, isEmpty);
      expect(result.stock, isEmpty);
    },
  );
}
