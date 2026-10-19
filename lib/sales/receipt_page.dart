import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../catalog/catalog_source.dart';
import '../core/fastpas_theme.dart';
import '../pos/product_home_screen.dart';
import '../preview/sample_catalog.dart';

class ReceiptPage extends StatelessWidget {
  const ReceiptPage({
    super.key,
    required this.saleId,
    required this.paymentMethod,
    required this.location,
    required this.userId,
    required this.subtotal,
    required this.tax,
    required this.discount,
    required this.total,
    required this.cartItems,
    required this.fullName,
    required this.role,
    required this.cashGiven,
    required this.change,
    this.preview = false,
  });
  final String saleId;
  final String paymentMethod;
  final String location;
  final String userId;
  final double subtotal;
  final double tax;
  final double discount;
  final double total;
  final List<Map<String, dynamic>> cartItems;
  final String fullName;
  final String role;
  final double cashGiven;
  final double change;
  final bool preview;

  String get _shortId => saleId.length > 12
      ? saleId.substring(0, 12).toUpperCase()
      : saleId.toUpperCase();
  bool get _cash => paymentMethod.toLowerCase() == 'cash';

  Future<void> _copy(BuildContext context) async {
    final buffer = StringBuffer()
      ..writeln(preview ? 'FASTPAS POS · SAMPLE RECEIPT' : 'FASTPAS POS')
      ..writeln('Receipt: $saleId')
      ..writeln('Branch: $location')
      ..writeln('Cashier: $fullName')
      ..writeln('Payment: $paymentMethod');
    for (final item in cartItems) {
      buffer.writeln(
          '${item['name']} × ${item['cart_quantity']} · ${pesos((item['price'] as num) * (item['cart_quantity'] as num))}');
    }
    buffer
      ..writeln('Subtotal: ${pesos(subtotal)}')
      ..writeln('Tax: ${pesos(tax)}')
      ..writeln('Discount: ${pesos(discount)}')
      ..writeln('Total: ${pesos(total)}');
    if (_cash) {
      buffer
        ..writeln('Cash received: ${pesos(cashGiven)}')
        ..writeln('Change: ${pesos(change)}');
    }
    if (preview) buffer.writeln('Sample data only. No payment was recorded.');
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Receipt copied.')));
    }
  }

  void _newSale(BuildContext context) =>
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
            builder: (_) => ProductHomeScreen(
                  fullName: fullName,
                  role: role,
                  userId: userId,
                  location: location,
                  source: preview ? SampleCatalog() : null,
                )),
        (_) => false,
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(preview ? 'Sample receipt' : 'Receipt'),
            actions: [
              IconButton(
                  tooltip: 'Copy receipt',
                  onPressed: () => _copy(context),
                  icon: const Icon(Icons.copy_outlined)),
              const SizedBox(width: 8),
            ]),
        body: SafeArea(
            bottom: false,
            child: Center(
                child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(padding: const EdgeInsets.all(20), children: [
                Center(
                    child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                            color: Volt.lime.withValues(alpha: .3),
                            shape: BoxShape.circle),
                        child: const Icon(Icons.check, size: 30))),
                const SizedBox(height: 18),
                Text(preview ? 'Your receipt preview' : 'Sale recorded',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 29,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.8)),
                const SizedBox(height: 8),
                Text(
                    preview
                        ? 'Sample data only. No payment was recorded.'
                        : 'Your order details are below.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Volt.muted, height: 1.5)),
                const SizedBox(height: 26),
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Center(child: FastPasBrand(size: 25)),
                              const SizedBox(height: 22),
                              _detail('Receipt', '#$_shortId'),
                              if (location.isNotEmpty)
                                _detail('Branch', location),
                              _detail('Cashier', fullName),
                              _detail('Payment', paymentMethod),
                              const Divider(height: 32),
                              for (final item in cartItems)
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                Text(item['name'].toString(),
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600)),
                                                const SizedBox(height: 3),
                                                Text(
                                                    '${item['cart_quantity']} × ${pesos(item['price'] as num)}',
                                                    style: const TextStyle(
                                                        color: Volt.muted,
                                                        fontSize: 12)),
                                              ])),
                                          const SizedBox(width: 12),
                                          Flexible(
                                              child: Text(
                                                  pesos((item['price'] as num) *
                                                      (item['cart_quantity']
                                                          as num)),
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700))),
                                        ])),
                              const Divider(height: 24),
                              _detail('Subtotal', pesos(subtotal)),
                              _detail('Tax', pesos(tax)),
                              if (discount > 0)
                                _detail('Discount', '-${pesos(discount)}'),
                              const Divider(height: 24),
                              _detail('Total', pesos(total), strong: true),
                              if (_cash) ...[
                                const Divider(height: 24),
                                _detail('Cash received', pesos(cashGiven)),
                                _detail('Change', pesos(change)),
                              ],
                              const SizedBox(height: 20),
                              const Center(
                                  child: Text('Thank you for shopping!',
                                      style: TextStyle(
                                          color: Volt.muted, fontSize: 12))),
                            ]))),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                    onPressed: () => _copy(context),
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    label: const Text('Copy receipt')),
                const SizedBox(height: 16),
              ]),
            ))),
        bottomNavigationBar: SafeArea(
            child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: FilledButton(
              onPressed: () => _newSale(context),
              child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(child: Text('Start a new sale')),
                    SizedBox(width: 12),
                    Icon(Icons.arrow_forward, size: 18)
                  ])),
        )),
      );

  Widget _detail(String label, String value, {bool strong = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: strong ? Volt.ink : Volt.muted,
                      fontWeight: strong ? FontWeight.w700 : FontWeight.w400))),
          const SizedBox(width: 12),
          Flexible(
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: strong ? 23 : 14,
                      fontWeight: strong ? FontWeight.w800 : FontWeight.w600))),
        ]),
      );
}
