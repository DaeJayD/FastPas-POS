import 'package:flutter/material.dart';

import '../core/fastpas_theme.dart';
import '../core/studio_components.dart';
import 'cash_rules.dart';

class SellingProductCard extends StatelessWidget {
  const SellingProductCard({
    super.key,
    required this.product,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });
  final Map<String, Object?> product;
  final int quantity;
  final VoidCallback? onAdd, onRemove;
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(
        color: quantity > 0
            ? Theme.of(context).colorScheme.primary
            : context.pos.border,
      ),
    ),
    child: AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 150),
      padding: const EdgeInsets.all(14),
      color: quantity > 0 ? context.pos.accentSoft : context.pos.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              MediaQuery.textScalerOf(context).scale(1) > 1.4 ||
              constraints.maxWidth < 250;
          final summary = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayCents(product['price_cents'] as int),
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              StockBadge(quantity: product['quantity'] as int),
            ],
          );
          final controls = QuantityControl(
            quantity: quantity,
            onAdd: onAdd,
            onRemove: onRemove,
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProductThumbnail(
                    imageUrl: product['image_url'] as String?,
                    size: 42,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product['name'] as String,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          product['sku'] as String,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.pos.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (stacked) ...[
                summary,
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: controls),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: summary),
                    const SizedBox(width: 8),
                    controls,
                  ],
                ),
            ],
          );
        },
      ),
    ),
  );
}
