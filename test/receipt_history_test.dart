import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vasenizzpos/hybrid/local_store.dart';

void main() {
  sqfliteFfiInit();
  test('Receipt pages keep their cursor when a new sale arrives and retain review status', () async {
    final directory = await Directory.systemTemp.createTemp(
      'fastpas-receipt-pages-',
    );
    final store = await LocalStore.open(
      userId: 'user',
      businessId: 'business',
      branchId: 'branch',
      directory: directory.path,
      factory: databaseFactoryFfi,
    );
    try {
      await store.replaceSnapshot([
        {
          'id': 'coffee',
          'name': 'Coffee',
          'sku': 'COF',
          'price_cents': 1250,
          'quantity': 20,
        },
      ], 'cashier');
      final ids = <String>[];
      for (var i = 0; i < 5; i++) {
        ids.add(await store.checkout({'coffee': 1}, 1250));
      }
      await store.setStatus(ids[0], 'synced');
      await store.setStatus(ids[1], 'blocked', error: 'Catalog changed');
      final original = (await store.receipt(ids[1]))['payload'];
      final first = await store.receiptPage(limit: 2);
      expect(first.entries.map((r) => r.id), [ids[4], ids[3]]);
      expect(first.nextBefore, isNotNull);
      final latest = await store.checkout({'coffee': 1}, 1250);
      final second = await store.receiptPage(
        limit: 2,
        before: first.nextBefore,
      );
      expect(second.entries.map((r) => r.id), [ids[2], ids[1]]);
      final third = await store.receiptPage(
        limit: 2,
        before: second.nextBefore,
      );
      expect(third.entries.map((r) => r.id), [ids[0]]);
      expect(third.nextBefore, isNull);
      final review = await store.receiptPage(status: 'blocked');
      expect(review.entries.single.id, ids[1]);
      expect(review.entries.single.error, 'Catalog changed');
      final counts = await store.receiptCounts();
      expect(
        [counts.pending, counts.synced, counts.blocked, counts.total],
        [4, 1, 1, 6],
      );
      expect((await store.receiptPage()).entries.first.id, latest);
      expect((await store.receipt(ids[1]))['payload'], original);
      expect((await store.products()).single['quantity'], 14);
    } finally {
      await store.close();
      await directory.delete(recursive: true);
    }
  });
}
