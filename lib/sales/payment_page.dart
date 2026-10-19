import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'receipt_page.dart';
import '../core/fastpas_theme.dart';
import '../catalog/catalog_source.dart';

class PaymentPage extends StatefulWidget {
  final String fullName;
  final String role;
  final List<Map<String, dynamic>> cartItems;
  final double subtotal;
  final double tax;
  final double discount;
  final double total;
  final String userId;
  final String location;
  final bool preview;

  const PaymentPage({
    super.key,
    required this.fullName,
    required this.role,
    required this.cartItems,
    required this.subtotal,
    required this.tax,
    required this.discount,
    required this.total,
    required this.userId,
    required this.location,
    this.preview = false,
  });

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  final TextEditingController _cashController = TextEditingController();
  double _cashGiven = 0.0;
  double _change = 0.0;
  String _method = 'Cash';
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _change = -widget.total;
  }

  void _calculateChange() {
    setState(() {
      final value = double.tryParse(_cashController.text);
      _cashGiven = value != null && value.isFinite ? value : 0;
      _change = _cashGiven - widget.total;
    });
  }

  void _quickFillCash() {
    _cashController.text = widget.total.toStringAsFixed(2);
    _calculateChange();
  }

  Future<void> _processPayment(
      BuildContext context, String paymentMethod) async {
    try {
      // For cash payments, validate cash given
      if (paymentMethod == "Cash") {
        if (_cashGiven <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Please enter cash amount!"),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        if (_cashGiven < widget.total) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Insufficient cash given!"),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      if (widget.preview) {
        if (!context.mounted) return;
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => ReceiptPage(
                      saleId: 'SAMPLE-RECEIPT',
                      paymentMethod: paymentMethod,
                      subtotal: widget.subtotal,
                      tax: widget.tax,
                      discount: widget.discount,
                      total: widget.total,
                      cartItems: widget.cartItems,
                      fullName: widget.fullName,
                      role: widget.role,
                      userId: widget.userId,
                      location: widget.location,
                      cashGiven: paymentMethod == 'Cash' ? _cashGiven : 0,
                      change: paymentMethod == 'Cash' ? _change : 0,
                      preview: true,
                    )));
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      // Process payment
      final saleResponse = await Supabase.instance.client
          .from('sales')
          .insert({
            'total_amount': widget.total,
            'subtotal_amount': widget.subtotal,
            'tax_amount': widget.tax,
            'discount_amount': widget.discount,
            'payment_method': paymentMethod.toLowerCase(),
            'created_at': DateTime.now().toIso8601String(),
            'status': 'completed',
            'cashier_name': widget.fullName,
            'cashier_role': widget.role,
            'cash_given': _cashGiven,
            'change': _change,
            'branch_location': widget.location,
          })
          .select()
          .single();

      final saleId = saleResponse['id'];

      // Check if saleId is null
      if (saleId == null) {
        throw Exception('Failed to create sale record');
      }

      // Create sale items with null safety
      final saleItems = widget.cartItems.map((item) {
        final price = (item['price'] as num?)?.toDouble() ?? 0.0;
        final quantity = (item['cart_quantity'] as num?)?.toInt() ?? 0;

        return {
          'sale_id': saleId,
          'product_id': item['id'],
          'quantity': quantity,
          'unit_price': price,
          'total_price': price * quantity,
        };
      }).toList();

      await Supabase.instance.client.from('sale_items').insert(saleItems);

      // Update branch stock for each item with null safety
      for (final item in widget.cartItems) {
        final productId = item['id'];
        final quantity = (item['cart_quantity'] as num?)?.toInt() ?? 0;

        if (productId == null) continue;

        try {
          final stockResponse = await Supabase.instance.client
              .from('branch_stock')
              .select('current_stock, id')
              .eq('product_id', productId)
              .single();

          final currentStock =
              (stockResponse['current_stock'] as num?)?.toInt() ?? 0;
          final branchStockId = stockResponse['id'];

          if (branchStockId != null) {
            await Supabase.instance.client
                .from('branch_stock')
                .update({'current_stock': currentStock - quantity}).eq(
                    'id', branchStockId);
          }
        } catch (e) {
          debugPrint('Error updating stock for product $productId: $e');
          // Continue with other items even if one fails
        }
      }

      if (!context.mounted) return;
      Navigator.pop(context); // Close loading dialog

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => ReceiptPage(
            saleId: saleId,
            paymentMethod: paymentMethod,
            subtotal: widget.subtotal,
            tax: widget.tax,
            discount: widget.discount,
            total: widget.total,
            cartItems: widget.cartItems,
            fullName: widget.fullName,
            role: widget.role,
            cashGiven: _cashGiven,
            change: _change,
            userId: widget.userId,
            location: widget.location,
          ),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment failed: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _cashController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_processing) return;
    FocusScope.of(context).unfocus();
    setState(() => _processing = true);
    try {
      await _processPayment(context, _method);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_processing,
        child: Scaffold(
          appBar: AppBar(title: const Text('Payment')),
          body: SafeArea(
              bottom: false,
              child: Center(
                  child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    '${widget.cartItems.fold<int>(0, (sum, item) => sum + (item['cart_quantity'] as num).toInt())} items · amount due',
                                    style: const TextStyle(color: Volt.muted)),
                                const SizedBox(height: 10),
                                FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(pesos(widget.total),
                                        style: const TextStyle(
                                            fontSize: 42,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -1.3))),
                                const SizedBox(height: 12),
                                Text(widget.location,
                                    style: const TextStyle(
                                        color: Volt.muted, fontSize: 12)),
                              ]))),
                  if (widget.preview)
                    const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: Text(
                            'Sample payment · no money or store records will change',
                            style: TextStyle(color: Volt.muted, fontSize: 12))),
                  const SizedBox(height: 28),
                  const Text('Payment method',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
                  const SizedBox(height: 6),
                  const Text('Select how the customer is paying.',
                      style: TextStyle(color: Volt.muted)),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                      builder: (context, constraints) =>
                          Wrap(spacing: 10, runSpacing: 10, children: [
                            for (final method in const [
                              'Cash',
                              'GCash',
                              'Bank',
                              'Card'
                            ])
                              SizedBox(
                                width: (constraints.maxWidth - 10) / 2,
                                child: OutlinedButton.icon(
                                  onPressed: _processing
                                      ? null
                                      : () => setState(() {
                                            _method = method;
                                            if (method != 'Cash') {
                                              _cashGiven = 0;
                                              _change = 0;
                                              _cashController.clear();
                                            }
                                          }),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 22),
                                    backgroundColor: _method == method
                                        ? Volt.ink
                                        : Colors.white,
                                    foregroundColor: _method == method
                                        ? Volt.lime
                                        : Volt.ink,
                                    side: BorderSide(
                                        color: _method == method
                                            ? Volt.ink
                                            : Volt.line),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14)),
                                  ),
                                  icon: Icon(
                                      method == 'Cash'
                                          ? Icons.payments_outlined
                                          : method == 'Card'
                                              ? Icons.credit_card
                                              : method == 'Bank'
                                                  ? Icons
                                                      .account_balance_outlined
                                                  : Icons
                                                      .account_balance_wallet_outlined,
                                      size: 21),
                                  label: Text(method,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                ),
                              ),
                          ])),
                  const SizedBox(height: 24),
                  if (_method == 'Cash') ...[
                    TextField(
                      controller: _cashController,
                      enabled: !_processing,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => _calculateChange(),
                      decoration: InputDecoration(
                          labelText: 'Cash received',
                          prefixText: '₱ ',
                          suffixIcon: TextButton(
                              onPressed: _processing ? null : _quickFillCash,
                              child: const Text('Exact'))),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                          color: Volt.soft,
                          borderRadius: BorderRadius.circular(14)),
                      child: Row(children: [
                        Expanded(
                            child: Text(_change < 0 ? 'Still due' : 'Change',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600))),
                        Flexible(
                            child: Text(pesos(_change.abs()),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 22))),
                      ]),
                    ),
                  ] else
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                          color: Volt.soft,
                          borderRadius: BorderRadius.circular(14)),
                      child: const Text(
                          'Confirm that payment has been received before recording this sale. FastPas records the payment method; it does not charge or verify an external account.',
                          style: TextStyle(
                              color: Volt.muted, fontSize: 13, height: 1.5)),
                    ),
                  const SizedBox(height: 24),
                ]),
              ))),
          bottomNavigationBar: SafeArea(
              child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: FilledButton(
              onPressed: _processing ? null : _submit,
              child: _processing
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(widget.preview
                          ? 'Preview receipt'
                          : 'Record payment'),
                      const SizedBox(width: 12),
                      const Icon(Icons.check_circle_outline, size: 20),
                    ]),
            ),
          )),
        ),
      );
}
