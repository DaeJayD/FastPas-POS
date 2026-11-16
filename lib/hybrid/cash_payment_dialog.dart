import 'package:flutter/material.dart';

import '../core/fastpas_theme.dart';
import 'cash_rules.dart';
import 'checkout_quote.dart';

class CashPaymentDialog extends StatefulWidget {
  const CashPaymentDialog({
    super.key,
    required this.quote,
    required this.onConfirm,
  });
  final CheckoutQuote quote;
  final Future<void> Function(int cashCents) onConfirm;

  @override
  State<CashPaymentDialog> createState() => _CashPaymentDialogState();
}

class _CashPaymentDialogState extends State<CashPaymentDialog> {
  final _form = GlobalKey<FormState>();
  late final _cash = TextEditingController(
    text:
        '${widget.quote.totalCents ~/ 100}.${(widget.quote.totalCents % 100).toString().padLeft(2, '0')}',
  );
  bool _saving = false;
  String? _error;

  String? _validate(String? value) {
    try {
      return parseCents(value ?? '') < widget.quote.totalCents
          ? 'Cash must cover the total due.'
          : null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  Future<void> _confirm() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onConfirm(parseCents(_cash.text));
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : 'Sale was not saved. Check cash, stock, and selling access.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _cash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text('Cash payment'),
      scrollable: true,
      content: SizedBox(
        width: 400,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 16),
              for (final line in widget.quote.lines)
                Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${line.quantity} × ${line.name}',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '${line.sku} · ${displayCents(line.unitCents)} each · ${displayCents(line.quantity * line.unitCents)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.pos.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              Divider(),
              SizedBox(height: 8),
              Text(
                'Total due ${displayCents(widget.quote.totalCents)}',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 20),
              TextFormField(
                key: ValueKey('Cash received'),
                controller: _cash,
                enabled: !_saving,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                validator: _validate,
                onFieldSubmitted: (_) => _confirm(),
                decoration: InputDecoration(
                  labelText: 'Cash received',
                  errorMaxLines: 3,
                ),
              ),
              SizedBox(height: 14),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _cash,
                builder: (context, value, _) {
                  String text;
                  try {
                    final change =
                        parseCents(value.text) - widget.quote.totalCents;
                    text = change < 0
                        ? 'Still due ${displayCents(-change)}'
                        : 'Change ${displayCents(change)}';
                  } on FormatException {
                    text = 'Enter cash to see change';
                  }
                  return Semantics(
                    liveRegion: true,
                    child: Text(
                      text,
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  );
                },
              ),
              if (_error != null)
                Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _confirm,
          child: Text(_saving ? 'Saving…' : 'Complete sale'),
        ),
      ],
    ),
  );
}
