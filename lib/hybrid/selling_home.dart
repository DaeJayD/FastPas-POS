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

  Widget _category(BuildContext context, String label, String? value) =>
      Padding(
        padding: EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: category == value,
          onSelected: locked ? null : (_) => onCategory(value),
          selectedColor: context.pos.accentSoft,
          backgroundColor: context.pos.surface,
          showCheckmark: false,
          labelStyle: TextStyle(
            fontFamily: 'Roboto',
            color: category == value
                ? Theme.of(context).colorScheme.primary
                : context.pos.muted,
            fontWeight: FontWeight.w600,
          ),
          side: BorderSide(
            color: category == value ? context.pos.text : context.pos.border,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final connected = status.startsWith('Connected');
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Duration(milliseconds: 160);
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 16),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: context.pos.subtle,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: context.pos.border),
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
                              ? context.pos.warning
                              : connected
                              ? context.pos.success
                              : context.pos.muted,
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              status,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              '$pending pending · $blocked need review',
                              style: TextStyle(
                                fontSize: 12,
                                color: context.pos.muted,
                              ),
                            ),
                            if (deviceId case final id?)
                              Text(
                                'Device ${id.split('-').first.toUpperCase()}',
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
                ),
                if (busy || syncing)
                  Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (!allowed && !busy)
                  Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      'Connect to verify selling access. Offline access lasts up to 24 hours after verification.',
                      style: TextStyle(fontSize: 12, color: context.pos.muted),
                    ),
                  ),
                SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: search,
                        onChanged: (_) => onSearch(),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Search products or SKU',
                          prefixIcon: Icon(Icons.search),
                          suffixIcon: search.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: () {
                                    search.clear();
                                    onSearch();
                                  },
                                  icon: Icon(Icons.close),
                                ),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                    if (onAddProduct != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Add product',
                        onPressed: locked ? null : onAddProduct,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ],
                ),
                if (categories.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _category(context, 'All products', null),
                          for (final entry in categories.entries)
                            _category(context, entry.value, entry.key),
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
              padding: EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 36,
                    color: context.pos.muted,
                  ),
                  SizedBox(height: 12),
                  Text(
                    busy
                        ? 'Opening products…'
                        : catalogEmpty
                        ? 'Your catalog is empty'
                        : 'No products match your search',
                    style: TextStyle(fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 6),
                  Text(
                    catalogEmpty
                        ? 'Connect to download products, or add your first product.'
                        : 'Try a different name, SKU or category. Your cart is kept.',
                    style: TextStyle(color: context.pos.muted),
                    textAlign: TextAlign.center,
                  ),
                  if (onRetry != null)
                    TextButton.icon(
                      onPressed: onRetry,
                      icon: Icon(Icons.refresh),
                      label: Text('Retry opening store'),
                    ),
                ],
              ),
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: 20),
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
                  (constraints.crossAxisExtent / (250 * scale.clamp(1, 1.5)))
                      .floor()
                      .clamp(1, 4);
              if (columns == 1) {
                return SliverList.builder(
                  itemCount: products.length,
                  itemBuilder: (context, index) => Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: tile(context, index),
                  ),
                );
              }
              return SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: 225 + (scale - 1).clamp(0, 2) * 130,
                ),
                itemCount: products.length,
                itemBuilder: tile,
              );
            },
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 20)),
      ],
    );
  }
}
