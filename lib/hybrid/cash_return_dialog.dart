import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cash_return_repository.dart';
import 'cash_rules.dart';

class CashReturnDialog extends StatefulWidget {
  const CashReturnDialog({super.key, required this.repository});
  final CashReturnRepository repository;

  @override
  State<CashReturnDialog> createState() => _CashReturnDialogState();
}

class _CashReturnDialogState extends State<CashReturnDialog> {
  final _reason = TextEditingController();
  final _quantities = <String, String>{};
  final _restock = <String>{};
  List<CashReturnLine>? _lines;
  CashReturnResult? _result;
  String? _error;
  bool _loading = true, _saving = false, _pending = false;
  int _formVersion = 0;

  CashReturnRepository get _repository => widget.repository;
  List<CashReturnLine> get _available =>
      _lines?.where((line) => line.remaining > 0).toList() ?? [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _lines = null;
      _quantities.clear();
      _restock.clear();
      _formVersion++;
    });
    try {
      final pending = await _repository.pending();
      final lines = pending == null ? await _repository.options() : null;
      if (mounted) {
        setState(() {
          _pending = pending != null;
          _lines = lines;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _message(Object error) {
    if (error is FormatException) return error.message;
    if (error is PostgrestException) {
      if (error.code == 'PGRST202') {
        return 'Returns are not available on this server yet.';
      }
      if (error.code == '42501') {
        return 'A branch owner or assigned manager must record this return.';
      }
    }
    return 'Could not verify the return. Check your connection and try again.';
  }

  int? _quantity(CashReturnLine line) {
    final text = _quantities[line.id]?.trim() ?? '';
    if (text.isEmpty) return 0;
    final quantity = int.tryParse(text, radix: 10);
    if (quantity == null || quantity < 0 || quantity > line.remaining) {
      return null;
    }
    return quantity;
  }

  int? get _total {
    var total = 0;
    for (final line in _available) {
      final quantity = _quantity(line);
      if (quantity == null) return null;
      total += quantity * line.unitCents;
    }
    return total;
  }

  Future<void> _save() async {
    if (_saving || _loading) return;
    final reason = _reason.text.trim();
    final items = <Map<String, Object>>[];
    if (!_pending) {
      for (final line in _available) {
        final quantity = _quantity(line);
        if (quantity == null) {
          setState(
            () => _error = 'Enter whole quantities within the remaining units.',
          );
          return;
        }
        if (quantity > 0) {
          items.add({
            'product_id': line.id,
            'quantity': quantity,
            'restock': _restock.contains(line.id),
          });
        }
      }
      if (items.isEmpty || reason.isEmpty) {
        setState(() => _error = 'Select at least one unit and enter a reason.');
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = _pending
          ? await _repository.retry()
          : await _repository.record(reason, items);
      if (mounted) setState(() => _result = result);
    } catch (error) {
      // If the local journal cannot be read, require a fresh load before recording.
      String? pending;
      var journalReadable = true;
      try {
        pending = await _repository.pending();
      } catch (_) {
        journalReadable = false;
      }
      if (mounted) {
        setState(() {
          _pending = pending != null;
          _lines = null;
          _error = journalReadable
              ? _message(error)
              : 'Could not check the saved request. Reload this return.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = _total;
    final available = _available;
    final result = _result;
    return PopScope(
      canPop: !_saving && result == null,
      child: AlertDialog(
        scrollable: true,
        title: Text(result == null ? 'Cash return' : 'Return recorded'),
        content: SizedBox(
          width: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_loading || _saving) const LinearProgressIndicator(),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (result != null) ...[
                Text('Cash refund ${displayCents(result.totalCents)}'),
                const SizedBox(height: 8),
                SelectableText('Return ID ${result.id}'),
              ] else if (_pending) ...[
                const SizedBox(height: 12),
                const Text(
                  'A saved return is awaiting confirmation. Retry sends the same request and checks its result.',
                ),
              ] else if (_lines != null) ...[
                Text(
                  'Previously recorded refunds ${displayCents(_lines!.fold(0, (sum, line) => sum + (line.sold - line.remaining) * line.unitCents))}',
                ),
                if (available.isEmpty)
                  const Text('All units on this receipt have been returned.'),
                for (final line in available) ...[
                  const Divider(height: 24),
                  Text(
                    line.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${line.sku} · ${line.remaining} available to return · ${displayCents(line.unitCents)} each',
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: ValueKey('$_formVersion:${line.id}'),
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Return quantity',
                    ),
                    onChanged: (value) =>
                        setState(() => _quantities[line.id] = value),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Put back in sellable stock'),
                    value: _restock.contains(line.id),
                    onChanged: _saving
                        ? null
                        : (value) => setState(() {
                            if (value == true) {
                              _restock.add(line.id);
                            } else {
                              _restock.remove(line.id);
                            }
                          }),
                  ),
                ],
                if (available.isNotEmpty) ...[
                  TextField(
                    controller: _reason,
                    enabled: !_saving,
                    maxLength: 240,
                    decoration: const InputDecoration(
                      labelText: 'Return reason',
                    ),
                  ),
                  Text(
                    total == null
                        ? 'Check return quantities'
                        : 'Cash refund ${displayCents(total)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving
                ? null
                : () => Navigator.pop(context, result != null),
            child: Text(result == null ? 'Close' : 'Done'),
          ),
          if (result == null && !_loading && _pending)
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Retry saved return'),
            )
          else if (result == null && !_loading && available.isNotEmpty)
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Record return'),
            )
          else if (result == null && !_loading && _lines == null)
            TextButton(
              onPressed: _saving ? null : _load,
              child: const Text('Reload'),
            ),
        ],
      ),
    );
  }
}
