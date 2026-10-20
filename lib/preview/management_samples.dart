import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/store_connection.dart';

/// A local transport for exercising the real management layouts. It has no
/// network fallback and rejects every write, upload, auth, or RPC request.
class SampleStoreTransport extends http.BaseClient {
  int rejectedWrites = 0;
  final now = DateTime.now();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method != 'GET' || !request.url.path.startsWith('/rest/v1/')) {
      rejectedWrites++;
      return _response(request, 403, {
        'message': 'Sample view is read-only. Changes are not saved.',
      });
    }
    final table = request.url.pathSegments.last;
    var rows = _tables[table] ?? <Map<String, dynamic>>[];
    for (final entry in request.url.queryParametersAll.entries) {
      if (['select', 'order', 'limit', 'offset'].contains(entry.key) ||
          entry.key.contains('.')) {
        continue;
      }
      for (final filter in entry.value) {
        final split = filter.indexOf('.');
        if (split < 0) continue;
        final op = filter.substring(0, split);
        final value = filter.substring(split + 1);
        rows = rows.where((row) {
          final actual = row[entry.key]?.toString();
          if (actual == null) return false;
          return switch (op) {
            'eq' => actual == value,
            'gte' => actual.compareTo(value) >= 0,
            'lte' => actual.compareTo(value) <= 0,
            'lt' => actual.compareTo(value) < 0,
            'gt' => actual.compareTo(value) > 0,
            _ => true,
          };
        }).toList();
      }
    }
    final single =
        request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    return _response(
      request,
      200,
      single ? (rows.isEmpty ? null : rows.first) : rows,
    );
  }

  http.StreamedResponse _response(
    http.BaseRequest request,
    int status,
    Object? data,
  ) => http.StreamedResponse(
    Stream.value(utf8.encode(jsonEncode(data))),
    status,
    request: request,
    headers: {'content-type': 'application/json'},
  );

  Map<String, List<Map<String, dynamic>>> get _tables {
    final date = now.toIso8601String().split('T').first;
    final stamp = now.subtract(const Duration(minutes: 30)).toIso8601String();
    final product = {
      'id': 'p1',
      'name': 'Bottled water',
      'price': 25.0,
      'sku': 'DR-001',
      'brand_id': 'brand1',
      'category_id': 'cat1',
      'categories': {'id': 'cat1', 'name': 'Drinks'},
      'brands': {'id': 'brand1', 'name': 'Everyday'},
      'branch_stock': [
        {
          'current_stock': 4,
          'low_stock_threshold': 10,
          'branches': {'id': 'b1', 'name': 'Main Branch'},
        },
      ],
    };
    final branch = {
      'id': 'b1',
      'name': 'Main Branch',
      'location': 'Main Branch',
    };
    final employee = {
      'id': 'e1',
      'user_id': 'preview',
      'name': 'Alex Santos',
      'role': 'owner',
      'branch': 'Main Branch',
      'phone': '09123456789',
      'dob': '2000-01-01',
      'username': 'alex',
      'status': 'active',
      'is_active': true,
    };
    return {
      'branches': [
        branch,
        {'id': 'b2', 'name': 'North Branch', 'location': 'North Branch'},
        for (final name in ['CARMEN BRANCH', 'JASAAN BRANCH', 'PUERTO BRANCH'])
          {'id': name, 'name': name, 'location': name},
      ],
      'employees': [employee],
      'suppliers': [
        {
          'id': 'supplier1',
          'name': 'Everyday Supply Co.',
          'company_name': 'Everyday Supply Co.',
          'contact_person': 'Sam Reyes',
          'phone': '09123456780',
          'email': 'orders@example.com',
          'created_at': stamp,
        },
      ],
      'products': [product],
      'brands': [
        {
          'id': 'brand1',
          'name': 'Everyday',
          'description': 'Everyday essentials',
        },
      ],
      'categories': [
        {'id': 'cat1', 'name': 'Drinks', 'brand_id': 'brand1'},
      ],
      'branch_brands': [
        for (final name in ['CARMEN BRANCH', 'JASAAN BRANCH', 'PUERTO BRANCH'])
          {
            'branch_id': name,
            'brand_id': 'brand1',
            'brands': {
              'id': 'brand1',
              'name': 'Everyday',
              'description': 'Everyday essentials',
            },
          },
        {
          'branch_id': 'b1',
          'brand_id': 'brand1',
          'brands': {'id': 'brand1', 'name': 'Everyday'},
          'branch_stock': [
            {
              'current_stock': 4,
              'low_stock_threshold': 10,
              'branches': {'id': 'b1', 'name': 'Main Branch'},
            },
          ],
        },
      ],
      'branch_stock': [
        {
          'id': 'stock1',
          'branch_id': 'b1',
          'product_id': 'p1',
          'current_stock': 4,
          'low_stock_threshold': 10,
          'products': product,
          'branches': branch,
        },
      ],
      'sales': [
        {
          'id': 'sample-sale-001',
          'created_at': stamp,
          'total_amount': 56.0,
          'subtotal_amount': 50.0,
          'tax_amount': 6.0,
          'discount_amount': 0.0,
          'payment_method': 'cash',
          'cash_given': 100.0,
          'change': 44.0,
          'branch_location': 'Main Branch',
          'cashier_name': 'Alex Santos',
          'cashier_role': 'owner',
        },
      ],
      'sale_items': [
        {
          'sale_id': 'sample-sale-001',
          'product_id': 'p1',
          'quantity': 2,
          'unit_price': 25.0,
          'total_price': 50.0,
          'created_at': stamp,
          'products': product,
        },
      ],
      'attendance': [
        {
          'id': 'att1',
          'user_id': 'preview',
          'date': date,
          'time_in': '${date}T08:00:00',
          'time_out': null,
          'employees': employee,
        },
      ],
      'calendar_events': [],
      'inventory_history': [],
      'supplier_products': [],
    };
  }
}

SampleStoreTransport enableManagementSamples() {
  final transport = SampleStoreTransport();
  StoreConnection.previewClient = SupabaseClient(
    'https://preview.invalid',
    'preview-only',
    httpClient: transport,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  return transport;
}
