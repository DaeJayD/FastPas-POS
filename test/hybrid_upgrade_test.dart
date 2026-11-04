import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vasenizzpos/hybrid/local_store.dart';

void main() {
  sqfliteFfiInit();

  test('Version 1 upgrades offline without losing receipts, device identity or deductions', () async {
    final directory = await Directory.systemTemp.createTemp('fastpas-upgrade-');
    final payload = jsonEncode({
      'id': 'saved-sale',
      'business_id': 'business',
      'branch_id': 'branch',
      'cash_cents': 1250,
      'items': [
        {
          'product_id': 'p1',
          'name': 'Original coffee',
          'sku': 'COF',
          'quantity': 1,
          'unit_cents': 1250,
        },
      ],
    });
    final legacy = await databaseFactoryFfi.openDatabase(
      path.join(directory.path, 'pos-user-business-branch.db'),
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE products (id TEXT PRIMARY KEY, name TEXT NOT NULL, sku TEXT NOT NULL, price_cents INTEGER NOT NULL, quantity INTEGER NOT NULL)',
          );
          await db.execute(
            "CREATE TABLE sales (id TEXT PRIMARY KEY, payload TEXT NOT NULL, total_cents INTEGER NOT NULL, status TEXT NOT NULL DEFAULT 'pending', error TEXT)",
          );
          for (final entry in {
            'device_id': 'existing-device',
            'role': 'cashier',
            'verified_at': DateTime.now().toUtc().toIso8601String(),
            'revoked': 'false',
            'receipt_details': 'retained-branding',
          }.entries) {
            await db.insert('metadata', {
              'key': entry.key,
              'value': entry.value,
            });
          }
          await db.insert('products', {
            'id': 'p1',
            'name': 'Coffee',
            'sku': 'COF',
            'price_cents': 1250,
            'quantity': 4,
          });
          await db.insert('sales', {
            'id': 'saved-sale',
            'payload': payload,
            'total_cents': 1250,
            'status': 'pending',
          });
        },
      ),
    );
    await legacy.close();
    Future<LocalStore> open() => LocalStore.open(
      userId: 'user',
      businessId: 'business',
      branchId: 'branch',
      directory: directory.path,
      factory: databaseFactoryFfi,
    );
    var store = await open();
    try {
      expect(await store.meta('device_id'), 'existing-device');
      expect(await store.meta('receipt_details'), 'retained-branding');
      expect(await store.canSell(), isTrue);
      expect((await store.receipt('saved-sale'))['payload'], payload);
      expect((await store.products()).single['quantity'], 4);
      expect((await store.products()).single['category_name'], '');
      await store.replaceSnapshot([
        {
          'id': 'p1',
          'name': 'Coffee',
          'sku': 'COF',
          'price_cents': 1250,
          'quantity': 5,
          'category_id': 'drinks',
          'category_name': 'Drinks',
        },
      ], 'cashier');
      await store.close();
      store = await open();
      expect((await store.products()).single['category_name'], 'Drinks');
      expect((await store.products()).single['category_id'], 'drinks');
      expect((await store.products()).single['quantity'], 4);
      expect((await store.pendingReceipts()).single['payload'], payload);
      expect(await store.meta('device_id'), 'existing-device');
    } finally {
      await store.close();
      await directory.delete(recursive: true);
    }
  });
}
