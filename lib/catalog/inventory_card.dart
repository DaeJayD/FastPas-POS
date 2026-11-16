import 'package:flutter/material.dart';

import '../core/fastpas_theme.dart';
import '../core/studio_components.dart';
import '../hybrid/cash_rules.dart';
import 'catalog_repository.dart';

class InventoryCard extends StatelessWidget {
  const InventoryCard({
    super.key,
    required this.item,
    required this.category,
    required this.actions,
  });
  final CatalogItem item;
  final String category;
  final Widget actions;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final identity = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  item.sku,
                  style: TextStyle(color: context.pos.muted, fontSize: 12),
                ),
                if (!item.active) const Text('Archived'),
              ],
            );
            final status = StockBadge(
              quantity: item.quantity,
              threshold: item.threshold,
            );
            if (constraints.maxWidth >= 720 &&
                MediaQuery.textScalerOf(context).scale(1) <= 1.3) {
              return Row(
                children: [
                  Expanded(flex: 3, child: identity),
                  Expanded(flex: 2, child: Text(category)),
                  Expanded(flex: 2, child: Text(displayCents(item.price))),
                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: status,
                    ),
                  ),
                  actions,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: identity),
                    actions,
                  ],
                ),
                const SizedBox(height: 10),
                Text(category, style: TextStyle(color: context.pos.muted)),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 16,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      displayCents(item.price),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 19,
                      ),
                    ),
                    status,
                  ],
                ),
                if (item.quantity > 0 &&
                    item.threshold > 0 &&
                    item.quantity <= item.threshold)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Low stock · alert at ${item.threshold}',
                      style: TextStyle(
                        color: context.pos.warning,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
