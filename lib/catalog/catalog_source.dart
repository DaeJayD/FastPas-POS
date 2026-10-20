import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/store_connection.dart';

String pesos(num value) => NumberFormat.currency(
  locale: 'en_PH',
  symbol: '₱',
  decimalDigits: 2,
).format(value);

bool isStoreManager(String role) =>
    const ['owner', 'admin', 'manager'].contains(role.toLowerCase().trim());

class StoreBranch {
  const StoreBranch({
    required this.id,
    required this.name,
    required this.location,
  });
  final String id;
  final String name;
  final String location;
}

class CatalogProduct {
  const CatalogProduct({
    required this.id,
    required this.name,
    required this.price,
    required this.stock,
    required this.sku,
    required this.category,
    this.brand = '',
  });
  final String id;
  final String name;
  final double price;
  final int stock;
  final String sku;
  final String category;
  final String brand;

  IconData get icon {
    final text = '$category $name'.toLowerCase();
    if (text.contains('coffee')) return Icons.coffee_outlined;
    if (text.contains('water') || text.contains('drink')) {
      return Icons.water_drop_outlined;
    }
    if (text.contains('cookie') || text.contains('food')) {
      return Icons.cookie_outlined;
    }
    if (text.contains('soap') || text.contains('beauty')) {
      return Icons.spa_outlined;
    }
    if (text.contains('pen') || text.contains('stationery')) {
      return Icons.edit_outlined;
    }
    return Icons.inventory_2_outlined;
  }

  Map<String, dynamic> toCartItem(int quantity) => {
    'id': id,
    'name': name,
    'price': price,
    'stock': stock,
    'sku': sku,
    'category': category,
    'brand': brand,
    'cart_quantity': quantity,
  };
}

abstract class CatalogSource {
  bool get isPreview => false;
  Future<List<StoreBranch>> branches({
    required String userId,
    required String role,
    required String location,
  });
  Future<List<CatalogProduct>> products(String branchId);
}

/// Loads branch-specific products and stock from the existing schema.
class SupabaseCatalogSource extends CatalogSource {
  SupabaseCatalogSource({SupabaseClient? client})
    : _client = client ?? StoreConnection.client;
  final SupabaseClient _client;

  @override
  Future<List<StoreBranch>> branches({
    required String userId,
    required String role,
    required String location,
  }) async {
    var assigned = location;
    if (!isStoreManager(role)) {
      final employee = await _client
          .from('employees')
          .select('branch')
          .eq('user_id', userId)
          .maybeSingle();
      assigned = employee?['branch']?.toString() ?? assigned;
      if (assigned.isEmpty) throw StateError('No branch assigned');
    }
    final rows = await _client
        .from('branches')
        .select('id, name, location')
        .order('name');
    return rows
        .where(
          (row) =>
              isStoreManager(role) ||
              row['location'] == assigned ||
              row['name'] == assigned,
        )
        .map(
          (row) => StoreBranch(
            id: row['id'].toString(),
            name: (row['name'] ?? row['location'] ?? 'Branch').toString(),
            location: (row['location'] ?? row['name'] ?? '').toString(),
          ),
        )
        .toList();
  }

  @override
  Future<List<CatalogProduct>> products(String branchId) async {
    final products = <CatalogProduct>[];
    const pageSize = 500;
    var offset = 0;
    while (true) {
      final rows = await _client
          .from('branch_stock')
          .select('''
        current_stock, product:products(id, name, price, sku,
          category:categories(name), brand:brands(name))
      ''')
          .eq('branch_id', branchId)
          .order('product_id')
          .range(offset, offset + pageSize - 1);
      for (final row in rows) {
        final product = row['product'];
        if (product is! Map) continue;
        products.add(
          CatalogProduct(
            id: product['id'].toString(),
            name: (product['name'] ?? 'Unnamed product').toString(),
            price: (product['price'] as num?)?.toDouble() ?? 0,
            stock: (row['current_stock'] as num?)?.toInt() ?? 0,
            sku: (product['sku'] ?? '').toString(),
            category: (product['category']?['name'] ?? 'Other').toString(),
            brand: (product['brand']?['name'] ?? '').toString(),
          ),
        );
      }
      if (rows.length < pageSize) break;
      offset += pageSize;
    }
    products.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return products;
  }
}
