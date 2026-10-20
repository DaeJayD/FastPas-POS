import 'package:supabase_flutter/supabase_flutter.dart';

import '../catalog/catalog_source.dart';
import '../core/store_connection.dart';

class BranchBrand {
  const BranchBrand({
    required this.id,
    required this.name,
    this.description = '',
  });
  final String id;
  final String name;
  final String description;
  factory BranchBrand.fromRow(Map<String, dynamic> row) => BranchBrand(
    id: row['id'].toString(),
    name: row['name']?.toString() ?? 'Unnamed brand',
    description: row['description']?.toString() ?? '',
  );
}

class StockWarning {
  const StockWarning(this.name, this.quantity, this.threshold);
  final String name;
  final int quantity;
  final int threshold;
}

class BranchEvent {
  const BranchEvent(this.id, this.date, this.description);
  final String id;
  final DateTime date;
  final String description;
}

/// Adapts the current schema. Branch identity is always explicit in queries.
class BranchRepository {
  BranchRepository({SupabaseClient? client})
    : _client = client ?? StoreConnection.client;
  final SupabaseClient _client;

  Future<List<StoreBranch>> branches() async {
    final rows = await _client
        .from('branches')
        .select('id, name, location')
        .order('name');
    return [
      for (final row in rows)
        StoreBranch(
          id: row['id'].toString(),
          name: (row['name'] ?? row['location'] ?? 'Branch').toString(),
          location: (row['location'] ?? row['name'] ?? '').toString(),
        ),
    ];
  }

  Future<StoreBranch> findByName(String name) async {
    final row = await _client
        .from('branches')
        .select('id, name, location')
        .eq('name', name)
        .single();
    return StoreBranch(
      id: row['id'].toString(),
      name: row['name'].toString(),
      location: (row['location'] ?? row['name']).toString(),
    );
  }

  Future<List<BranchBrand>> brands(String branchId) async {
    final rows = await _client
        .from('branch_brands')
        .select('brands:brand_id(id, name, description)')
        .eq('branch_id', branchId)
        .order('brands(name)');
    return [
      for (final row in rows)
        if (row['brands'] is Map<String, dynamic>)
          BranchBrand.fromRow(row['brands'] as Map<String, dynamic>),
    ];
  }

  Future<List<StockWarning>> warnings(String branchId) async {
    final rows = await _client
        .from('branch_stock')
        .select('current_stock, low_stock_threshold, products(name)')
        .eq('branch_id', branchId);
    return [
      for (final row in rows)
        if (((row['current_stock'] as num?)?.toInt() ?? 0) <=
            ((row['low_stock_threshold'] as num?)?.toInt() ?? 10))
          StockWarning(
            row['products']?['name']?.toString() ?? 'Unnamed product',
            (row['current_stock'] as num?)?.toInt() ?? 0,
            (row['low_stock_threshold'] as num?)?.toInt() ?? 10,
          ),
    ];
  }

  Future<List<BranchEvent>> events(String branchId) async {
    final rows = await _client
        .from('calendar_events')
        .select('id, event_date, description')
        .eq('branch_id', branchId)
        .order('event_date');
    return [
      for (final row in rows)
        if (DateTime.tryParse(row['event_date']?.toString() ?? '')
            case final date?)
          BranchEvent(
            row['id'].toString(),
            date,
            row['description']?.toString() ?? '',
          ),
    ];
  }

  Future<void> addBrand(
    String branchId,
    String name,
    String description,
  ) async {
    final row = await _client
        .from('brands')
        .insert({
          'name': name,
          'description': description.isEmpty ? null : description,
        })
        .select('id')
        .single();
    await _client.from('branch_brands').insert({
      'branch_id': branchId,
      'brand_id': row['id'],
    });
  }

  Future<void> removeBrand(String branchId, String brandId) async {
    await _client
        .from('branch_brands')
        .delete()
        .eq('branch_id', branchId)
        .eq('brand_id', brandId);
  }
}
