import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../workspaces/workspace_repository.dart';
import '../core/receipt_details.dart';

/// One file per signed-in account, business, and branch. No global active tenant.
class LocalStore {
  LocalStore._(this.db, this.userId, this.businessId, this.branchId);
  final Database db;
  final String userId, businessId, branchId;

  static Future<LocalStore> open({
    required String userId,
    required String businessId,
    required String branchId,
    DatabaseFactory? factory,
    String? directory,
  }) async {
    final backend = factory ?? databaseFactory;
    final root = directory ?? await backend.getDatabasesPath();
    for (final id in [userId, businessId, branchId]) {
      if (!RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(id)) {
        throw ArgumentError('Invalid store identity');
      }
    }
    final db = await backend.openDatabase(
      path.join(root, 'pos-$userId-$businessId-$branchId.db'),
      options: OpenDatabaseOptions(
        // A previous route may finish an upload after this branch is reopened.
        // Each visit owns its connection; closing one must not close another.
        singleInstance: false,
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
        },
      ),
    );
    final store = LocalStore._(db, userId, businessId, branchId);
    if (await store.meta('device_id') == null) {
      await store.setMeta('device_id', WorkspaceRepository.newRequestId());
    }
    return store;
  }

  Future<String?> meta(String key) async {
    final rows = await db.query('metadata', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setMeta(String key, String value) => db
      .insert('metadata', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace)
      .then((_) {});

  Future<List<Map<String, Object?>>> products() =>
      db.query('products', orderBy: 'name');
  Future<List<Map<String, Object?>>> receipts() =>
      db.query('sales', orderBy: 'rowid DESC');

  Future<List<Map<String, Object?>>> pendingReceipts() => db.query(
    'sales',
    where: 'status = ?',
    whereArgs: ['pending'],
    orderBy: 'rowid',
  );

  Future<Map<String, Object?>> receipt(String id) async => (await db.query(
    'sales',
    where: 'id = ?',
    whereArgs: [id],
    limit: 1,
  )).single;

  Future<void> replaceSnapshot(
    List<Map<String, Object?>> products,
    String role, {
    DateTime? now,
    ReceiptDetails? receiptDetails,
  }) async {
    receiptDetails?.checkScope(businessId, branchId);
    await db.transaction((tx) async {
      final local = await tx.query(
        'sales',
        where: 'status != ?',
        whereArgs: ['synced'],
      );
      final deductions = <String, int>{};
      for (final receipt in local) {
        final payload =
            jsonDecode(receipt['payload'] as String) as Map<String, dynamic>;
        for (final line in payload['items'] as List) {
          final id = line['product_id'] as String;
          deductions[id] = (deductions[id] ?? 0) + (line['quantity'] as int);
        }
      }
      await tx.delete('products');
      for (final row in products) {
        await tx.insert('products', {
          ...row,
          'quantity': (row['quantity'] as int) - (deductions[row['id']] ?? 0),
        });
      }
      for (final entry in {
        'role': role,
        'verified_at': (now ?? DateTime.now()).toUtc().toIso8601String(),
        'revoked': 'false',
        if (receiptDetails != null)
          'receipt_details': jsonEncode(receiptDetails.toJson()),
      }.entries) {
        await tx.insert('metadata', {
          'key': entry.key,
          'value': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<bool> canSell({DateTime? now}) async {
    final verified = DateTime.tryParse(await meta('verified_at') ?? '');
    final clock = (now ?? DateTime.now()).toUtc();
    final role = await meta('role');
    return await meta('revoked') != 'true' &&
        ['owner', 'manager', 'cashier'].contains(role) &&
        verified != null &&
        !clock.isBefore(verified) &&
        clock.difference(verified) < const Duration(hours: 24);
  }

  /// Local receipt, stock deduction, and durable outbox entry commit together.
  Future<String> checkout(
    Map<String, int> quantities,
    int cashCents, {
    DateTime? now,
    ReceiptDetails? fallbackReceiptDetails,
  }) async {
    if (!await canSell(now: now)) {
      throw StateError('Connect to renew selling access.');
    }
    if (quantities.isEmpty || quantities.length > 200) {
      throw ArgumentError('Empty or oversized cart');
    }
    final device = await meta('device_id');
    return db.transaction((tx) async {
      final branding = await tx.query(
        'metadata',
        where: 'key = ?',
        whereArgs: ['receipt_details'],
      );
      final details = branding.isEmpty
          ? fallbackReceiptDetails
          : ReceiptDetails.fromJson(
              jsonDecode(branding.single['value'] as String)
                  as Map<String, dynamic>,
            );
      details?.checkScope(businessId, branchId);
      final items = <Map<String, Object?>>[];
      var total = 0;
      for (final entry in quantities.entries) {
        final rows = await tx.query(
          'products',
          where: 'id = ?',
          whereArgs: [entry.key],
        );
        if (rows.isEmpty ||
            entry.value < 1 ||
            entry.value > 100000 ||
            (rows.first['quantity'] as int) < entry.value) {
          throw StateError('Insufficient local stock');
        }
        final row = rows.first;
        final price = row['price_cents'] as int;
        total += price * entry.value;
        items.add({
          'product_id': entry.key,
          'name': row['name'],
          'sku': row['sku'],
          'quantity': entry.value,
          'unit_cents': price,
        });
        await tx.rawUpdate(
          'UPDATE products SET quantity = quantity - ? WHERE id = ?',
          [entry.value, entry.key],
        );
      }
      if (cashCents < total || total > 9000000000000) {
        throw ArgumentError('Insufficient cash');
      }
      final id = WorkspaceRepository.newRequestId();
      final payload = {
        'id': id,
        'business_id': businessId,
        'branch_id': branchId,
        'device_id': device,
        'occurred_at': (now ?? DateTime.now()).toUtc().toIso8601String(),
        'cash_cents': cashCents,
        'items': items,
        if (details != null) 'receipt_details': details.toJson(),
      };
      await tx.insert('sales', {
        'id': id,
        'payload': jsonEncode(payload),
        'total_cents': total,
        'status': 'pending',
      });
      return id;
    });
  }

  Future<void> setStatus(String id, String status, {String? error}) async {
    if (!['pending', 'synced', 'blocked'].contains(status)) {
      throw ArgumentError('Invalid sync status');
    }
    await db.update(
      'sales',
      {'status': status, 'error': error},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> close() => db.close();
}
