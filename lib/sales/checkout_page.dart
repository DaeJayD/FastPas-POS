import 'package:flutter/material.dart';
import '../catalog/catalog_source.dart';
import '../core/fastpas_theme.dart';
import 'payment_page.dart';

class CheckoutPage extends StatefulWidget {
  const CheckoutPage(
      {super.key,
      required this.cartItems,
      required this.role,
      required this.fullName,
      required this.userId,
      required this.location,
      this.change = '',
      this.cashGiven = '',
      this.preview = false});
  final String fullName;
  final String role;
  final List<Map<String, dynamic>> cartItems;
  final String? change;
  final String? cashGiven;
  final String userId;
  final String location;
  final bool preview;

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  late final List<Map<String, dynamic>> _items =
      widget.cartItems.map((item) => Map<String, dynamic>.from(item)).toList();
  double _discountPercent = 0;
  double get _subtotal => _items.fold(
      0,
      (sum, item) =>
          sum +
          (item['price'] as num).toDouble() *
              (item['cart_quantity'] as num).toInt());
  // Preserve the existing pricing rules; configurable tax is a later phase.
  double get _tax => _subtotal * .12;
  double get _discount => _subtotal * _discountPercent / 100;
  double get _total => _subtotal + _tax - _discount;

  void _quantity(Map<String, dynamic> item, int change) {
    final quantity = (item['cart_quantity'] as num).toInt() + change;
    if (quantity > ((item['stock'] as num?)?.toInt() ?? 0)) return;
    setState(() {
      if (quantity <= 0) {
        _items.remove(item);
      } else {
        item['cart_quantity'] = quantity;
      }
    });
  }

