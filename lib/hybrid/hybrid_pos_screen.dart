import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../workspaces/workspace_repository.dart';
import 'cash_rules.dart';
import 'local_store.dart';
import 'sync_service.dart';

class HybridPosScreen extends StatefulWidget {
  const HybridPosScreen({
    super.key,
    required this.client,
    required this.business,
    required this.branch,
    this.openStore,
    this.synchronize,
  });
  final SupabaseClient client;
  final BusinessWorkspace business;
  final WorkspaceBranch branch;
  final Future<LocalStore> Function()? openStore;
  final Future<void> Function(LocalStore)? synchronize;

  @override
  State<HybridPosScreen> createState() => _HybridPosScreenState();
}

class _HybridPosScreenState extends State<HybridPosScreen>
    with WidgetsBindingObserver {
  LocalStore? _store;
  Timer? _timer;
  StreamSubscription<AuthState>? _auth;
  late final String? _userId;
  Future<void>? _operation;
  List<Map<String, Object?>> _products = [], _receipts = [];
  final _cart = <String, int>{};
  bool _busy = true;
  bool _syncing = false;
  bool _allowed = false;
  String _status = 'Opening saved store…';

  @override
  void initState() {
    super.initState();
    _userId = widget.client.auth.currentUser?.id;
    WidgetsBinding.instance.addObserver(this);
    _auth = widget.client.auth.onAuthStateChange.listen(
      (event) {
        if (mounted && event.session?.user.id != _userId) {
          setState(() {
            _products = [];
            _receipts = [];
            _cart.clear();
            _allowed = false;
            _status = 'Account changed. Return to your businesses.';
          });
        }
      },
      onError: (_) {
        if (mounted) setState(() => _status = 'Offline · using saved data');
      },
    );
    _operation = _open();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _startSync());
  }

  Future<void> _open() async {
    try {
      final user = widget.client.auth.currentUser;
      if (user == null) throw StateError('Sign in first.');
      final store =
          await (widget.openStore?.call() ??
              LocalStore.open(
                userId: user.id,
                businessId: widget.business.id,
                branchId: widget.branch.id,
              ));
      if (!mounted) {
        await store.close();
        return;
      }
      _store = store;
      await _load();
      if (mounted) setState(() => _busy = false);
      await _sync();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = 'Could not open this store. Try again.';
        });
      }
    }
  }

  Future<void> _load() async {
    final store = _store!;
    if (widget.client.auth.currentUser?.id != store.userId) return;
    final products = await store.products();
    final receipts = await store.receipts();
    final allowed =
        widget.client.auth.currentUser?.id == store.userId &&
        await store.canSell();
    if (mounted && widget.client.auth.currentUser?.id == store.userId) {
      setState(() {
        _products = products;
        _receipts = receipts;
        _allowed = allowed;
      });
    }
  }

  void _startSync() {
    if (_busy || _syncing || _store == null || !mounted) return;
    _operation = _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _startSync();
  }

  Future<void> _sync() async {
    if (_busy || _syncing || _store == null || !mounted) return;
    setState(() {
      _syncing = true;
      _status = 'Syncing…';
    });
    try {
      if (widget.synchronize != null) {
        await widget.synchronize!(_store!);
      } else {
        await SyncService(widget.client, _store!).synchronize();
      }
      if (mounted) setState(() => _status = 'Connected · changes synchronized');
    } catch (_) {
      if (mounted) {
        setState(() => _status = 'Not synchronized · using saved data');
      }
    } finally {
      await _load();
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _auth?.cancel();
    final store = _store;
    final operation = _operation;
    if (store != null) {
      unawaited(() async {
        try {
          await operation;
        } finally {
          await store.close();
        }
      }());
    }
    super.dispose();
  }

  int get _total => _products.fold(
    0,
    (sum, p) => sum + (p['price_cents'] as int) * (_cart[p['id']] ?? 0),
  );

  Future<Map<String, String>?> _form(
    String title,
    Map<String, String> fields,
  ) async {
    final controllers = fields.map(
      (key, value) => MapEntry(key, TextEditingController(text: value)),
    );
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in controllers.entries)
                TextField(
                  controller: entry.value,
                  decoration: InputDecoration(labelText: entry.key),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              controllers.map((k, v) => MapEntry(k, v.text)),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final controller in controllers.values) {
      controller.dispose();
    }
    return result;
  }

  Future<void> _checkout() async {
    if (_busy || !_allowed || _cart.isEmpty) return;
    final result = await _form('Cash payment', {
      'Cash received': (_total / 100).toStringAsFixed(2),
    });
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      if (widget.client.auth.currentUser?.id != _store!.userId) {
        throw StateError('Account changed');
      }
      final cash = parseCents(result['Cash received']!);
      final id = await _store!.checkout(Map.of(_cart), cash);
      final saved = (await _store!.receipts()).firstWhere(
        (row) => row['id'] == id,
      );
      final total = saved['total_cents'] as int;
      _cart.clear();
      await _load();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Sale saved on this device'),
          content: SelectableText(
            'Receipt $id\nTotal ${displayCents(total)}\nCash ${displayCents(cash)}\nChange ${displayCents(cash - total)}\nPending cloud synchronization',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _status =
              'Sale was not saved. Check cash, stock, and selling access.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    _startSync();
  }

  Future<void> _addProduct() async {
    final result = await _form('Add product · online', {
      'Name': '',
      'SKU': '',
      'Price': '',
      'Opening stock': '0',
    });
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.client.rpc(
        'pos_add_item',
        params: {
          'business': widget.business.id,
          'branch': widget.branch.id,
          'product_name': result['Name']!.trim(),
          'product_sku': result['SKU']!.trim(),
          'unit_cents': parseCents(result['Price']!),
          'opening_quantity': int.parse(result['Opening stock']!),
        },
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _status = 'Could not add product. Connect and check the SKU, price, and stock.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    _startSync();
  }

  @override
  Widget build(BuildContext context) {
    final pending = _receipts.where((r) => r['status'] == 'pending').length;
    final blocked = _receipts.where((r) => r['status'] == 'blocked').length;
    return PopScope(
      canPop: !_busy && !_syncing,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.business.name} · ${widget.branch.name}'),
          actions: [
            IconButton(
              onPressed: _busy || _syncing ? null : _startSync,
              tooltip: 'Sync now',
              icon: const Icon(Icons.sync),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(_status),
              Text('$pending pending · $blocked need review'),
              if (!_allowed)
                const Text(
                  'Connect to verify selling access. Offline access lasts up to 24 hours after verification.',
                ),
              if (_busy || _syncing) const LinearProgressIndicator(),
              const SizedBox(height: 12),
              if (widget.business.role == 'owner')
                OutlinedButton.icon(
                  onPressed: _busy ? null : _addProduct,
                  icon: const Icon(Icons.add),
                  label: const Text('Add product'),
                ),
              if (_products.isEmpty)
                const Text(
                  'Connect to download products, or add your first product.',
                ),
              for (final p in _products)
                Card(
                  child: ListTile(
                    title: Text(p['name'] as String),
                    subtitle: Text(
                      '${p['sku']} · ${displayCents(p['price_cents'] as int)} · ${p['quantity']} locally available',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Remove one',
                          onPressed: _busy || (_cart[p['id']] ?? 0) == 0
                              ? null
                              : () => setState(() {
                                  final id = p['id'] as String;
                                  if (_cart[id] == 1) {
                                    _cart.remove(id);
                                  } else {
                                    _cart[id] = _cart[id]! - 1;
                                  }
                                }),
                          icon: const Icon(Icons.remove),
                        ),
                        Text('${_cart[p['id']] ?? 0}'),
                        IconButton(
                          tooltip: 'Add one',
                          onPressed:
                              _busy ||
                                  !_allowed ||
                                  (_cart[p['id']] ?? 0) >=
                                      (p['quantity'] as int)
                              ? null
                              : () => setState(() {
                                  final id = p['id'] as String;
                                  _cart[id] = (_cart[id] ?? 0) + 1;
                                }),
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                'Saved receipts',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final receipt in _receipts)
                ListTile(
                  title: Text(
                    '${displayCents(receipt['total_cents'] as int)} · ${receipt['status']}',
                  ),
                  subtitle: Text(
                    receipt['error'] as String? ?? receipt['id'] as String,
                  ),
                  onTap: () {
                    final sale = jsonDecode(
                      receipt['payload'] as String,
                    ) as Map<String, dynamic>;
                    showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('Receipt · ${receipt['status']}'),
                        content: SingleChildScrollView(
                          child: SelectableText(
                            '${sale['id']}\n${sale['occurred_at']}\n'
                            '${(sale['items'] as List).map((l) => '${l['quantity']} × ${l['name']} · ${displayCents(l['unit_cents'] as int)}').join('\n')}\n'
                            'Total ${displayCents(receipt['total_cents'] as int)}',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: _busy || !_allowed || _cart.isEmpty ? null : _checkout,
              child: Text('Cash checkout · ${displayCents(_total)}'),
            ),
          ),
        ),
      ),
    );
  }
}
