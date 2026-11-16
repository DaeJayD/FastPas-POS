import 'package:flutter/material.dart';

import '../core/fastpas_theme.dart';
import '../core/studio_components.dart';
import '../hybrid/cash_rules.dart';
import 'branch_cash_report.dart';
import 'overview_details.dart';

class OverviewPanels extends StatelessWidget {
  const OverviewPanels({
    super.key,
    required this.report,
    this.details,
    required this.detailsLoading,
    this.error,
    required this.onRetry,
  });
  final BranchCashReport report;
  final OverviewDetails? details;
  final bool detailsLoading;
  final String? error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final data = details;
    final sellerPanel = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Top sellers',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        Text(
          data == null
              ? (detailsLoading
                    ? 'Loading synced receipts'
                    : 'Details unavailable')
              : 'Latest ${data.receiptCount} synced receipts · units before returns',
          style: TextStyle(color: context.pos.muted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Card(
          child: data == null
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Sales details unavailable'),
                )
              : data.sellers.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('No synced sales'),
                )
              : Column(
                  children: [
                    for (final item in data.sellers)
                      ListTile(
                        title: Text(item.name),
                        subtitle: Text(item.sku),
                        trailing: Text(
                          '${item.quantity}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 20),
      ],
    );
    final stockPanel = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Low stock',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Card(
          child: data == null
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Stock details unavailable'),
                )
              : data.stock.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('No stock needs attention'),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final item in data.stock.take(10))
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.name),
                            Text(
                              item.sku,
                              style: TextStyle(
                                color: context.pos.muted,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            StockBadge(
                              quantity: item.quantity,
                              threshold: item.threshold,
                            ),
                          ],
                        ),
                      ),
                    if (data.stock.length > 10)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '${data.stock.length} products need attention',
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns =
                constraints.maxWidth >= 740 &&
                    MediaQuery.textScalerOf(context).scale(1) <= 1.3
                ? 3
                : 1;
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: width,
                  child: StudioMetric(
                    label: 'Net cash sales',
                    value: displayCents(report.totals.net),
                    detail: '${report.fromDay} to ${report.throughDay}',
                    highlight: true,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: StudioMetric(
                    label: 'Items sold',
                    value: data == null ? '—' : '${data.itemsSold}',
                    detail: data == null
                        ? (detailsLoading
                              ? 'Loading synced receipts'
                              : 'Details unavailable')
                        : 'Latest ${data.receiptCount} synced receipts · before returns',
                  ),
                ),
                SizedBox(
                  width: width,
                  child: StudioMetric(
                    label: 'Stock attention',
                    value: data == null ? '—' : '${data.stock.length}',
                    detail: 'Current branch stock',
                  ),
                ),
              ],
            );
          },
        ),
        if (detailsLoading)
          const Padding(
            padding: EdgeInsets.all(12),
            child: LinearProgressIndicator(),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                Text(error!, style: TextStyle(color: context.pos.warning)),
                TextButton(
                  onPressed: onRetry,
                  child: const Text('Retry overview details'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 900 &&
                MediaQuery.textScalerOf(context).scale(1) <= 1.5) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: sellerPanel),
                  const SizedBox(width: 20),
                  Expanded(flex: 2, child: stockPanel),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [sellerPanel, stockPanel],
            );
          },
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
