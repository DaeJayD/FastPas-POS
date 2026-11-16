import 'package:flutter/material.dart';

import 'fastpas_theme.dart';

class StockBadge extends StatelessWidget {
  const StockBadge({super.key, required this.quantity, this.threshold});
  final int quantity;
  final int? threshold;
  @override
  Widget build(BuildContext context) {
    final warning =
        quantity <= 0 ||
        (threshold == null
            ? quantity <= 5
            : threshold! > 0 && quantity <= threshold!);
    final label = quantity < 0
        ? 'Stock needs review · $quantity'
        : quantity == 0
        ? 'Out of stock'
        : warning
        ? (threshold == null ? 'Only $quantity left' : 'Low stock · $quantity')
        : '$quantity in stock';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: warning ? context.pos.warningSurface : context.pos.subtle,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: warning ? context.pos.warning : context.pos.muted,
        ),
      ),
    );
  }
}

class ProductThumbnail extends StatelessWidget {
  const ProductThumbnail({super.key, this.imageUrl, this.size = 52});
  final String? imageUrl;
  final double size;
  @override
  Widget build(BuildContext context) {
    Widget fallback() => Icon(
      Icons.inventory_2_outlined,
      color: context.pos.muted,
      size: size * .4,
    );
    final uri = Uri.tryParse(imageUrl ?? '');
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.pos.subtle,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: uri != null && ['https', 'http'].contains(uri.scheme)
          ? Image.network(
              uri.toString(),
              fit: BoxFit.cover,
              cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                  .round(),
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => fallback(),
            )
          : fallback(),
    );
  }
}

class QuantityControl extends StatelessWidget {
  const QuantityControl({
    super.key,
    required this.quantity,
    this.onAdd,
    this.onRemove,
  });
  final int quantity;
  final VoidCallback? onAdd, onRemove;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.pos.subtle,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.pos.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Remove one',
          onPressed: onRemove,
          icon: const Icon(Icons.remove, size: 20),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '$quantity',
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
  );
}

class StudioMetric extends StatelessWidget {
  const StudioMetric({
    super.key,
    required this.label,
    required this.value,
    this.detail,
    this.highlight = false,
  });
  final String label, value;
  final String? detail;
  final bool highlight;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: highlight ? context.pos.accent : context.pos.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: context.pos.border),
    ),
    child: DefaultTextStyle.merge(
      style: TextStyle(
        color: highlight ? context.pos.accentText : context.pos.text,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 16),
          Text(
            value,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w600,
              letterSpacing: -.8,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 8),
            Text(detail!, style: const TextStyle(fontSize: 12)),
          ],
        ],
      ),
    ),
  );
}
