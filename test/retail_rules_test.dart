import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vasenizzpos/branches/branch_repository.dart';
import 'package:vasenizzpos/core/pos_session.dart';
import 'package:vasenizzpos/inventory/stock_repository.dart';
import 'package:vasenizzpos/reports/report_repository.dart';
import 'package:vasenizzpos/sales/sale_models.dart';
import 'package:vasenizzpos/sales/sales_repository.dart';

const session = PosSession(
  fullName: 'Alex Santos',
  role: 'owner',
  userId: 'u1',
  location: 'Main',
);
const lines = [
  SaleLine(
    productId: 'p1',
    name: 'Water',
    unitPrice: 25,
    quantity: 2,
    stock: 4,
  ),
];

void main() {
  test('checkout retains subtotal tax and discount ordering', () {
    final totals = SaleTotals.calculate(lines, discountPercent: 10);
    expect(totals.subtotal, 50);
    expect(totals.tax, 6);
    expect(totals.discount, 5);
    expect(totals.total, 51);
  });
  test('empty cart and full discount keep the existing tax rule', () {
    expect(SaleTotals.calculate([]).total, 0);
    expect(SaleTotals.calculate(lines, discountPercent: 100).total, 6);
  });
  test('non-finite rates and invalid lines are rejected', () {
    for (final rate in [-1.0, 101.0, double.nan, double.infinity]) {
      expect(
        () => SaleTotals.calculate(lines, discountPercent: rate),
        throwsArgumentError,
      );
    }
    expect(
      () => SaleTotals.calculate([
        const SaleLine(productId: 'p', name: 'P', unitPrice: 25, quantity: -1),
      ]),
      throwsArgumentError,
    );
  });
  test('cart adapter round-trips price quantity stock and identity', () {
    final item = SaleLine.fromCart(lines.single.toCart());
    expect(item.productId, 'p1');
    expect(item.quantity, 2);
    expect(item.stock, 4);
    expect(item.amount, 50);
  });
  test(
    'previous and current report periods have no boundary gap or overlap',
    () {
      final period = ReportPeriod(
        DateTime(2026, 10, 13),
        DateTime(2026, 10, 20),
      );
      final report = SalesReport.summarize([
        ReportSale(period.start.subtract(const Duration(milliseconds: 1)), 40),
        ReportSale(period.start, 60),
        ReportSale(period.end, 1000),
      ], period);
      expect(report.total, 60);
      expect(report.previousTotal, 40);
      expect(report.orders, 1);
      expect(report.changePercent, 50);
    },
  );
  test(
    'report daily totals include seven calendar days and no future sales',
    () {
      final now = DateTime(2026, 10, 20, 12);
      final report = SalesReport.summarize([
        ReportSale(DateTime(2026, 10, 14), 10),
        ReportSale(DateTime(2026, 10, 20, 9), 20),
        ReportSale(DateTime(2026, 10, 20, 13), 999),
      ], ReportPeriod.forLabel('1W', now));
      expect(report.dailyTotals, [10, 0, 0, 0, 0, 0, 20]);
      expect(report.orders, 2);
    },
  );
  test('zero previous sales uses the existing change display rule', () {
    expect(const SalesReport().changePercent, 0);
    expect(const SalesReport(total: 50).changePercent, 100);
  });
  test('report pagination includes sales beyond the first page', () async {
    final offsets = <int>[];
    final client = SupabaseClient(
      'https://test.invalid',
      'test',
      httpClient: MockClient((request) async {
        final table = request.url.pathSegments.last;
        final offset =
            int.tryParse(request.url.queryParameters['offset'] ?? '0') ?? 0;
        if (table == 'sales') offsets.add(offset);
        final rows = table == 'sales'
            ? List.generate(
                offset == 0 ? 500 : 1,
                (index) => {
                  'id': '${offset + index}',
                  'total_amount': 1,
                  'created_at': '2026-10-20T09:00:00',
                },
              )
            : [];
        return http.Response(
          jsonEncode(rows),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final report = await ReportRepository(client: client)
        .load('1W', now: DateTime(2026, 10, 20, 12));
    expect(offsets, [0, 500]);
    expect(report.orders, 501);
    expect(report.total, 501);
    await client.dispose();
  });
  test(
    'branch lookup uses the selected name rather than a fixed city',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://test.invalid',
        'test',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({'id': 'depot', 'name': 'Depot', 'location': 'West'}),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final branch = await BranchRepository(client: client).findByName('Depot');
      expect(branch.id, 'depot');
      expect(requests.single.url.queryParameters['name'], 'eq.Depot');
      await client.dispose();
    },
  );
  test(
    'stock movement keeps branch filters and signed quantities consistent',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://test.invalid',
        'test',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response('', 204, request: request);
        }),
      );
      await StockRepository(client: client).adjust(
        const StockAdjustment(
          productId: 'p1',
          branchId: 'b2',
          previousStock: 5,
          delta: -2,
          userId: 'u1',
          username: 'Alex',
        ),
      );
      expect(requests.first.url.queryParameters['branch_id'], 'eq.b2');
      final movement = jsonDecode(requests.last.body);
      expect(movement['quantity'], 2);
      expect(movement['movement_type'], 'out');
      expect(movement['previous_stock'], 5);
      expect(movement['new_stock'], 3);
      await client.dispose();
    },
  );
  test('invalid stock adjustment fails before sending requests', () async {
    var count = 0;
    final client = SupabaseClient(
      'https://test.invalid',
      'test',
      httpClient: MockClient((request) async {
        count++;
        return http.Response('', 204, request: request);
      }),
    );
    await expectLater(
      StockRepository(client: client).adjust(
        const StockAdjustment(
          productId: 'p1',
          branchId: 'b1',
          previousStock: 1,
          delta: -2,
          userId: 'u',
          username: 'Alex',
        ),
      ),
      throwsArgumentError,
    );
    expect(count, 0);
    await client.dispose();
  });
  test(
    'sale records line items and scopes stock updates to its branch',
    () async {
      final requests = <http.Request>[];
      final client = _salesClient(requests);
      final saved = await SalesRepository(client: client).record(_draft());
      expect(saved.id, 'sale1');
      expect(saved.stockWarnings, 0);
      final stockRequests = requests.where(
        (request) => request.url.path.endsWith('/branch_stock'),
      );
      expect(stockRequests.length, 2);
      for (final request in stockRequests) {
        expect(request.url.queryParameters['branch_id'], 'eq.b1');
      }
      final items = jsonDecode(
        requests
            .firstWhere(
              (request) =>
                  request.method == 'POST' &&
                  request.url.path.endsWith('/sale_items'),
            )
            .body,
      ) as List;
      expect(items.single['quantity'], 2);
      expect(items.single['total_price'], 50);
      await client.dispose();
    },
  );
  test('stock update failure is reported with the saved sale', () async {
    final requests = <http.Request>[];
    final client = _salesClient(requests, stockFailure: true);
    final saved = await SalesRepository(client: client).record(_draft());
    expect(saved.id, 'sale1');
    expect(saved.stockWarnings, 1);
    await client.dispose();
  });
  test('sample sale is rejected before any persistence', () async {
    final requests = <http.Request>[];
    final client = _salesClient(requests);
    await expectLater(
      SalesRepository(client: client).record(_draft(preview: true)),
      throwsStateError,
    );
    expect(requests, isEmpty);
    await client.dispose();
  });
}