  Future<void> _editDiscount() async {
    final controller = TextEditingController(
        text: _discountPercent == 0 ? '' : _discountPercent.toStringAsFixed(0));
    final form = GlobalKey<FormState>();
    final result = await showDialog<double>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Order discount'),
              content: Form(
                  key: form,
                  child: TextFormField(
                    autofocus: true,
                    controller: controller,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Discount', suffixText: '%'),
                    validator: (value) {
                      final number = double.tryParse(value ?? '');
                      return number == null ||
                              !number.isFinite ||
                              number < 0 ||
                              number > 100
                          ? 'Enter a number from 0 to 100.'
                          : null;
                    },
                  )),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () {
                      if (form.currentState!.validate()) {
                        Navigator.pop(context, double.parse(controller.text));
                      }
                    },
                    child: const Text('Apply')),
              ],
            ));
    // The dialog route disposes its field after its closing transition.
    if (!mounted || result == null) return;
    setState(() => _discountPercent = result);
  }

  @override
  Widget build(BuildContext context) => PopScope<List<Map<String, dynamic>>>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _backWithResult();
        },
        child: Scaffold(
          appBar: AppBar(
              leading: IconButton(
                  tooltip: 'Back to products',
                  onPressed: _backWithResult,
                  icon: const Icon(Icons.arrow_back)),
              title: const Text('Review order')),
          body: SafeArea(
              bottom: false,
              child: Center(
                  child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: _items.isEmpty
                    ? Center(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.shopping_cart_outlined,
                            size: 48, color: Volt.muted),
                        const SizedBox(height: 16),
                        const Text('Your cart is empty'),
                        const SizedBox(height: 16),
                        FilledButton(
                            onPressed: _backWithResult,
                            child: const Text('Browse products')),
                      ]))
                    : ListView(padding: const EdgeInsets.all(20), children: [
                        Text(
                            widget.location.isEmpty
                                ? 'Your order'
                                : widget.location,
                            style: const TextStyle(color: Volt.muted)),
                        const SizedBox(height: 8),
                        Text(
                            '${_items.fold<int>(0, (sum, item) => sum + (item['cart_quantity'] as num).toInt())} items in your cart',
                            style: const TextStyle(
                                fontSize: 27,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.8)),
                        if (widget.preview)
                          const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                  'Sample order · no store transactions are saved',
                                  style: TextStyle(
                                      color: Volt.muted, fontSize: 12))),
                        const SizedBox(height: 24),
                        for (final item in _items)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Card(
                                  child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                                padding:
                                                    const EdgeInsets.all(12),
                                                decoration: BoxDecoration(
                                                    color: Volt.soft,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12)),
                                                child: const Icon(Icons
                                                    .inventory_2_outlined)),
                                            const SizedBox(width: 14),
                                            Expanded(
                                                child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                  Text(item['name'].toString(),
                                                      style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          fontSize: 16)),
                                                  const SizedBox(height: 5),
                                                  Text(
                                                      '${pesos(item['price'] as num)} each',
                                                      style: const TextStyle(
                                                          color: Volt.muted,
                                                          fontSize: 12)),
                                                ])),
                                          ]),
                                      const SizedBox(height: 12),
                                      Row(children: [
                                        IconButton(
                                            tooltip:
                                                'Remove one ${item['name']}',
                                            onPressed: () =>
                                                _quantity(item, -1),
                                            icon: const Icon(
                                                Icons.remove_circle_outline)),
                                        Text('${item['cart_quantity']}',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700)),
                                        IconButton(
                                            tooltip: 'Add one ${item['name']}',
                                            onPressed: (item['cart_quantity']
                                                        as num) >=
                                                    (item['stock'] as num? ?? 0)
                                                ? null
                                                : () => _quantity(item, 1),
                                            icon: const Icon(
                                                Icons.add_circle_outline)),
                                        const Spacer(),
                                        Flexible(
                                            child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text(
                                                    pesos((item['price']
                                                            as num) *
                                                        (item['cart_quantity']
                                                            as num)),
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        fontSize: 19)))),
                                      ]),
                                    ]),
                              ))),
                        TextButton.icon(
                            onPressed: _backWithResult,
                            icon: const Icon(Icons.add),
                            label: const Text('Add more products')),
                        const SizedBox(height: 16),
                        Card(
                            child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(children: [
                                  _summary('Subtotal', _subtotal),
                                  _summary('Tax (12%)', _tax),
                                  if (_discount > 0)
                                    _summary(
                                        'Discount (${_discountPercent.toStringAsFixed(0)}%)',
                                        -_discount),
                                  const Divider(height: 30),
                                  _summary('Total', _total, strong: true),
                                ]))),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                            onPressed: _editDiscount,
                            icon: const Icon(Icons.sell_outlined, size: 18),
                            label: Text(_discountPercent > 0
                                ? 'Edit discount'
                                : 'Add discount')),
                        const SizedBox(height: 12),
                        const Text(
                            'Order totals use the store’s current tax and discount rules.',
                            style: TextStyle(fontSize: 12, color: Volt.muted)),
                      ]),
              ))),
          bottomNavigationBar: _items.isEmpty
              ? null
              : SafeArea(
                  child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: FilledButton(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => PaymentPage(
                                    fullName: widget.fullName,
                                    role: widget.role,
                                    cartItems: _items,
                                    subtotal: _subtotal,
                                    tax: _tax,
                                    discount: _discount,
                                    total: _total,
                                    userId: widget.userId,
                                    location: widget.location,
                                    preview: widget.preview,
                                  ))),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Expanded(child: Text('Continue to payment')),
                            const SizedBox(width: 12),
                            Flexible(
                                child: Text(pesos(_total),
                                    textAlign: TextAlign.right)),
                            const SizedBox(width: 10),
                            const Icon(Icons.arrow_forward, size: 18)
                          ])),
                )),
        ),
      );

  // Bypass PopScope for our intentional pop while returning edited quantities.
  void _backWithResult() {
    Navigator.of(context).pop(_items);
  }

  Widget _summary(String label, double amount, {bool strong = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: strong ? Volt.ink : Volt.muted,
                      fontWeight: strong ? FontWeight.w700 : FontWeight.w400))),
          const SizedBox(width: 12),
          Flexible(
              child: Text(pesos(amount),
                  style: TextStyle(
                      fontSize: strong ? 23 : 15,
                      fontWeight: strong ? FontWeight.w800 : FontWeight.w600))),
        ]),
      );
}
