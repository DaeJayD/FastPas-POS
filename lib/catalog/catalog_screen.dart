import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/pos_form_dialog.dart';
import '../hybrid/cash_rules.dart';
import '../workspaces/workspace_repository.dart';
import 'catalog_repository.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({
    super.key,
    required this.client,
    required this.business,
    required this.branch,
  });
  final SupabaseClient client;
  final BusinessWorkspace business;
  final WorkspaceBranch branch;
  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen>
    with SingleTickerProviderStateMixin {
  late final CatalogRepository _repository = CatalogRepository(
    widget.client,
    widget.business.id,
  );
  late final TabController _tabs = TabController(length: 3, vsync: this);
  late WorkspaceBranch _branch = widget.branch;
  late final String? _actor = widget.client.auth.currentUser?.id;
  List<WorkspaceBranch> _branches = [];
  List<CatalogLabel> _labels = [];
  List<CatalogItem> _items = [];
  List<Map<String, dynamic>> _movements = [];
  String _kind = 'category', _search = '';
  String? _historyProduct, _error;
  bool _ready = false;
  bool _busy = false,
      _archived = false,
      _moreItems = false,
      _moreHistory = false;
  int _generation = 0;
  Timer? _debounce;
  StreamSubscription<AuthState>? _auth;
  BuildContext? _dialog;

  @override
  void initState() {
    super.initState();
    _auth = widget.client.auth.onAuthStateChange.listen(
      (event) {
        if (mounted && event.session?.user.id != _actor) {
          _generation++;
          final dialog = _dialog;
          _dialog = null;
          if (dialog != null && dialog.mounted) Navigator.pop(dialog);
          setState(() {
            _labels = [];
            _items = [];
            _movements = [];
            _branches = [];
            _busy = false;
            _ready = false;
            _error = 'Account changed. Return to Businesses.';
          });
        }
      },
      onError: (_) {
        if (mounted) {
          setState(() => _error = 'Reconnect to manage catalog and inventory.');
        }
      },
    );
    unawaited(_reload());
  }

  @override
  void dispose() {
    _generation++;
    _auth?.cancel();
    _debounce?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  static String _message(Object error) {
    if (error is FormatException) return error.message;
    if (error is SocketException ||
        error is ClientException ||
        error is TimeoutException ||
        error is AuthRetryableFetchException) {
      return 'Connection unavailable. Reconnect and try again.';
    }
    if (error is PostgrestException) {
      return switch (error.code) {
        'PGRST202' => 'Catalog and inventory are not available yet. Refresh after your workspace is updated.',
        '42501' =>
          'Owner access is required for catalog and inventory changes.',
        'PT409' || '40001' =>
          'This record changed. Cancel and refresh before trying again.',
        '23505' => 'That SKU, label name, or family variant already exists.',
        '22023' => 'Check the details and available stock. If a retry was changed, cancel and refresh first.',
        'PGRST301' || 'PGRST302' || 'PGRST303' =>
          'Return to Businesses and sign in again with the same account.',
        _ => 'Could not complete the request. Reconnect and try again.',
      };
    }
    return 'Could not complete the request. Reconnect and try again.';
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _repository.checkIdentity();
      final results = await Future.wait<dynamic>([
        _repository.labels(),
        _repository.items(_branch.id, search: _search, archived: _archived),
        _repository.history(_branch.id, product: _historyProduct),
        WorkspaceRepository(widget.client).branches(widget.business.id),
      ]);
      if (!mounted || generation != _generation) return;
      setState(() {
        _ready = true;
        _labels = results[0] as List<CatalogLabel>;
        _items = results[1] as List<CatalogItem>;
        _movements = results[2] as List<Map<String, dynamic>>;
        _branches = results[3] as List<WorkspaceBranch>;
        _moreItems = _items.length == 50;
        _moreHistory = _movements.length == 50;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _ready = false;
          _error = _message(error);
          _items = [];
          _movements = [];
          _labels = [];
        });
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _more(bool history) async {
    if (_busy) return;
    final generation = _generation;
    setState(() => _busy = true);
    try {
      if (history) {
        final rows = await _repository.history(
          _branch.id,
          product: _historyProduct,
          offset: _movements.length,
        );
        if (mounted && generation == _generation) {
          setState(() {
            _movements.addAll(rows);
            _moreHistory = rows.length == 50;
          });
        }
      } else {
        final rows = await _repository.items(
          _branch.id,
          offset: _items.length,
          search: _search,
          archived: _archived,
        );
        if (mounted && generation == _generation) {
          setState(() {
            _items.addAll(rows);
            _moreItems = rows.length == 50;
          });
        }
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = _message(error));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _edit(
    String title,
    List<PosFormField> fields,
    Future<void> Function(Map<String, String>) save, {
    String? description,
  }) async {
    if (_busy || !_ready || widget.client.auth.currentUser?.id != _actor) {
      return;
    }
    final result = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        _dialog = context;
        return PosFormDialog(
          title: title,
          description: description,
          fields: fields,
          errorMessage: _message,
          onSave: (values) async {
            _repository.checkIdentity();
            await save(values);
            _repository.checkIdentity();
          },
        );
      },
    );
    _dialog = null;
    if (result != null &&
        mounted &&
        widget.client.auth.currentUser?.id == _actor) {
      await _reload();
    }
  }

  String? _name(String? value) =>
      (value ?? '').trim().isEmpty || (value ?? '').trim().length > 120
      ? 'Use 1–120 characters.'
      : null;
  String? _quantity(String? value) {
    final number = int.tryParse((value ?? '').trim());
    return number == null || number < 0 || number > 1000000000
        ? 'Use a whole number from 0 to 1000000000.'
        : null;
  }

  Map<String, String> _options(String kind, String? selected) => {
    '': 'None',
    for (final label in _labels.where(
      (label) => label.kind == kind && (label.active || label.id == selected),
    ))
      label.id: label.name + (label.active ? '' : ' (archived)'),
  };
  Future<void> _label([CatalogLabel? label]) async {
    final request = WorkspaceRepository.newRequestId(),
        id = label?.id ?? WorkspaceRepository.newRequestId();
    final kind = label?.kind ?? _kind;
    await _edit(
      label == null ? 'Add $kind' : 'Edit $kind',
      [
        PosFormField(
          label: 'Name',
          initialValue: label?.name ?? '',
          validator: _name,
        ),
        PosFormField(
          label: 'Status',
          initialValue: (label?.active ?? true) ? 'active' : 'archived',
          options: const {'active': 'Active', 'archived': 'Archived'},
        ),
      ],
      (values) => _repository.saveLabel(
        request,
        id,
        kind,
        label?.version ?? 0,
        values['Name']!,
        values['Status'] == 'active',
      ),
    );
  }

  Future<void> _item([CatalogItem? item]) async {
    final request = WorkspaceRepository.newRequestId(),
        id = item?.id ?? WorkspaceRepository.newRequestId();
    await _edit(
      item == null ? 'Add product' : 'Edit product',
      [
        PosFormField(
          label: 'Product name',
          initialValue: item?.baseName ?? '',
          validator: _name,
        ),
        PosFormField(
          label: 'SKU',
          initialValue: item?.sku ?? '',
          validator: (v) => (v ?? '').isEmpty || (v ?? '').length > 80
              ? 'Use 1–80 characters.'
              : null,
        ),
        PosFormField(
          label: 'Price',
          initialValue: ((item?.price ?? 0) / 100).toStringAsFixed(2),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (v) {
            try {
              return parseCents(v ?? '') > 1000000000
                  ? 'Price is too large.'
                  : null;
            } on FormatException catch (e) {
              return e.message;
            }
          },
        ),
        PosFormField(
          label: 'Brand',
          initialValue: item?.brand ?? '',
          options: _options('brand', item?.brand),
        ),
        PosFormField(
          label: 'Category',
          initialValue: item?.category ?? '',
          options: _options('category', item?.category),
        ),
        PosFormField(
          label: 'Product family',
          initialValue: item?.family ?? '',
          options: _options('family', item?.family),
        ),
        PosFormField(
          label: 'Variant (size / color)',
          initialValue: item?.variant ?? '',
        ),
        if (item == null)
          PosFormField(
            label: 'Opening stock',
            initialValue: '0',
            keyboardType: TextInputType.number,
            validator: _quantity,
          ),
        PosFormField(
          label: 'Status',
          initialValue: (item?.active ?? true) ? 'active' : 'archived',
          options: const {'active': 'Active', 'archived': 'Archived'},
        ),
      ],
      (values) async {
        final variant = values['Variant (size / color)']!,
            family = values['Product family']!;
        if (family.isEmpty != variant.isEmpty) {
          throw const FormatException(
            'Choose a product family and enter a variant together, or leave both empty.',
          );
        }
        if ('${values['Product name']}${variant.isEmpty ? '' : ' · $variant'}'
                .length >
            120) {
          throw const FormatException(
            'The product name and variant together must fit within 120 characters.',
          );
        }
        await _repository.saveItem(request, {
          'id': id,
          'version': item?.version ?? 0,
          'name': values['Product name'],
          'sku': values['SKU'],
          'price_cents': parseCents(values['Price']!),
          'active': values['Status'] == 'active',
          'brand_id': values['Brand']!.isEmpty ? null : values['Brand'],
          'category_id': values['Category']!.isEmpty
              ? null
              : values['Category'],
          'family_id': family.isEmpty ? null : family,
          'variant_label': variant,
          if (item == null) ...{
            'branch_id': _branch.id,
            'opening_quantity': int.parse(values['Opening stock']!),
          },
        });
      },
      description: item == null
          ? 'Add optional brands, categories and families under Classifications. Each variant has its own SKU, price and stock.'
          : 'Saved receipts retain their recorded details. Repricing or archiving may send pending offline sales for review.',
    );
  }

  Future<void> _stock(CatalogItem item, String kind) async {
    final destinations = _branches
        .where((branch) => branch.id != _branch.id)
        .toList();
    if (kind == 'transfer' && destinations.isEmpty) {
      setState(
        () => _error = 'Add another branch in Business settings before transferring stock.',
      );
      return;
    }
    final request = WorkspaceRepository.newRequestId();
    final destinationVersions = <String, int>{};
    final title = switch (kind) {
      'receive' => 'Receive stock',
      'count' => 'Set physical count',
      'transfer' => 'Transfer stock',
      _ => 'Low-stock alert',
    };
    final amountLabel = kind == 'count'
        ? 'Counted quantity'
        : kind == 'threshold'
        ? 'Alert threshold'
        : 'Quantity';
    await _edit(
      title,
      [
        if (kind == 'transfer')
          PosFormField(
            label: 'Destination',
            initialValue: destinations.first.id,
            options: {
              for (final branch in destinations) branch.id: branch.name,
            },
          ),
        PosFormField(
          label: amountLabel,
          initialValue: kind == 'count'
              ? '${item.quantity < 0 ? 0 : item.quantity}'
              : kind == 'threshold'
              ? '${item.threshold}'
              : '1',
          keyboardType: TextInputType.number,
          validator: (v) =>
              _quantity(v) ??
              (kind == 'receive' || kind == 'transfer'
                  ? (int.parse(v!) == 0 ? 'Enter at least one unit.' : null)
                  : null),
        ),
        PosFormField(
          label: 'Reason',
          initialValue: kind == 'threshold' ? 'Low-stock alert' : '',
          maxLines: 2,
          validator: (v) => (v ?? '').isEmpty || (v ?? '').length > 300
              ? 'Use a reason of 1–300 characters.'
              : null,
        ),
      ],
      (values) async {
        final destination = values['Destination'];
        if (destination != null &&
            !destinationVersions.containsKey(destination)) {
          destinationVersions[destination] = await _repository.stockVersion(
            destination,
            item.id,
          );
        }
        await _repository.postStock(request, {
          'kind': kind,
          'branch_id': _branch.id,
          'product_id': item.id,
          'quantity': int.parse(values[amountLabel]!),
          'stock_version': item.stockVersion,
          'reason': values['Reason'],
          if (destination != null) ...{
            'destination_id': destination,
            'destination_version': destinationVersions[destination],
          },
        });
      },
      description:
          '${item.name}\n${_branch.name} · ${item.quantity} in stock\nChanges require internet. Refresh after another device changes stock.',
    );
  }

  Widget _catalog() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Search name or SKU',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), () {
                  if (mounted) {
                    _search = value;
                    unawaited(_reload());
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _busy || !_ready ? null : () => _item(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add product'),
                ),
                FilterChip(
                  label: const Text('Include archived'),
                  selected: _archived,
                  onSelected: _busy
                      ? null
                      : (value) {
                          _archived = value;
                          unawaited(_reload());
                        },
                ),
              ],
            ),
          ],
        ),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _items.length + 1,
          itemBuilder: (context, index) {
            if (index == _items.length) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: _moreItems
                    ? OutlinedButton(
                        onPressed: _busy ? null : () => _more(false),
                        child: const Text('Load more products'),
                      )
                    : Text(
                        _items.isEmpty && !_busy
                            ? 'No matching products.'
                            : '${_items.length} products loaded.',
                      ),
              );
            }
            final item = _items[index];
            final names = _labels
                .where(
                  (label) => [
                    item.brand,
                    item.category,
                    item.family,
                  ].contains(label.id),
                )
                .map((label) => label.name)
                .join(' · ');
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text('${item.sku} · ${displayCents(item.price)}'),
                          if (names.isNotEmpty) Text(names),
                          const SizedBox(height: 8),
                          Text(
                            '${item.quantity} in stock${item.active ? '' : ' · Archived'}',
                          ),
                          if (item.quantity < 0)
                            const Text(
                              'Stock needs review',
                              style: TextStyle(color: Colors.red),
                            )
                          else if (item.threshold > 0 &&
                              item.quantity <= item.threshold)
                            Text(
                              'Low stock · alert at ${item.threshold}',
                              style: const TextStyle(color: Colors.deepOrange),
                            ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Product actions',
                      enabled: !_busy,
                      onSelected: (action) {
                        if (action == 'edit') {
                          unawaited(_item(item));
                        } else if (action == 'history') {
                          _historyProduct = item.id;
                          _tabs.index = 2;
                          unawaited(_reload());
                        } else {
                          unawaited(_stock(item, action));
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit product'),
                        ),
                        PopupMenuItem(
                          value: 'receive',
                          child: Text('Receive stock'),
                        ),
                        PopupMenuItem(
                          value: 'count',
                          child: Text('Set physical count'),
                        ),
                        PopupMenuItem(
                          value: 'transfer',
                          child: Text('Transfer stock'),
                        ),
                        PopupMenuItem(
                          value: 'threshold',
                          child: Text('Low-stock alert'),
                        ),
                        PopupMenuItem(
                          value: 'history',
                          child: Text('Movement history'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
  Widget _classifications() {
    final labels = _labels.where((label) => label.kind == _kind).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: _kind,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Classification'),
                items: const [
                  DropdownMenuItem(value: 'brand', child: Text('Brands')),
                  DropdownMenuItem(
                    value: 'category',
                    child: Text('Categories'),
                  ),
                  DropdownMenuItem(
                    value: 'family',
                    child: Text('Product families'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _kind = value);
                },
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy || !_ready ? null : () => _label(),
                icon: const Icon(Icons.add),
                label: const Text('Add classification'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: labels.isEmpty ? 1 : labels.length,
            itemBuilder: (context, index) {
              if (labels.isEmpty) {
                return const Text(
                  'Classifications are optional. Add them when your catalog needs grouping.',
                );
              }
              final label = labels[index];
              return Card(
                child: ListTile(
                  title: Text(label.name),
                  subtitle: Text(label.active ? 'Active' : 'Archived'),
                  trailing: IconButton(
                    tooltip: 'Edit classification',
                    onPressed: _busy ? null : () => _label(label),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _history() => Column(
    children: [
      if (_historyProduct != null)
        TextButton(
          onPressed: _busy
              ? null
              : () {
                  _historyProduct = null;
                  unawaited(_reload());
                },
          child: const Text('Show all products'),
        ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _movements.length + 1,
          itemBuilder: (context, index) {
            if (index == _movements.length) {
              return _moreHistory
                  ? OutlinedButton(
                      onPressed: _busy ? null : () => _more(true),
                      child: const Text('Load more movements'),
                    )
                  : Text(
                      _movements.isEmpty && !_busy
                          ? 'No stock movements recorded.'
                          : '${_movements.length} movements loaded.',
                    );
            }
            final row = _movements[index],
                delta = (_movements[index]['quantity_delta'] as num).toInt();
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${row['product_name']} · ${row['sku']}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${row['kind']} · ${delta > 0 ? '+' : ''}$delta · ${row['before_quantity']} → ${row['after_quantity']}',
                    ),
                    Text(row['reason'] as String),
                    Text(
                      '${DateTime.tryParse(row['created_at'] as String)?.toLocal() ?? row['created_at']}',
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Catalog & inventory'),
      actions: [
        IconButton(
          tooltip: 'Refresh inventory',
          onPressed: _busy ? null : _reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: DropdownButtonFormField<String>(
                  key: ValueKey(_branch.id),
                  initialValue: _branch.id,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Branch'),
                  items: [
                    for (final branch
                        in (_branches.isEmpty ? [_branch] : _branches))
                      DropdownMenuItem(
                        value: branch.id,
                        child: Text(
                          branch.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) {
                          if (value != null) {
                            _branch = _branches.firstWhere(
                              (branch) => branch.id == value,
                            );
                            _historyProduct = null;
                            unawaited(_reload());
                          }
                        },
                ),
              ),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      Text(_error!),
                      TextButton(
                        onPressed: _busy ? null : _reload,
                        child: const Text('Retry inventory'),
                      ),
                    ],
                  ),
                ),
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                controller: _tabs,
                tabs: const [
                  Tab(text: 'Products'),
                  Tab(text: 'Classifications'),
                  Tab(text: 'Movements'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [_catalog(), _classifications(), _history()],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
