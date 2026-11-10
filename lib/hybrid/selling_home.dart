import 'package:flutter/material.dart';

import '../core/fastpas_theme.dart';
import 'selling_product_card.dart';

/// Product browsing uses the current local snapshot; filtering never owns the cart.
class SellingHome extends StatelessWidget {
  const SellingHome({
    super.key,
    required this.products,
    required this.catalogEmpty,
    required this.cart,
    required this.search,
    required this.onSearch,
    required this.categories,
    required this.category,
    required this.onCategory,
    required this.onQuantity,
    required this.status,
    required this.pending,
    required this.blocked,
    required this.busy,
    required this.syncing,
    required this.locked,
    required this.allowed,
    this.deviceId,
    this.onAddProduct,
    this.onRetry,
  });

  final List<Map<String, Object?>> products;
  final bool catalogEmpty, busy, syncing, locked, allowed;
  final Map<String, int> cart;
  final TextEditingController search;
  final VoidCallback onSearch;
  final Map<String, String> categories;
  final String? category;
  final ValueChanged<String?> onCategory;
  final void Function(String id, int delta) onQuantity;
  final String status;
  final String? deviceId;
  final int pending, blocked;
  final VoidCallback? onAddProduct, onRetry;

  Widget _category(String label, String? value) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: category == value,
      onSelected: locked ? null : (_) => onCategory(value),
      selectedColor: Volt.ink,
      backgroundColor: Volt.surface,
      showCheckmark: false,
      labelStyle: TextStyle(
        color: category == value ? Volt.lime : Volt.ink,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide(color: category == value ? Volt.ink : Volt.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final connected = status.startsWith('Connected');
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160);
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Volt.soft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Volt.line),
                  ),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: motion,
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: syncing
                              ? Colors.amber.shade700
                              : connected
                              ? Colors.teal.shade700
                              : Volt.muted,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$pending pending · $blocked need review',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Volt.muted,
                              ),
                            ),
                            if (deviceId case final id?)
                              Text(
                                'Device ${id.split('-').first.toUpperCase()}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Volt.muted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (busy || syncing)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (!allowed && !busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      'Connect to verify selling access. Offline access lasts up to 24 hours after verification.',
                      style: TextStyle(fontSize: 12, color: Volt.muted),
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Products',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (onAddProduct != null)
                      OutlinedButton.icon(
                        onPressed: locked ? null : onAddProduct,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add product'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: search,
                  onChanged: (_) => onSearch(),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search products or SKU',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              search.clear();
                              onSearch();
                            },
                            icon: const Icon(Icons.close),
                          ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                  ),
                ),
                if (categories.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _category('All products', null),
                          for (final entry in categories.entries)
                            _category(entry.value, entry.key),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (products.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                children: [
                  const Icon(
                    Icons.inventory_2_outlined,
                    size: 36,
                    color: Volt.muted,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    busy
                        ? 'Opening products…'
                        : catalogEmpty
                        ? 'Your catalog is empty'
                        : 'No products match your search',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    catalogEmpty
                        ? 'Connect to download products, or add your first product.'
                        : 'Try a different name, SKU or category. Your cart is kept.',
                    style: const TextStyle(color: Volt.muted),
                    textAlign: TextAlign.center,
                  ),
                  if (onRetry != null)
                    TextButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry opening store'),
                    ),
                ],
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) {
              Widget tile(BuildContext context, int index) {
                final product = products[index];
                final id = product['id'] as String;
                final quantity = cart[id] ?? 0;
                return SellingProductCard(
                  product: product,
                  quantity: quantity,
                  onAdd:
                      locked ||
                          !allowed ||
                          quantity >= (product['quantity'] as int)
                      ? null
                      : () => onQuantity(id, 1),
                  onRemove: locked || quantity == 0
                      ? null
                      : () => onQuantity(id, -1),
                );
              }

              final scale = MediaQuery.textScalerOf(context).scale(1);
              final columns =
                  (constraints.crossAxisExtent / (320 * scale.clamp(1, 1.5)))
                      .floor()
                      .clamp(1, 4);
              if (columns == 1) {
                return SliverList.builder(
                  itemCount: products.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: tile(context, index),
                  ),
                );
              }
              return SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: 230 + (scale - 1).clamp(0, 2) * 130,
                ),
                itemCount: products.length,
                itemBuilder: tile,
              );
            },
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 20)),
      ],
    );
  }
}
