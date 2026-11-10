import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../workspaces/workspace_repository.dart';
import '../core/receipt_details.dart';
import 'checkout_quote.dart';
import 'receipt_history.dart';

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
        version: 3,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await db.execute(
            "CREATE TABLE products (id TEXT PRIMARY KEY, name TEXT NOT NULL, sku TEXT NOT NULL, price_cents INTEGER NOT NULL, quantity INTEGER NOT NULL, category_id TEXT NOT NULL DEFAULT '', category_name TEXT NOT NULL DEFAULT '')",
          );
          await db.execute(
            "CREATE TABLE sales (id TEXT PRIMARY KEY, payload TEXT NOT NULL, total_cents INTEGER NOT NULL, status TEXT NOT NULL DEFAULT 'pending', error TEXT, upload_attempts INTEGER NOT NULL DEFAULT 0, retry_after_ms INTEGER)",
          );
          await db.execute('CREATE INDEX sales_status ON sales(status)');
        },
        onUpgrade: (db, oldVersion, _) async {
          if (oldVersion < 2) {
            await db.execute(
              "ALTER TABLE products ADD COLUMN category_id TEXT NOT NULL DEFAULT ''",
            );
            await db.execute(
              "ALTER TABLE products ADD COLUMN category_name TEXT NOT NULL DEFAULT ''",
            );
            await db.execute('CREATE INDEX sales_status ON sales(status)');
          }
          if (oldVersion < 3) {
            await db.execute(
              'ALTER TABLE sales ADD COLUMN upload_attempts INTEGER NOT NULL DEFAULT 0',
            );
            await db.execute(
              'ALTER TABLE sales ADD COLUMN retry_after_ms INTEGER',
            );
          }
        },
      ),
    );
    final store = LocalStore._(db, userId, businessId, branchId);
    if (await store.meta('device_id') == null) {
      await db.insert('metadata', {
        'key': 'device_id',
        'value': WorkspaceRepository.newRequestId(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    return store;
  }

  Future<String?> meta(String key) => _meta(db, key);
  Future<String> get deviceId async => (await meta('device_id'))!;

  Future<String?> _meta(DatabaseExecutor database, String key) async {
    final rows = await database.query(
      'metadata',
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setMeta(String key, String value) => db
      .insert('metadata', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace)
      .then((_) {});

  String _cashReturnKey(String saleId) => 'cash_return:$saleId';

  Future<String?> pendingCashReturn(String saleId) =>
      meta(_cashReturnKey(saleId));

  Future<String> rememberCashReturn(
    String saleId,
    Map<String, Object> params,
  ) async {
    final key = _cashReturnKey(saleId);
    return db.transaction((tx) async {
      await _requireDrawerReady(tx);
      final shift = await _meta(tx, 'cash_shift_id');
      final request = jsonEncode({
        ...params,
        if (shift != null) 'p_shift': shift,
        if (shift != null) 'p_device': (await _meta(tx, 'device_id'))!,
      });
      await tx.insert('metadata', {
        'key': key,
        'value': request,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      final saved = await tx.query(
        'metadata',
        where: 'key = ?',
        whereArgs: [key],
      );
      if (saved.single['value'] != request) {
        throw const FormatException(
          'Check the saved return request before starting another.',
        );
      }
      return request;
    });
  }

  Future<void> clearCashReturn(String saleId, String request) async {
    await db.delete(
      'metadata',
      where: 'key = ? AND value = ?',
      whereArgs: [_cashReturnKey(saleId), request],
    );
  }

  Future<void> _requireDrawerReady(DatabaseExecutor database) async {
    if (await _meta(database, 'cash_shift_request') != null) {
      throw const FormatException(
        'Resolve the saved request in Cash shift first.',
      );
    }
  }

  Future<String?> pendingCashShift() => meta('cash_shift_request');

  Future<void> rememberCashShift(
    String request, {
    required String? activeShift,
    required bool closing,
  }) async {
    await db.transaction((tx) async {
      await _requireDrawerReady(tx);
      if (await _meta(tx, 'cash_shift_id') != activeShift) {
        throw const FormatException(
          'Cash shift changed. Refresh and try again.',
        );
      }
      if (closing) {
        final unresolved = await tx.query(
          'sales',
          columns: ['payload'],
          where: "status IN ('pending', 'blocked')",
        );
        if (unresolved.any(
          (row) =>
              (jsonDecode(row['payload'] as String) as Map)['cash_shift_id'] ==
              activeShift,
        )) {
          throw const FormatException(
            'Sync or resolve all receipts for this shift before closing.',
          );
        }
      }
      if (closing || activeShift == null) {
        final returns = await tx.query(
          'metadata',
          columns: ['key'],
          where: "key LIKE 'cash_return:%'",
          limit: 1,
        );
        if (returns.isNotEmpty) {
          throw const FormatException(
            'Resolve the saved cash return before opening or closing a shift.',
          );
        }
      }
      await tx.insert('metadata', {
        'key': 'cash_shift_request',
        'value': request,
      });
    });
  }

  Future<void> updateCashShift(
    String? activeShift, {
    required String? previousShift,
    String? completedRequest,
  }) async {
    await db.transaction((tx) async {
      if (await _meta(tx, 'cash_shift_request') != completedRequest ||
          await _meta(tx, 'cash_shift_id') != previousShift) {
        return;
      }
      if (activeShift == null) {
        await tx.delete(
          'metadata',
          where: 'key = ?',
          whereArgs: ['cash_shift_id'],
        );
      } else {
        await tx.insert('metadata', {
          'key': 'cash_shift_id',
          'value': activeShift,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      if (completedRequest != null) {
        await tx.delete(
          'metadata',
          where: 'key = ?',
          whereArgs: ['cash_shift_request'],
        );
      }
    });
  }

  Future<List<Map<String, Object?>>> products() =>
      db.query('products', orderBy: 'name');
  Future<List<Map<String, Object?>>> receipts() =>
      db.query('sales', orderBy: 'rowid DESC');

  Future<ReceiptCounts> receiptCounts() async {
    final rows = await db.rawQuery(
      'SELECT status, COUNT(*) AS total FROM sales GROUP BY status',
    );
    final counts = {
      for (final row in rows) row['status'] as String: row['total'] as int,
    };
    return ReceiptCounts(
      pending: counts['pending'] ?? 0,
      synced: counts['synced'] ?? 0,
      blocked: counts['blocked'] ?? 0,
    );
  }

  /// Cursor pages exclude receipt payloads; load one payload only when opened.
  Future<ReceiptPage> receiptPage({
    String? status,
    int? before,
    int limit = 30,
  }) async {
    if (limit < 1 ||
        limit > 100 ||
        (before != null && before < 1) ||
        (status != null &&
            !['pending', 'synced', 'blocked'].contains(status))) {
      throw ArgumentError('Invalid receipt page');
    }
    final clauses = <String>[], args = <Object?>[];
    if (status != null) {
      clauses.add('status = ?');
      args.add(status);
    }
    if (before != null) {
      clauses.add('rowid < ?');
      args.add(before);
    }
    final rows = await db.rawQuery(
      'SELECT rowid AS sequence, id, total_cents, status, error FROM sales ${clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}'} ORDER BY rowid DESC LIMIT ?',
      [...args, limit + 1],
    );
    final entries = rows.take(limit).map(SavedReceipt.new).toList();
    return ReceiptPage(
      entries,
      rows.length > limit ? entries.last.sequence : null,
    );
  }

  Future<List<Map<String, Object?>>> pendingReceipts({int? limit}) => db.query(
    'sales',
    where: 'status = ?',
    whereArgs: ['pending'],
    orderBy: 'rowid',
    limit: limit,
  );

  Future<bool> hasPendingReceipts() async => (await db.query(
    'sales',
    columns: ['id'],
    where: 'status = ?',
    whereArgs: ['pending'],
    limit: 1,
  )).isNotEmpty;

  Future<void> deferUpload(String id, int attempts, DateTime retryAfter) async {
    await db.update(
      'sales',
      {
        'upload_attempts': attempts,
        'retry_after_ms': retryAfter.millisecondsSinceEpoch,
        'error':
            'Upload not confirmed. The original receipt is saved for retry.',
      },
      where: "id = ? AND status = 'pending'",
      whereArgs: [id],
    );
  }

  Future<void> finishUpload(String id, {String? reviewReason}) async {
    await db.update(
      'sales',
      {
        'status': reviewReason == null ? 'synced' : 'blocked',
        'error': reviewReason,
        'retry_after_ms': null,
      },
      where: "id = ? AND status = 'pending'",
      whereArgs: [id],
    );
  }

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
    return _canSell(db, now: now);
  }

  Future<bool> _canSell(DatabaseExecutor database, {DateTime? now}) async {
    final rows = await database.query(
      'metadata',
      where: 'key IN (?, ?, ?)',
      whereArgs: ['verified_at', 'role', 'revoked'],
    );
    final values = {
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
    final verified = DateTime.tryParse(values['verified_at'] ?? '');
    final clock = (now ?? DateTime.now()).toUtc();
    final role = values['role'];
    return values['revoked'] != 'true' &&
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
    CheckoutQuote? quote,
    bool Function()? isActive,
  }) async {
    quantities = Map<String, int>.of(quantities);
    quote?.checkScope(userId, businessId, branchId);
    quote?.checkQuantities(quantities);
    if (quantities.isEmpty || quantities.length > 200) {
      throw ArgumentError('Empty or oversized cart');
    }
    return db.transaction((tx) async {
      void checkActive() {
        if (isActive?.call() == false) throw StateError('Account changed.');
      }

      checkActive();
      if (quote != null) {
        final saved = await tx.query(
          'sales',
          where: 'id = ?',
          whereArgs: [quote.attemptId],
          limit: 1,
        );
        if (saved.isNotEmpty) {
          if (!quote.matchesSaved(
                jsonDecode(saved.single['payload'] as String)
                    as Map<String, dynamic>,
                cashCents,
              ) ||
              saved.single['total_cents'] != quote.totalCents) {
            throw const FormatException(
              'This checkout was already saved with different details.',
            );
          }
          checkActive();
          return quote.attemptId;
        }
      }
      if (!await _canSell(tx, now: now)) {
        throw StateError('Connect to renew selling access.');
      }
      await _requireDrawerReady(tx);
      final cashShift = await _meta(tx, 'cash_shift_id');
      checkActive();
      final deviceRows = await tx.query(
        'metadata',
        where: 'key = ?',
        whereArgs: ['device_id'],
      );
      final device = deviceRows.isEmpty ? null : deviceRows.single['value'];
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
        if (quote != null) {
          final quoted = quote.lines.where((line) => line.id == entry.key);
          if (rows.isEmpty ||
              quoted.length != 1 ||
              quoted.single.quantity != entry.value ||
              quote.lines.length != quantities.length ||
              !quoted.single.matches(rows.first)) {
            throw const CheckoutChanged();
          }
        }
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
        checkActive();
        await tx.rawUpdate(
          'UPDATE products SET quantity = quantity - ? WHERE id = ?',
          [entry.value, entry.key],
        );
      }
      if (cashCents < total || total > 9000000000000) {
        throw ArgumentError('Insufficient cash');
      }
      final id = quote?.attemptId ?? WorkspaceRepository.newRequestId();
      final payload = {
        'id': id,
        'business_id': businessId,
        'branch_id': branchId,
        'device_id': device,
        'occurred_at': (now ?? DateTime.now()).toUtc().toIso8601String(),
        'cash_cents': cashCents,
        if (cashShift != null) 'cash_shift_id': cashShift,
        'items': items,
        if (details != null) 'receipt_details': details.toJson(),
      };
      checkActive();
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
      {'status': status, 'error': error, 'retry_after_ms': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> close() => db.close();
}
