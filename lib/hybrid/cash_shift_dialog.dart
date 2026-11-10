import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cash_rules.dart';
import 'cash_shift_repository.dart';

class CashShiftDialog extends StatefulWidget {
  const CashShiftDialog({
    super.key,
    required this.repository,
    required this.onSync,
  });

  final CashShiftRepository repository;
  final Future<void> Function() onSync;

  @override
  State<CashShiftDialog> createState() => _CashShiftDialogState();
}

class _CashShiftDialogState extends State<CashShiftDialog> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  CashShiftSummary? _drawer;
  CashShiftAction _action = CashShiftAction.open;
  String? _error;
  bool _busy = false, _ready = false, _pending = false;

  CashShiftRepository get _repository => widget.repository;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  String _message(Object error) {
    if (error is FormatException) return error.message;
    if (error is PostgrestException && error.code == 'PGRST202') {
      return 'Cash shifts are not available on this server yet.';
    }
    if (error is PostgrestException && error.code == '42501') {
      return 'This shift needs branch selling access on the original account and device.';
    }
    return 'Could not confirm the cash shift. Check your connection and retry.';
  }

  void _show(CashShiftSummary? drawer) {
    _drawer = drawer;
    _action = drawer?.isOpen == true
        ? CashShiftAction.cashIn
        : CashShiftAction.open;
    _amount.clear();
    _reason.clear();
    _pending = false;
    _ready = true;
  }

  Future<void> _load({bool sync = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _ready = false;
      _error = null;
    });
    try {
      final pending = await _repository.pending();
      if (pending != null) {
        if (mounted) setState(() => _pending = true);
        return;
      }
      if (sync) await widget.onSync();
      final drawer = await _repository.status();
      if (mounted) setState(() => _show(drawer));
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _movement =>
      _action == CashShiftAction.cashIn || _action == CashShiftAction.cashOut;

  Future<void> _save() async {
    if (_busy || (!_ready && !_pending)) return;
    int? cents;
    final reason = _reason.text.trim();
    if (!_pending) {
      try {
        cents = parseCents(_amount.text);
        if (_movement && (cents == 0 || reason.isEmpty)) {
          throw const FormatException('Enter a positive amount and a reason.');
        }
        if (cents > 9000000000000) {
          throw const FormatException(
            'Cash amount exceeds the supported range.',
          );
        }
      } on FormatException catch (error) {
        setState(() => _error = error.message);
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = _pending
          ? await _repository.retry()
          : await _repository.submit(
              _action,
              activeShift: _drawer?.isOpen == true ? _drawer!.id : null,
              cents: cents!,
              reason: reason,
            );
      if (mounted) setState(() => _show(result));
    } catch (error) {
      String? pending;
      var readable = true;
      try {
        pending = await _repository.pending();
      } catch (_) {
        readable = false;
      }
      if (mounted) {
        setState(() {
          _pending = pending != null;
          _ready = readable && _ready && !_pending;
          _error = _message(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _label(CashShiftAction action) => switch (action) {
    CashShiftAction.open => 'Open shift',
    CashShiftAction.cashIn => 'Record cash in',
    CashShiftAction.cashOut => 'Record cash out',
    CashShiftAction.close => 'Close shift',
  };

  @override
  Widget build(BuildContext context) {
    final drawer = _drawer;
    final showForm = _ready && !_pending;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Cash shift'),
        scrollable: true,
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_pending)
                const Text(
                  'A shift request is awaiting confirmation. Retry it before taking more cash payments.',
                ),
              if (showForm) ...[
                if (drawer == null)
                  const Text('Enter the opening cash in this drawer.')
                else ...[
                  Text(
                    drawer.isOpen ? 'Shift open' : 'Last shift closed',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text('Opening cash ${displayCents(drawer.opening)}'),
                  Text('Sales after change ${displayCents(drawer.sales)}'),
                  Text('Refunds ${displayCents(drawer.refunds)}'),
                  Text('Cash in ${displayCents(drawer.cashIn)}'),
                  Text('Cash out ${displayCents(drawer.cashOut)}'),
                  Text(
                    'Expected cash ${displayCents(drawer.expected)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (drawer.counted case final counted?)
                    Text('Counted cash ${displayCents(counted)}'),
                  if (drawer.variance case final variance?)
                    Text('Variance ${displayCents(variance)}'),
                  if (drawer.recentMovements.isNotEmpty)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Recent cash movements'),
                      children: [
                        for (final movement in drawer.recentMovements)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(movement.reason),
                            subtitle: Text(displayCents(movement.cents)),
                          ),
                      ],
                    ),
                  if (drawer.isOpen) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final action in [
                          CashShiftAction.cashIn,
                          CashShiftAction.cashOut,
                          CashShiftAction.close,
                        ])
                          ChoiceChip(
                            label: Text(_label(action)),
                            selected: _action == action,
                            onSelected: _busy
                                ? null
                                : (_) => setState(() {
                                    _action = action;
                                    _amount.clear();
                                    _reason.clear();
                                    _error = null;
                                  }),
                          ),
                      ],
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _amount,
                  enabled: !_busy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: switch (_action) {
                      CashShiftAction.open => 'Opening cash',
                      CashShiftAction.close => 'Counted cash',
                      _ => 'Cash amount',
                    },
                  ),
                ),
                if (_movement) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _reason,
                    enabled: !_busy,
                    maxLength: 240,
                    decoration: const InputDecoration(labelText: 'Reason'),
                  ),
                ],
                if (drawer?.isOpen == true)
                  TextButton.icon(
                    onPressed: _busy ? null : () => _load(sync: true),
                    icon: const Icon(Icons.sync),
                    label: const Text('Sync receipts and refresh'),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Done'),
          ),
          if (_pending || showForm)
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_pending ? 'Retry saved request' : _label(_action)),
            )
          else
            TextButton(
              onPressed: _busy ? null : _load,
              child: const Text('Reload'),
            ),
        ],
      ),
    );
  }
}
