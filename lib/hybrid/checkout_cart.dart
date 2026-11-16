import 'package:flutter/material.dart';

import '../core/fastpas_theme.dart';
import '../core/studio_components.dart';
import 'cash_rules.dart';

class CheckoutCart extends StatelessWidget {
  const CheckoutCart({
    super.key,
    required this.products,
    required this.cart,
    required this.total,
    required this.locked,
    required this.allowed,
    required this.onQuantity,
    required this.onClear,
    required this.onCheckout,
    required this.status,
    required this.pending,
    required this.blocked,
    this.onClose,
  });
  final List<Map<String, Object?>> products;
  final Map<String, int> cart;
  final int total, pending, blocked;
  final bool locked, allowed;
  final String status;
  final void Function(String, int) onQuantity;
  final VoidCallback onClear, onCheckout;
  final VoidCallback? onClose;

  Widget _header(int count) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Cart',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
            ),
            if (onClose != null)
              IconButton(
                tooltip: 'Back to products',
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
          ],
        ),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('$count ${count == 1 ? 'item' : 'items'} in cart'),
            if (cart.isNotEmpty)
              TextButton(
                onPressed: locked ? null : onClear,
                child: const Text('Clear cart'),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _line(BuildContext context, int index) {
    final entry = cart.entries.elementAt(index);
    final item = products.where((p) => p['id'] == entry.key).firstOrNull;
    final price = item?['price_cents'] as int?;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          const SizedBox(height: 8),
          Text(
            item?['name'] as String? ?? 'Unavailable product',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 5),
          Text(
            item?['sku'] as String? ?? entry.key,
            style: TextStyle(fontSize: 12, color: context.pos.muted),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              QuantityControl(
                quantity: entry.value,
                onRemove: locked ? null : () => onQuantity(entry.key, -1),
                onAdd:
                    locked ||
                        !allowed ||
                        item == null ||
                        entry.value >= (item['quantity'] as int)
                    ? null
                    : () => onQuantity(entry.key, 1),
              ),
              Text(
                price == null
                    ? 'Price unavailable'
                    : displayCents(price * entry.value),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 17,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _payment() => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Total', style: TextStyle(fontSize: 13)),
        const SizedBox(height: 6),
        Text(
          displayCents(total),
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: locked || !allowed || cart.isEmpty ? null : onCheckout,
          icon: const Icon(Icons.arrow_forward_rounded),
          label: Text('Cash checkout · ${displayCents(total)}'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final count = cart.values.fold(0, (sum, n) => sum + n);
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(
              '$status\n$pending pending · $blocked need review',
              style: TextStyle(
                fontSize: 12,
                color: blocked > 0 ? context.pos.warning : context.pos.muted,
              ),
            ),
          ),
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _header(count)),
                if (cart.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Your cart is empty'),
                    ),
                  ),
                SliverList.builder(itemCount: cart.length, itemBuilder: _line),
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [const Divider(), _payment()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
