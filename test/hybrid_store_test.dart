import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vasenizzpos/hybrid/cash_rules.dart';
import 'package:vasenizzpos/hybrid/checkout_quote.dart';
import 'package:vasenizzpos/hybrid/local_store.dart';
import 'package:vasenizzpos/core/receipt_details.dart';
import 'package:vasenizzpos/hybrid/receipt_presenter.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late LocalStore store;
  final verified = DateTime.utc(2026, 10, 21, 1);
  final product = <String, Object?>{
    'id': 'p1',
    'name': 'Coffee',
    'sku': 'COF',
    'price_cents': 1250,
    'quantity': 5,
  };
  Future<LocalStore> open({
    String user = 'u1',
    String business = 'b1',
    String branch = 's1',
  }) => LocalStore.open(
    userId: user,
    businessId: business,
    branchId: branch,
    factory: databaseFactoryFfi,
    directory: directory.path,
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fastpas-sqlite-');
    store = await open();
    await store.replaceSnapshot([product], 'cashier', now: verified);
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  Future<CheckoutQuote> review() async => CheckoutQuote.capture(
    userId: store.userId,
    businessId: store.businessId,
    branchId: store.branchId,
    products: await store.products(),
    quantities: {'p1': 1},
  );

  test('Concurrent confirmation of one quote saves and deducts once', () async {
    final quote = await review();
    final ids = await Future.wait([
      store.checkout({'p1': 1}, 1250, quote: quote, now: verified),
      store.checkout({'p1': 1}, 1250, quote: quote, now: verified),
    ]);
    expect(ids, [quote.attemptId, quote.attemptId]);
    expect((await store.receipts()).length, 1);
    expect((await store.products()).single['quantity'], 4);
  });

  test('Changing the caller cart while confirmation runs cannot change the saved sale', () async {
    final quote = await review();
    final quantities = {'p1': 1};
    final saving = store.checkout(
      quantities,
      1250,
      quote: quote,
      now: verified,
    );
    quantities.clear();
    final id = await saving;
    final payload =
        jsonDecode((await store.receipt(id))['payload'] as String) as Map;
    expect(payload['items'], [
      {
        'product_id': 'p1',
        'name': 'Coffee',
        'sku': 'COF',
        'quantity': 1,
        'unit_cents': 1250,
      },
    ]);
    expect((await store.receipt(id))['total_cents'], 1250);
    expect((await store.products()).single['quantity'], 4);
  });

  test(
    'A changed cash retry cannot alter an already committed receipt',
    () async {
      final quote = await review();
      final id = await store.checkout(
        {'p1': 1},
        1250,
        quote: quote,
        now: verified,
      );
      final original = (await store.receipt(id))['payload'];
      await expectLater(
        store.checkout({'p1': 1}, 1500, quote: quote, now: verified),
        throwsFormatException,
      );
      expect((await store.receipt(id))['payload'], original);
      expect((await store.products()).single['quantity'], 4);
    },
  );

  for (final scope in ['account', 'business', 'branch']) {
    test('A reviewed quote cannot cross its $scope boundary', () async {
      final quote = await review();
      final other = await open(
        user: scope == 'account' ? 'u2' : 'u1',
        business: scope == 'business' ? 'b2' : 'b1',
        branch: scope == 'branch' ? 's2' : 's1',
      );
      try {
        await other.replaceSnapshot([product], 'owner', now: verified);
        await expectLater(
          other.checkout({'p1': 1}, 1250, quote: quote, now: verified),
          throwsStateError,
        );
        expect(await other.receipts(), isEmpty);
        expect((await other.products()).single['quantity'], 5);
      } finally {
        await other.close();
      }
    });
  }

  test('A failed receipt insert rolls back stock and leaves the same quote retryable', () async {
    final quote = await review();
    await store.db.execute(
      "CREATE TRIGGER interrupt_checkout BEFORE INSERT ON sales BEGIN SELECT RAISE(ABORT, 'Interrupted checkout'); END",
    );
    await expectLater(
      store.checkout({'p1': 1}, 1250, quote: quote, now: verified),
      throwsException,
    );
    expect(await store.receipts(), isEmpty);
    expect((await store.products()).single['quantity'], 5);
    await store.db.execute('DROP TRIGGER interrupt_checkout');
    expect(
      await store.checkout({'p1': 1}, 1250, quote: quote, now: verified),
      quote.attemptId,
    );
    expect((await store.receipts()).length, 1);
    expect((await store.products()).single['quantity'], 4);
  });

  test(
    'Expired selling access permits receipt recovery but prevents a new sale',
    () async {
      final quote = await review();
      final id = await store.checkout(
        {'p1': 1},
        1250,
        quote: quote,
        now: verified,
      );
      final expired = verified.add(const Duration(hours: 25));
      expect(
        await store.checkout({'p1': 1}, 1250, quote: quote, now: expired),
        id,
      );
      final next = await review();
      await expectLater(
        store.checkout({'p1': 1}, 1250, quote: next, now: expired),
        throwsStateError,
      );
      expect((await store.receipts()).length, 1);
      expect((await store.products()).single['quantity'], 4);
    },
  );

  test(
    'An inactive checkout context cannot write a receipt or deduct stock',
    () async {
      final quote = await review();
      await expectLater(
        store.checkout(
          {'p1': 1},
          1250,
          quote: quote,
          now: verified,
          isActive: () => false,
        ),
        throwsStateError,
      );
      expect(await store.receipts(), isEmpty);
      expect((await store.products()).single['quantity'], 5);
    },
  );

  test('Exact monetary parsing rejects rounding and malformed amounts', () {
    expect(parseCents('10.01'), 1001);
    expect(parseCents('0.1'), 10);
    for (final value in ['-1', '1.001', 'NaN', '1e3', '']) {
      expect(() => parseCents(value), throwsFormatException);
    }
  });
  test('Retrying one reviewed checkout after restart returns its saved receipt once', () async {
    final quote = CheckoutQuote.capture(
      userId: store.userId,
      businessId: store.businessId,
      branchId: store.branchId,
      products: await store.products(),
      quantities: {'p1': 1},
    );
    final first = await store.checkout(
      {'p1': 1},
      1250,
      quote: quote,
      now: verified,
    );
    await store.close();
    store = await open();
    final retry = await store.checkout(
      {'p1': 1},
      1250,
      quote: quote,
      now: verified,
    );
    expect(retry, first);
    expect((await store.receipts()).length, 1);
    expect((await store.products()).single['quantity'], 4);
  });
  test(
    'Offline receipt branding survives settings changes and a restart',
    () async {
      const original = ReceiptDetails(
        businessId: 'b1',
        branchId: 's1',
        businessName: 'Original store',
        branchName: 'Main',
        branchAddress: 'CDO',
        footer: 'Original footer',
      );
      await store.replaceSnapshot(
        [product],
        'cashier',
        now: verified,
        receiptDetails: original,
      );
      final id = await store.checkout({'p1': 1}, 1500, now: verified);
      final payload = (await store.receipt(id))['payload'];
      await store.replaceSnapshot(
        [product],
        'cashier',
        now: verified,
        receiptDetails: const ReceiptDetails(
          businessId: 'b1',
          branchId: 's1',
          businessName: 'Renamed store',
          branchName: 'Renamed branch',
          footer: 'New footer',
        ),
      );
      await store.close();
      store = await open();
      expect((await store.receipt(id))['payload'], payload);
      final sale = jsonDecode(payload as String) as Map<String, dynamic>;
      final text = receiptText(sale, 1250);
      expect(text, contains('Original store\nMain\nCDO'));
      expect(text, contains('Original footer'));
      expect(text, contains('Change ₱2.50'));
      expect(text, isNot(contains('Renamed store')));
      expect((await store.pendingReceipts()).single['id'], id);
    },
  );
  test('Receipt details cannot cross a business or branch boundary', () async {
    const wrong = ReceiptDetails(
      businessId: 'b2',
      branchId: 's1',
      businessName: 'Wrong',
      branchName: 'Main',
    );
    await expectLater(
      store.replaceSnapshot(
        [product],
        'cashier',
        now: verified,
        receiptDetails: wrong,
      ),
      throwsStateError,
    );
    await expectLater(
      store.checkout(
        {'p1': 1},
        1250,
        now: verified,
        fallbackReceiptDetails: wrong,
      ),
      throwsStateError,
    );
    expect(await store.receipts(), isEmpty);
    expect((await store.products()).single['quantity'], 5);
  });
  test(
    'Receipts from before branding support still show exact totals and change',
    () async {
      final id = await store.checkout({'p1': 1}, 1500, now: verified);
      final sale = jsonDecode(
        (await store.receipt(id))['payload'] as String,
      ) as Map<String, dynamic>;
      expect(sale.containsKey('receipt_details'), isFalse);
      expect(receiptText(sale, 1250), contains('Cash ₱15.00\nChange ₱2.50'));
    },
  );
  test(
    'Closing a previous branch visit does not close a reopened store',
    () async {
      final reopened = await open();
      try {
        await store.close();
        expect((await reopened.products()).single['id'], 'p1');
      } finally {
        await reopened.close();
      }
    },
  );
  test(
    'Checkout atomically saves receipt, outbox, stock and fixed scope',
    () async {
      final id = await store.checkout({'p1': 2}, 3000, now: verified);
      final receipt = (await store.receipts()).single;
      expect(receipt['id'], id);
      expect(receipt['status'], 'pending');
      expect(receipt['total_cents'], 2500);
      final payload = jsonDecode(receipt['payload'] as String) as Map;
      expect(payload['business_id'], 'b1');
      expect(payload['branch_id'], 's1');
      expect((await store.products()).single['quantity'], 3);
    },
  );
  test(
    'Failed checkout rolls back stock and does not create a receipt',
    () async {
      await expectLater(
        store.checkout({'p1': 2}, 100, now: verified),
        throwsArgumentError,
      );
      expect(await store.receipts(), isEmpty);
      expect((await store.products()).single['quantity'], 5);
      await expectLater(
        store.checkout({'p1': 6}, 10000, now: verified),
        throwsStateError,
      );
    },
  );
  test(
    'Pending sale and device identity survive closing and reopening SQLite',
    () async {
      final device = await store.meta('device_id');
      await store.checkout({'p1': 1}, 1250, now: verified);
      await store.close();
      store = await open();
      expect(await store.meta('device_id'), device);
      expect((await store.receipts()).single['status'], 'pending');
      expect((await store.products()).single['quantity'], 4);
    },
  );
  test('Different accounts, businesses, and branches cannot see the same local records', () async {
    await store.checkout({'p1': 1}, 1250, now: verified);
    for (final other in [
      await open(user: 'u2'),
      await open(business: 'b2'),
      await open(branch: 's2'),
    ]) {
      expect(await other.receipts(), isEmpty);
      expect(await other.products(), isEmpty);
      expect(await other.canSell(now: verified), isFalse);
      await other.close();
    }
  });
  test('Refreshing stock retains pending deductions; acknowledged retries do not deduct twice', () async {
    final id = await store.checkout({'p1': 2}, 2500, now: verified);
    await store.replaceSnapshot([product], 'cashier', now: verified);
    expect((await store.products()).single['quantity'], 3);
    await store.setStatus(id, 'synced');
    await store.setStatus(id, 'synced');
    await store.replaceSnapshot(
      [
        {...product, 'quantity': 3},
      ],
      'cashier',
      now: verified,
    );
    expect((await store.products()).single['quantity'], 3);
  });
  test(
    'Rejected sales stay available for review and retain their stock deduction',
    () async {
      final id = await store.checkout({'p1': 1}, 1250, now: verified);
      await store.setStatus(id, 'blocked', error: 'Catalog changed');
      await store.replaceSnapshot([product], 'cashier', now: verified);
      expect((await store.receipts()).single['error'], 'Catalog changed');
      expect((await store.products()).single['quantity'], 4);
    },
  );
  test(
    'Expired, revoked, clock-regressed or employee access cannot sell offline',
    () async {
      expect(
        await store.canSell(now: verified.add(const Duration(hours: 23))),
        isTrue,
      );
      expect(
        await store.canSell(now: verified.add(const Duration(hours: 24))),
        isFalse,
      );
      expect(
        await store.canSell(now: verified.subtract(const Duration(seconds: 1))),
        isFalse,
      );
      await store.setMeta('revoked', 'true');
      await expectLater(
        store.checkout({'p1': 1}, 1250, now: verified),
        throwsStateError,
      );
      await store.replaceSnapshot([product], 'employee', now: verified);
      expect(await store.canSell(now: verified), isFalse);
    },
  );
}
