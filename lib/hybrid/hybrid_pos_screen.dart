import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/pos_form_dialog.dart';
import '../core/fastpas_theme.dart';
import '../workspaces/workspace_repository.dart';
import 'cash_rules.dart';
import 'cash_payment_dialog.dart';
import 'checkout_quote.dart';
import 'local_store.dart';
import 'sync_service.dart';
import 'selling_home.dart';
import 'receipt_history.dart';
import 'receipt_history_screen.dart';
import '../core/receipt_details.dart';
import 'receipt_presenter.dart';

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
  List<Map<String, Object?>> _products = [];
  ReceiptCounts _receiptCounts = const ReceiptCounts();
  Map<String, int> _prices = {};
  final _cart = <String, int>{};
  final _search = TextEditingController();
  String? _category;
  bool _busy = true;
  bool _paying = false;
  BuildContext? _paymentDialog;
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
          final dialog = _paymentDialog;
          _paymentDialog = null;
          if (dialog != null && dialog.mounted) Navigator.pop(dialog);
          setState(() {
            _products = [];
            _receiptCounts = const ReceiptCounts();
            _prices = {};
            _cart.clear();
            _search.clear();
            _category = null;
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
    final receipts = await store.receiptCounts();
    final allowed =
        widget.client.auth.currentUser?.id == store.userId &&
        await store.canSell();
    if (mounted && widget.client.auth.currentUser?.id == store.userId) {
      setState(() {
        _products = products;
        _receiptCounts = receipts;
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
      if (mounted) {
        setState(() {
          _syncing = false;
          if (widget.client.auth.currentUser?.id != _userId) {
            _status = 'Account changed. Return to your businesses.';
          }
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _auth?.cancel();
    _search.dispose();
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
    if (_busy || _paying || !_allowed || _cart.isEmpty) return;
    setState(() => _paying = true);
    String? committedId;
    try {
      final quantities = Map<String, int>.of(_cart);
      final quote = CheckoutQuote.capture(
        userId: _userId!,
        businessId: widget.business.id,
        branchId: widget.branch.id,
        products: _products,
        quantities: quantities,
      );
      await showDialog<void>(
        context: context,
        builder: (dialog) {
          _paymentDialog = dialog;
          return CashPaymentDialog(
            quote: quote,
            onConfirm: (cashCents) async {
              if (widget.client.auth.currentUser?.id != _store!.userId) {
                throw const FormatException(
                  'Account changed. Return to your businesses.',
                );
              }
              committedId = await _store!.checkout(
                quantities,
                cashCents,
                quote: quote,
                isActive: () =>
                    mounted && widget.client.auth.currentUser?.id == _userId,
                fallbackReceiptDetails: ReceiptDetails(
                  businessId: widget.business.id,
                  branchId: widget.branch.id,
                  businessName: widget.business.name,
                  branchName: widget.branch.name,
                ),
              );
              _cart.clear();
            },
          );
        },
      );
      if (!mounted || widget.client.auth.currentUser?.id != _userId) return;
      if (committedId == null) {
        await _load();
        return;
      }
      setState(() => _busy = true);
      final saved = await _store!.receipt(committedId!);
      final total = saved['total_cents'] as int;
      await _load();
      if (!mounted || widget.client.auth.currentUser?.id != _userId) return;
      await showDialog<void>(
        context: context,
        builder: (context) {
          _paymentDialog = context;
          return AlertDialog(
            title: const Text('Sale saved on this device'),
            scrollable: true,
            content: SelectableText(
              '${receiptText(jsonDecode(saved['payload'] as String) as Map<String, dynamic>, total)}\n\nPending cloud synchronization',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          );
        },
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _status = committedId != null
              ? 'Sale saved. Reopen Saved receipts to view it.'
              : error is CheckoutChanged
              ? error.message
              : 'Sale was not saved. Check cash, stock, and selling access.',
        );
      }
    } finally {
      _paymentDialog = null;
      if (mounted) {
        setState(() {
          _busy = false;
          _paying = false;
        });
      }
    }
    _startSync();
  }

  Future<void> _addProduct() async {
    if (_busy || _paying || widget.client.auth.currentUser?.id != _userId) {
      return;
    }
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

  void _retryOpen() {
    if (_busy || _store != null) return;
    setState(() {
      _busy = true;
      _status = 'Opening saved store…';
    });
    _operation = _open();
  }

  void _changeQuantity(String id, int delta) {
    if (_busy || _paying) return;
    setState(() {
      final next = (_cart[id] ?? 0) + delta;
      if (next <= 0) {
        _cart.remove(id);
      } else {
        _cart[id] = next;
      }
    });
  }

  Future<void> _history() async {
    if (_store == null ||
        _busy ||
        _paying ||
        widget.client.auth.currentUser?.id != _userId) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReceiptHistoryScreen(
          client: widget.client,
          store: _store!,
          branchName: widget.branch.name,
          canRecordReturns:
              widget.business.role == 'owner' ||
              widget.business.role == 'manager',
          onSync: () async {
            _startSync();
            await _operation;
          },
        ),
      ),
    );
    if (mounted && widget.client.auth.currentUser?.id == _userId) await _load();
  }

  Widget _cartBar() {
    final count = _cart.values.fold(0, (sum, quantity) => sum + quantity);
    return Container(
      decoration: const BoxDecoration(
        color: Volt.surface,
        border: Border(top: BorderSide(color: Volt.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.shopping_bag_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      count == 0
                          ? 'Your cart is empty'
                          : '$count ${count == 1 ? 'item' : 'items'} in cart',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (_cart.isNotEmpty)
                    TextButton(
                      onPressed: _busy || _paying
                          ? null
                          : () => setState(_cart.clear),
                      child: const Text('Clear cart'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              FilledButton.icon(
                onPressed: _busy || _paying || !_allowed || _cart.isEmpty
                    ? null
                    : _checkout,
                icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                label: Text('Cash checkout · ${displayCents(_total)}'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final visible = _products
        .where(
          (p) =>
              (_category == null || (p['category_id'] ?? '') == _category) &&
              (query.isEmpty ||
                  (p['name'] as String).toLowerCase().contains(query) ||
                  (p['sku'] as String).toLowerCase().contains(query)),
        )
        .toList();
    final categories = <String, String>{};
    if (_products.any(
      (p) => (p['category_id'] as String?)?.isNotEmpty == true,
    )) {
      for (final p in _products) {
        final id = (p['category_id'] as String?) ?? '';
        final name = (p['category_name'] as String?) ?? '';
        categories[id] = id.isEmpty
            ? 'Uncategorized'
            : name.isEmpty
            ? 'Category'
            : name;
      }
    }
    final pending = _receiptCounts.pending;
    final blocked = _receiptCounts.blocked;
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
              onPressed:
                  _store == null ||
                      _busy ||
                      _paying ||
                      widget.client.auth.currentUser?.id != _userId
                  ? null
                  : _history,
              tooltip: 'Saved receipts',
              icon: const Icon(Icons.receipt_long_outlined),
            ),
            IconButton(
              onPressed: _busy || _syncing ? null : _startSync,
              tooltip: 'Sync now',
              icon: const Icon(Icons.sync),
            ),
          ],
        ),
        body: SafeArea(
          child: SellingHome(
            products: visible,
            catalogEmpty: _products.isEmpty,
            cart: _cart,
            search: _search,
            onSearch: () => setState(() {}),
            categories: categories,
            category: _category,
            onCategory: (value) => setState(() => _category = value),
            onQuantity: _changeQuantity,
            status: _status,
            pending: pending,
            blocked: blocked,
            busy: _busy,
            syncing: _syncing,
            locked:
                _busy ||
                _paying ||
                widget.client.auth.currentUser?.id != _userId,
            allowed: _allowed,
            onAddProduct: widget.business.role == 'owner' ? _addProduct : null,
            onRetry: !_busy && _store == null ? _retryOpen : null,
          ),
        ),
        bottomNavigationBar: _cartBar(),
      ),
    );
  }
}
