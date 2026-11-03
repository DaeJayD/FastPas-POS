import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

class CatalogLabel {
  CatalogLabel(Map<String, dynamic> row, this.kind, String business)
    : id = row['id'] as String,
      name = row['name'] as String,
      version = row['version'] as int,
      active = row['active'] as bool {
    if (row['business_id'] != business) {
      throw StateError('Catalog scope changed');
    }
  }
  final String id, name, kind;
  final int version;
  final bool active;
}

class CatalogItem {
  CatalogItem(Map<String, dynamic> row, String business)
    : id = row['id'] as String,
      name = row['name'] as String,
      baseName = (row['base_name'] as String?)?.isNotEmpty == true
          ? row['base_name'] as String
          : row['name'] as String,
      sku = row['sku'] as String,
      price = (row['price_cents'] as num).toInt(),
      quantity = (row['quantity'] as num).toInt(),
      version = row['version'] as int,
      stockVersion = (row['stock_version'] as num).toInt(),
      threshold = (row['low_stock_threshold'] as num).toInt(),
      active = row['active'] as bool,
      brand = row['brand_id'] as String?,
      category = row['category_id'] as String?,
      family = row['family_id'] as String?,
      variant = row['variant_label'] as String {
    if (row['business_id'] != business) {
      throw StateError('Product scope changed');
    }
  }
  final String id, name, baseName, sku, variant;
  final String? brand, category, family;
  final int price, quantity, version, stockVersion, threshold;
  final bool active;
}

/// Scoped to one Owner account and business. Writes are never retried here.
class CatalogRepository {
  CatalogRepository(this.client, this.business)
    : _actor = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String business;
  final String? _actor;
  void checkIdentity() {
    if (_actor == null || client.auth.currentUser?.id != _actor) {
      throw const FormatException('Account changed. Return to Businesses.');
    }
  }

  Future<dynamic> _call(String name, Map<String, dynamic> args) async {
    checkIdentity();
    final result = await client
        .rpc(name, params: {'business': business, ...args})
        .timeout(const Duration(seconds: 12));
    checkIdentity();
    return result;
  }

  Future<List<CatalogLabel>> labels() async {
    final data = Map<String, dynamic>.from(
      await _call('pos_catalog_labels', {}),
    );
    if (data['business_id'] != business) {
      throw StateError('Catalog scope changed');
    }
    return [
      for (final entry in {
        'brand': 'brands',
        'category': 'categories',
        'family': 'families',
      }.entries)
        for (final row in data[entry.value] as List)
          CatalogLabel(
            Map<String, dynamic>.from(row as Map),
            entry.key,
            business,
          ),
    ];
  }

  Future<List<CatalogItem>> items(
    String branch, {
    int offset = 0,
    String search = '',
    bool archived = false,
  }) async {
    final rows = await _call('pos_catalog_items', {
      'branch': branch,
      'page_offset': offset,
      'page_size': 50,
      'search_text': search,
      'include_archived': archived,
    }) as List;
    return rows
        .map(
          (row) => CatalogItem(Map<String, dynamic>.from(row as Map), business),
        )
        .toList();
  }

  Future<void> saveLabel(
    String requestId,
    String id,
    String kind,
    int version,
    String name,
    bool active,
  ) async {
    await _call('pos_save_catalog_label', {
      'request_id': requestId,
      'label_id': id,
      'kind': kind,
      'expected_version': version,
      'label_name': name,
      'enabled': active,
    });
  }

  Future<void> saveItem(String requestId, Map<String, dynamic> item) async {
    await _call('pos_save_catalog_item', {
      'request_id': requestId,
      'item': item,
    });
  }

  Future<int> stockVersion(String branch, String product) async {
    checkIdentity();
    final row = await client
        .from('pos_item_stock')
        .select('stock_version')
        .eq('business_id', business)
        .eq('branch_id', branch)
        .eq('product_id', product)
        .maybeSingle()
        .timeout(const Duration(seconds: 12));
    checkIdentity();
    return (row?['stock_version'] as num?)?.toInt() ?? 0;
  }

  Future<void> postStock(String requestId, Map<String, dynamic> change) async {
    await _call('pos_post_stock', {'request_id': requestId, 'change': change});
  }

  Future<List<Map<String, dynamic>>> history(
    String branch, {
    String? product,
    int offset = 0,
  }) async {
    final rows = await _call('pos_stock_history', {
      'branch': branch,
      'product': product,
      'page_offset': offset,
      'page_size': 50,
    }) as List;
    final result = rows
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    if (result.any(
      (row) => row['business_id'] != business || row['branch_id'] != branch,
    )) {
      throw StateError('Movement scope changed');
    }
    return result;
  }
}
