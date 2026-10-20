import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/store_connection.dart';

class ReportPeriod {
  const ReportPeriod(this.start, this.end);
  final DateTime start, end;
  ReportPeriod get previous =>
      ReportPeriod(start.subtract(end.difference(start)), start);
  bool contains(DateTime value) =>
      !value.isBefore(start) && value.isBefore(end);
  factory ReportPeriod.forLabel(String label, DateTime now) {
    final start = switch (label) {
      '1D' => DateTime(now.year, now.month, now.day),
      '1M' => DateTime(now.year, now.month - 1, now.day),
      '3M' => DateTime(now.year, now.month - 3, now.day),
      '6M' => DateTime(now.year, now.month - 6, now.day),
      '1Yr' => DateTime(now.year - 1, now.month, now.day),
      _ => now.subtract(const Duration(days: 7)),
    };
    return ReportPeriod(start, now);
  }
}

class ReportSale {
  const ReportSale(this.date, this.total);
  final DateTime date;
  final double total;
}

class ProductSales {
  const ProductSales(this.id, this.name, this.quantity, this.price);
  final String id, name;
  final int quantity;
  final double price;
}

class SalesReport {
  const SalesReport({
    this.total = 0,
    this.previousTotal = 0,
    this.orders = 0,
    this.dailyTotals = const [0, 0, 0, 0, 0, 0, 0],
    this.topProducts = const [],
  });
  final double total, previousTotal;
  final int orders;
  final List<double> dailyTotals;
  final List<ProductSales> topProducts;
  double get changePercent => previousTotal > 0
      ? (total - previousTotal) / previousTotal * 100
      : total > 0
      ? 100
      : 0;

  factory SalesReport.summarize(
    Iterable<ReportSale> sales,
    ReportPeriod period, {
    List<ProductSales> topProducts = const [],
  }) {
    var total = 0.0, previous = 0.0, orders = 0;
    final daily = List<double>.filled(7, 0);
    final dayStart = DateTime(
      period.end.year,
      period.end.month,
      period.end.day,
    );
    for (final sale in sales) {
      if (period.contains(sale.date)) {
        total += sale.total;
        orders++;
      }
      if (period.previous.contains(sale.date)) previous += sale.total;
      // Calendar dates avoid daylight-saving duration errors.
      for (var index = 0; index < 7; index++) {
        final day = DateTime(
          dayStart.year,
          dayStart.month,
          dayStart.day - 6 + index,
        );
        final nextDay = DateTime(day.year, day.month, day.day + 1);
        if (!sale.date.isBefore(day) &&
            sale.date.isBefore(nextDay) &&
            sale.date.isBefore(period.end)) {
          daily[index] += sale.total;
          break;
        }
      }
    }
    return SalesReport(
      total: total,
      previousTotal: previous,
      orders: orders,
      dailyTotals: daily,
      topProducts: topProducts,
    );
  }
}

class ReportRepository {
  ReportRepository({SupabaseClient? client})
    : _client = client ?? StoreConnection.client;
  final SupabaseClient _client;

  Future<SalesReport> load(String label, {DateTime? now}) async {
    final period = ReportPeriod.forLabel(label, now ?? DateTime.now());
    final chartStart = DateTime(
      period.end.year,
      period.end.month,
      period.end.day - 6,
    );
    final from = period.previous.start.isBefore(chartStart)
        ? period.previous.start
        : chartStart;
    final sales = <ReportSale>[];
    const pageSize = 500;
    for (var offset = 0; ; offset += pageSize) {
      final rows = await _client
          .from('sales')
          .select('id, total_amount, created_at')
          .gte('created_at', from.toIso8601String())
          .lt('created_at', period.end.toIso8601String())
          .order('created_at')
          .order('id')
          .range(offset, offset + pageSize - 1);
      for (final row in rows) {
        final date = DateTime.tryParse(row['created_at']?.toString() ?? '');
        if (date != null) {
          sales.add(
            ReportSale(
              date.toLocal(),
              (row['total_amount'] as num?)?.toDouble() ?? 0,
            ),
          );
        }
      }
      if (rows.length < pageSize) break;
    }
    final top = await topProducts(period.end.subtract(const Duration(days: 7)));
    return SalesReport.summarize(
      sales,
      period,
      topProducts: top.take(4).toList(),
    );
  }

  Future<List<ProductSales>> topProducts(DateTime from) async {
    final products = <String, ProductSales>{};
    const pageSize = 500;
    for (var offset = 0; ; offset += pageSize) {
      final rows = await _client
          .from('sale_items')
          .select('product_id, quantity, products(name, price)')
          .gte('created_at', from.toIso8601String())
          .order('created_at')
          .order('sale_id')
          .order('product_id')
          .range(offset, offset + pageSize - 1);
      for (final row in rows) {
        final id = row['product_id'].toString(),
            old = products[row['product_id'].toString()];
        products[id] = ProductSales(
          id,
          row['products']?['name']?.toString() ?? 'Deleted product',
          (old?.quantity ?? 0) + ((row['quantity'] as num?)?.toInt() ?? 0),
          (row['products']?['price'] as num?)?.toDouble() ?? 0,
        );
      }
      if (rows.length < pageSize) break;
    }
    return products.values.toList()
      ..sort((a, b) => b.quantity.compareTo(a.quantity));
  }
}
