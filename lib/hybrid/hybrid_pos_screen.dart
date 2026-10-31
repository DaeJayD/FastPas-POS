import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/pos_form_dialog.dart';
import '../core/fastpas_theme.dart';
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
  Map<String, int> _prices = {};
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
            _prices = {};
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
        _prices = {
          for (final p in products) p['id'] as String: p['price_cents'] as int,
        };
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
        await SyncService(
          widget.client,
          _store!,
          isActive: () => mounted,
        ).synchronize();
      }
      if (mounted) setState(() => _status = 'Connected · changes synchronized');
    } catch (_) {
      if (mounted) {
        setState(() => _status = 'Not synchronized · using saved data');
      }
    } finally {
      if (mounted) await _load();
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

  int get _total => _cart.entries.fold(
    0,
    (sum, entry) => sum + (_prices[entry.key] ?? 0) * entry.value,
  );

  Future<void> _checkout() async {
    if (_busy || !_allowed || _cart.isEmpty) return;
    final totalDue = _total;
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => PosFormDialog(
        title: 'Cash payment',
        description:
            'Total due ${displayCents(totalDue)}. Exact cash is prefilled.',
        fields: [
          PosFormField(
            label: 'Cash received',
            initialValue: (totalDue / 100).toStringAsFixed(2),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (value) {
              try {
                return parseCents(value ?? '') < totalDue
                    ? 'Cash must cover the total due.'
                    : null;
              } on FormatException catch (error) {
                return error.message;
              }
            },
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      if (widget.client.auth.currentUser?.id != _store!.userId) {
        throw StateError('Account changed');
      }
      final cash = parseCents(result['Cash received']!);
      final id = await _store!.checkout(Map.of(_cart), cash);
      final saved = await _store!.receipt(id);
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
    if (_busy || widget.client.auth.currentUser?.id != _userId) return;
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => PosFormDialog(
        title: 'Add product · online',
        fields: [
          PosFormField(
            label: 'Name',
            validator: (value) =>
                (value ?? '').trim().isEmpty || value!.trim().length > 120
                ? 'Enter a name between 1 and 120 characters.'
                : null,
          ),
          PosFormField(
            label: 'SKU',
            validator: (value) =>
                (value ?? '').trim().isEmpty || value!.trim().length > 80
                ? 'Enter a SKU between 1 and 80 characters.'
                : null,
          ),
          PosFormField(
            label: 'Price',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (value) {
              try {
                return parseCents(value ?? '') > 1000000000
                    ? 'Maximum price is ₱10,000,000.00.'
                    : null;
              } on FormatException catch (error) {
                return error.message;
              }
            },
          ),
          PosFormField(
            label: 'Opening stock',
            initialValue: '0',
            keyboardType: TextInputType.number,
            validator: (value) {
              final quantity = int.tryParse((value ?? '').trim());
              return quantity == null || quantity < 0 || quantity > 2147483647
                  ? 'Enter a whole quantity from 0 to 2147483647.'
                  : null;
            },
          ),
        ],
      ),
    );
    if (result == null ||
        !mounted ||
        widget.client.auth.currentUser?.id != _userId) {
      return;
    }
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
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160);
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '${widget.business.name} · ${widget.branch.name}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              onPressed: _busy || _syncing ? null : _startSync,
              tooltip: 'Sync now',
              icon: const Icon(Icons.sync),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: _products.length + _receipts.length + 2,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Volt.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Volt.line),
                      ),
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: motion,
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _syncing
                                  ? Colors.amber.shade700
                                  : (_allowed
                                        ? Colors.teal.shade700
                                        : Volt.muted),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _status,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$pending pending · $blocked need review',
                                  style: const TextStyle(color: Volt.muted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
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
                    const SizedBox(height: 12),
                    if (_products.isEmpty)
                      const Text(
                        'Connect to download products, or add your first product.',
                      ),
                  ],
                );
              }
              if (index <= _products.length) {
                final p = _products[index - 1];
                final quantity = _cart[p['id']] ?? 0;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(
                      color: quantity > 0 ? Volt.ink : Volt.line,
                    ),
                  ),
                  child: AnimatedContainer(
                    duration: motion,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: quantity > 0
                          ? Volt.lime.withValues(alpha: .08)
                          : Volt.surface,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p['name'] as String,
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            Text(
                              p['sku'] as String,
                              style: const TextStyle(color: Volt.muted),
                            ),
                            Text(
                              displayCents(p['price_cents'] as int),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${p['quantity']} locally available',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            Row(
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
                                AnimatedSwitcher(
                                  duration: motion,
                                  child: Text(
                                    '$quantity',
                                    key: ValueKey(quantity),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
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
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }
              final receiptIndex = index - _products.length - 2;
              if (receiptIndex < 0) {
                return Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 12),
                  child: Text(
                    'Saved receipts',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                );
              }
              final receipt = _receipts[receiptIndex];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
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
              );
            },
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: _busy || !_allowed || _cart.isEmpty ? null : _checkout,
              icon: const Icon(Icons.shopping_bag_outlined, size: 20),
              label: Text('Cash checkout · ${displayCents(_total)}'),
            ),
          ),
        ),
      ),
    );
  }
}
