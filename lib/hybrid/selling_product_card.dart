import 'package:flutter/material.dart';

import '../core/fastpas_theme.dart';
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
  Widget build(BuildContext context) {
    final available = product['quantity'] as int;
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160);
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: quantity > 0 ? Volt.ink : Volt.line),
      ),
      child: AnimatedContainer(
        duration: motion,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: quantity > 0 ? Volt.lime.withValues(alpha: .09) : Volt.surface,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: quantity > 0 ? Volt.lime : Volt.soft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.inventory_2_outlined,
                    size: 24,
                    color: available <= 0 ? Volt.muted : Volt.ink,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product['name'] as String,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        product['sku'] as String,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Volt.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              displayCents(product['price_cents'] as int),
              style: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w800,
                letterSpacing: -.6,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    available <= 0
                        ? 'Out of stock'
                        : '$available locally available',
                    style: TextStyle(
                      fontSize: 12,
                      color: available <= 0
                          ? const Color(0xFF9B3A23)
                          : Volt.muted,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Volt.soft,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Remove one',
                        onPressed: onRemove,
                        icon: const Icon(Icons.remove, size: 20),
                      ),
                      AnimatedSwitcher(
                        duration: motion,
                        child: Text(
                          '$quantity',
                          key: ValueKey(quantity),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Add one',
                        onPressed: onAdd,
                        icon: const Icon(Icons.add, size: 20),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