SaleDraft _draft({bool preview = false}) => SaleDraft(
  session: preview
      ? const PosSession(
          fullName: 'Alex',
          role: 'owner',
          userId: 'u1',
          location: 'Main',
          preview: true,
        )
      : session,
  lines: lines,
  totals: SaleTotals.calculate(lines),
  paymentMethod: 'Cash',
  cashGiven: 100,
  change: 44,
);

SupabaseClient _salesClient(
  List<http.Request> requests, {
  bool stockFailure = false,
}) => SupabaseClient(
  'https://test.invalid',
  'test',
  httpClient: MockClient((request) async {
    requests.add(request);
    final table = request.url.pathSegments.last;
    if (table == 'branch_stock' && stockFailure) {
      return http.Response(
        jsonEncode({'message': 'Unavailable'}),
        503,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    }
    final Object? result = switch ((table, request.method)) {
      ('branches', 'GET') => [
        {'id': 'b1', 'name': 'Main', 'location': 'Main'},
      ],
      ('sales', 'POST') => {'id': 'sale1'},
      ('branch_stock', 'GET') => {'id': 'stock1', 'current_stock': 4},
      _ => null,
    };
    return http.Response(
      result == null ? '' : jsonEncode(result),
      result == null ? 204 : 200,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }),
);
