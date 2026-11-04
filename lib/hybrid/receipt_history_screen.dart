import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/fastpas_theme.dart';
import 'cash_rules.dart';
import 'local_store.dart';
import 'receipt_history.dart';
import 'receipt_presenter.dart';

/// Borrows the branch connection; the selling route owns its lifetime.
class ReceiptHistoryScreen extends StatefulWidget {
  const ReceiptHistoryScreen({
    super.key,
    required this.client,
    required this.store,
    required this.branchName,
    required this.onSync,
  });
  final SupabaseClient client;
  final LocalStore store;
  final String branchName;
  final Future<void> Function() onSync;

  @override
  State<ReceiptHistoryScreen> createState() => _ReceiptHistoryScreenState();
}

class _ReceiptHistoryScreenState extends State<ReceiptHistoryScreen> {
  List<SavedReceipt> _entries = [];
  ReceiptCounts _counts = const ReceiptCounts();
  String? _status, _error;
  int? _next;
  int _request = 0;
  bool _loading = true, _syncing = false, _opening = false;
  BuildContext? _dialog;
  StreamSubscription<AuthState>? _auth;
  bool get _sameAccount =>
      widget.client.auth.currentUser?.id == widget.store.userId;

  @override
  void initState() {
    super.initState();
    _auth = widget.client.auth.onAuthStateChange.listen((_) {
      if (!mounted || _sameAccount) return;
      _request++;
      final dialog = _dialog;
      _dialog = null;
      if (dialog != null && dialog.mounted) Navigator.pop(dialog);
      setState(() {
        _entries = [];
        _counts = const ReceiptCounts();
        _next = null;
        _loading = false;
        _error = 'Account changed. Return to your businesses.';
      });
    });
    unawaited(_load());
  }

  Future<void> _load({bool reset = true}) async {
    if (!_sameAccount || (!reset && (_loading || _next == null))) return;
    final request = reset ? ++_request : _request;
    final before = reset ? null : _next;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _entries = [];
        _next = null;
      }
    });
    try {
      final data = await Future.wait<Object>([
        widget.store.receiptCounts(),
        widget.store.receiptPage(status: _status, before: before),
      ]);
      if (!mounted || request != _request || !_sameAccount) return;
      final page = data[1] as ReceiptPage;
      setState(() {
        _counts = data[0] as ReceiptCounts;
        _entries = reset ? page.entries : [..._entries, ...page.entries];
        _next = page.nextBefore;
      });
    } catch (_) {
      if (mounted && request == _request && _sameAccount) {
        setState(() => _error = 'Could not read saved receipts. Try again.');
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _sync() async {
    if (_syncing || !_sameAccount) return;
    setState(() => _syncing = true);
    try {
      await widget.onSync();
      if (mounted && _sameAccount) await _load();
    } catch (_) {
      if (mounted && _sameAccount) {
        setState(
          () =>
              _error = 'Sync did not finish. Receipts are kept on this device.',
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _open(SavedReceipt summary) async {
    if (_opening || !_sameAccount) return;
    _opening = true;
    try {
      final row = await widget.store.receipt(summary.id);
      if (!mounted || !_sameAccount) return;
      await showDialog<void>(
        context: context,
        builder: (context) {
          _dialog = context;
          return AlertDialog(
            title: Text(
              'Receipt · ${receiptStatusLabel(row['status'] as String)}',
            ),
            scrollable: true,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (row['error'] != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      row['error'] as String,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                SelectableText(
                  receiptText(
                    jsonDecode(row['payload'] as String)
                        as Map<String, dynamic>,
                    row['total_cents'] as int,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    } catch (_) {
      if (mounted && _sameAccount) {
        setState(
          () => _error = 'Could not open this receipt. Refresh and try again.',
        );
      }
    } finally {
      _dialog = null;
      _opening = false;
    }
  }

  @override
  void dispose() {
    _auth?.cancel();
    super.dispose();
  }

  Widget _filter(String label, String? status) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: _status == status,
      onSelected: !_sameAccount || _syncing
          ? null
          : (_) {
              setState(() => _status = status);
              unawaited(_load());
            },
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Saved receipts'),
      actions: [
        IconButton(
          onPressed: _loading || !_sameAccount ? null : () => _load(),
          tooltip: 'Refresh receipts',
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          onPressed: _syncing || !_sameAccount ? null : _sync,
          tooltip: 'Sync now',
          icon: const Icon(Icons.sync),
        ),
      ],
    ),
    body: SafeArea(
      child: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _entries.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_sameAccount) ...[
                  Text(
                    'Receipts on this device · ${widget.branchName}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_counts.pending} pending · ${_counts.blocked} need review · ${_counts.synced} synced',
                    style: const TextStyle(color: Volt.muted),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _filter('All', null),
                        _filter('Pending', 'pending'),
                        _filter('Synced', 'synced'),
                        _filter('Needs review', 'blocked'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_syncing) const LinearProgressIndicator(),
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  if (_sameAccount)
                    TextButton(
                      onPressed: () => _load(reset: _entries.isEmpty),
                      child: const Text('Retry receipts'),
                    ),
                ],
                if (!_loading &&
                    _entries.isEmpty &&
                    _sameAccount &&
                    _error == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No receipts in this view yet.',
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            );
          }
          if (index == _entries.length + 1) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _next != null
                  ? OutlinedButton(
                      onPressed: () => _load(reset: false),
                      child: const Text('Load more receipts'),
                    )
                  : const SizedBox.shrink(),
            );
          }
          final receipt = _entries[index - 1];
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: Icon(
                receipt.status == 'blocked'
                    ? Icons.error_outline
                    : receipt.status == 'synced'
                    ? Icons.cloud_done_outlined
                    : Icons.schedule,
                color: receipt.status == 'blocked'
                    ? Theme.of(context).colorScheme.error
                    : Volt.muted,
              ),
              title: Text(
                '${displayCents(receipt.totalCents)} · ${receiptStatusLabel(receipt.status)}',
              ),
              subtitle: Text(
                receipt.error ?? receipt.id,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(receipt),
            ),
          );
        },
      ),
    ),
  );
}
