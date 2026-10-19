import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../catalog/catalog_source.dart';
import '../core/fastpas_theme.dart';
import '../dashboard/home_screen.dart';
import '../employees/employee_page.dart';
import '../inventory/inventory_screen.dart';
import '../main.dart';
import '../reports/reports_page.dart';
import '../sales/checkout_page.dart';
import '../sales/sales_history_page.dart';
import '../suppliers/suppliers_creen.dart';
import '../users/users_page.dart';

class ProductHomeScreen extends StatefulWidget {
  const ProductHomeScreen({
    super.key,
    required this.fullName,
    required this.role,
    required this.userId,
    required this.location,
    this.source,
  });
  final String fullName;
  final String role;
  final String userId;
  final String location;
  final CatalogSource? source;

  @override
  State<ProductHomeScreen> createState() => _ProductHomeScreenState();
}

class _ProductHomeScreenState extends State<ProductHomeScreen> {
  late final CatalogSource _source = widget.source ?? SupabaseCatalogSource();
  final _search = TextEditingController();
  final Map<String, int> _cart = {};
  List<StoreBranch> _branches = [];
  List<CatalogProduct> _products = [];
  StoreBranch? _branch;
  bool _loading = true;
  bool _error = false;
  bool _sortByPrice = false;
  String? _category;
  int _tab = 0;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final branches = await _source.branches(
          userId: widget.userId, role: widget.role, location: widget.location);
      if (!mounted || request != _request) return;
      StoreBranch? branch;
      for (final candidate in branches) {
        if (candidate.id == _branch?.id ||
            (_branch == null && candidate.location == widget.location)) {
          branch = candidate;
          break;
        }
      }
      branch ??= branches.firstOrNull;
      final products = branch == null
          ? <CatalogProduct>[]
          : await _source.products(branch.id);
      if (!mounted || request != _request) return;
      setState(() {
        _branches = branches;
        _branch = branch;
        _products = products;
        // Keep quantities within newly loaded stock after refresh.
        final available = {
          for (final product in products) product.id: product.stock
        };
        _cart.removeWhere((id, qty) => (available[id] ?? 0) <= 0);
        for (final id in _cart.keys.toList()) {
          if (_cart[id]! > available[id]!) _cart[id] = available[id]!;
        }
        if (!products.any((p) => p.category == _category)) _category = null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  List<CatalogProduct> get _filtered {
    final query = _search.text.trim().toLowerCase();
    final items = _products
        .where((p) =>
            (_category == null || p.category == _category) &&
            '${p.name} ${p.sku} ${p.category} ${p.brand}'
                .toLowerCase()
                .contains(query))
        .toList();
    if (_sortByPrice) items.sort((a, b) => a.price.compareTo(b.price));
    return items;
  }

  int get _units => _cart.values.fold(0, (sum, qty) => sum + qty);
  double get _subtotal =>
      _products.fold(0, (sum, p) => sum + p.price * (_cart[p.id] ?? 0));

  void _changeQuantity(CatalogProduct product, int change) {
    final quantity = (_cart[product.id] ?? 0) + change;
    if (quantity > product.stock) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('All available stock is already in your cart.')));
      return;
    }
    setState(() {
      if (quantity <= 0) {
        _cart.remove(product.id);
      } else {
        _cart[product.id] = quantity;
      }
    });
  }

  Future<void> _selectBranch(StoreBranch branch) async {
    if (branch.id == _branch?.id) return;
    if (_cart.isNotEmpty) {
      final discard = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('Switch branch?'),
                content: const Text(
                    'Your current cart will be cleared. Each branch has its own stock.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Keep cart')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Switch branch')),
                ],
              ));
      if (discard != true || !mounted) return;
    }
    setState(() {
      _branch = branch;
      _cart.clear();
      _category = null;
    });
    await _load();
  }

  Future<void> _checkout() async {
    if (_units == 0 || _branch == null || _loading || _error) return;
    final items = _products
        .where((p) => _cart.containsKey(p.id))
        .map((p) => p.toCartItem(_cart[p.id]!))
        .toList();
    final result = await Navigator.push<List<Map<String, dynamic>>>(
        context,
        MaterialPageRoute(
            builder: (_) => CheckoutPage(
                  cartItems: items,
                  fullName: widget.fullName,
                  role: widget.role,
                  userId: widget.userId,
                  location: _branch!.location,
                  preview: _source.isPreview,
                )));
    if (!mounted || result == null) return;
    setState(() {
      _cart.clear();
      for (final item in result) {
        _cart[item['id'].toString()] = (item['cart_quantity'] as num).toInt();
      }
    });
  }

  void _open(Widget Function() screen) {
    if (_source.isPreview) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'This section needs a store connection. You are viewing sample data.')));
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen()));
  }

  String get _location => _branch?.location ?? widget.location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverToBoxAdapter(child: _header()),
                  if (_tab == 0 || _tab == 1)
                    ..._catalogSlivers()
                  else
                    SliverToBoxAdapter(child: _tab == 2 ? _reports() : _more()),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_units > 0) _cartBar(),
          DecoratedBox(
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Volt.line))),
            child: NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (index) => setState(() {
                _tab = index;
                _search.clear();
                _category = null;
              }),
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: 'Home'),
                NavigationDestination(
                    icon: Icon(Icons.inventory_2_outlined), label: 'Inventory'),
                NavigationDestination(
                    icon: Icon(Icons.bar_chart_rounded), label: 'Reports'),
                NavigationDestination(
                    icon: Icon(Icons.more_horiz), label: 'More'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                        fit: BoxFit.scaleDown, child: FastPasBrand()))),
            IconButton(
                tooltip: 'Your store',
                onPressed: () => setState(() => _tab = 3),
                icon: const Icon(Icons.storefront_outlined)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: MenuAnchor(
              menuChildren: [
                for (final branch in _branches)
                  MenuItemButton(
                    onPressed: _loading ? null : () => _selectBranch(branch),
                    leadingIcon: Icon(branch.id == _branch?.id
                        ? Icons.check
                        : Icons.storefront_outlined),
                    child: Text(branch.name),
                  )
              ],
              builder: (context, controller, child) => OutlinedButton.icon(
                onPressed: _branches.length < 2 || _loading
                    ? null
                    : () => controller.isOpen
                        ? controller.close()
                        : controller.open(),
                icon: const Icon(Icons.storefront_outlined, size: 18),
                label: Text(
                    _branch?.name ??
                        (_loading ? 'Loading branch…' : 'No branch'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                style: OutlinedButton.styleFrom(
                    foregroundColor: Volt.ink,
                    disabledForegroundColor: Volt.ink,
                    side: const BorderSide(color: Volt.line),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10)),
              ),
            )),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                  color: Volt.soft, borderRadius: BorderRadius.circular(30)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.circle, color: Volt.ink, size: 7),
                const SizedBox(width: 7),
                Text(_source.isPreview ? 'Sample data' : widget.role,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            ),
          ]),
        ]),
      );

  List<Widget> _catalogSlivers() {
    final items = _filtered;
    final categories = _products.map((p) => p.category).toSet().toList()
      ..sort();
    return [
      SliverToBoxAdapter(
          child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: TextField(
              key: const ValueKey('product-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                hintText: 'Search products or SKU',
                prefixIcon: const Icon(Icons.search, color: Volt.ink),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () => setState(() => _search.clear()),
                        icon: const Icon(Icons.close)),
              ),
            )),
            const SizedBox(width: 10),
            const Tooltip(
                message: 'Barcode scanning is planned',
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton.outlined(
                      onPressed: null, icon: Icon(Icons.qr_code_scanner)),
                )),
          ]),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _categoryChip('All', null),
              for (final category in categories)
                _categoryChip(category, category),
            ]),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: Text(_tab == 0 ? 'Products' : 'Inventory',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.7))),
            const SizedBox(width: 10),
            Text('${items.length} items',
                style: const TextStyle(color: Volt.muted, fontSize: 13)),
            IconButton(
                tooltip:
                    _sortByPrice ? 'Sort by catalog order' : 'Sort by price',
                onPressed: () => setState(() => _sortByPrice = !_sortByPrice),
                icon: Icon(
                    _sortByPrice ? Icons.price_change_outlined : Icons.sort)),
          ]),
          if (_tab == 1 && isStoreManager(widget.role))
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 10),
              child: OutlinedButton.icon(
                  onPressed: () => _open(() => InventoryPage(
                      fullName: widget.fullName,
                      role: widget.role,
                      userId: widget.userId,
                      location: _location)),
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('Manage stock & branches')),
            ),
        ]),
      )),
      if (_loading)
        const SliverToBoxAdapter(
            child: Padding(
                padding: EdgeInsets.all(64),
                child: Center(child: CircularProgressIndicator())))
      else if (_error)
        SliverToBoxAdapter(
            child: _empty(
                Icons.cloud_off_outlined,
                'Couldn’t load your catalog',
                'Check your connection and branch assignment, then try again.',
                action: TextButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'))))
      else if (items.isEmpty)
        SliverToBoxAdapter(
            child: _empty(
                Icons.search_off,
                _products.isEmpty
                    ? 'No products in this branch'
                    : 'No matching products',
                _products.isEmpty
                    ? 'Products will appear here once stock is assigned to this branch.'
                    : 'Try another name, SKU, or category.',
                action: _products.isEmpty
                    ? null
                    : TextButton(
                        onPressed: () => setState(() {
                              _search.clear();
                              _category = null;
                            }),
                        child: const Text('Clear filters'))))
      else if (_tab == 1)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          sliver: SliverList.builder(
              itemCount: items.length,
              itemBuilder: (context, index) => _stockRow(items[index])),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          sliver: SliverLayoutBuilder(builder: (context, constraints) {
            final columns = constraints.crossAxisExtent >= 950
                ? 4
                : constraints.crossAxisExtent >= 650
                    ? 3
                    : 2;
            final scale = MediaQuery.textScalerOf(context).scale(1);
            return SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: 216 + (scale - 1).clamp(0, 2) * 105),
              itemCount: items.length,
              itemBuilder: (context, index) => _productCard(items[index]),
            );
          }),
        ),
    ];
  }

  Widget _categoryChip(String label, String? value) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: _category == value,
          onSelected: (_) => setState(() => _category = value),
          selectedColor: Volt.ink,
          backgroundColor: Colors.white,
          showCheckmark: false,
          labelStyle: TextStyle(
              color: _category == value ? Volt.lime : Volt.ink,
              fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          side: BorderSide(color: _category == value ? Volt.ink : Volt.line),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );

  Widget _productCard(CatalogProduct product) {
    final qty = _cart[product.id] ?? 0;
    return Card(
        child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
              color: Volt.soft, borderRadius: BorderRadius.circular(12)),
          child: Stack(children: [
            Center(
                child: Icon(product.icon,
                    size: 43,
                    color: product.stock == 0 ? Volt.muted : Volt.ink)),
            if (qty > 0)
              Positioned(
                  top: 7,
                  right: 7,
                  child: CircleAvatar(
                      radius: 12,
                      backgroundColor: Volt.lime,
                      foregroundColor: Volt.ink,
                      child: Text('$qty',
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700)))),
          ]),
        )),
        const SizedBox(height: 10),
        Text(product.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, height: 1.2)),
        const SizedBox(height: 4),
        FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(pesos(product.price),
                style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.5))),
        const SizedBox(height: 3),
        Row(children: [
          Expanded(
              child: Text(
                  product.stock == 0
                      ? 'Out of stock'
                      : '${product.stock} in stock',
                  style: TextStyle(
                      fontSize: 11,
                      color: product.stock <= 5
                          ? const Color(0xFF8E570D)
                          : Volt.muted))),
          if (qty == 0)
            SizedBox(
                width: 44,
                height: 44,
                child: IconButton.filled(
                  key: ValueKey('add-${product.id}'),
                  tooltip: 'Add ${product.name}',
                  onPressed: product.stock <= 0
                      ? null
                      : () => _changeQuantity(product, 1),
                  style: IconButton.styleFrom(
                      backgroundColor: Volt.ink, foregroundColor: Volt.lime),
                  icon: const Icon(Icons.add),
                )),
        ]),
        if (qty > 0)
          Container(
            decoration: BoxDecoration(
                color: Volt.soft, borderRadius: BorderRadius.circular(24)),
            child: Row(children: [
              Expanded(
                  child: IconButton(
                      key: ValueKey('remove-${product.id}'),
                      tooltip: 'Remove one ${product.name}',
                      onPressed: () => _changeQuantity(product, -1),
                      icon: const Icon(Icons.remove, size: 20))),
              Text('$qty', style: const TextStyle(fontWeight: FontWeight.w700)),
              Expanded(
                  child: IconButton(
                      key: ValueKey('add-${product.id}'),
                      tooltip: 'Add ${product.name}',
                      onPressed: qty >= product.stock
                          ? null
                          : () => _changeQuantity(product, 1),
                      icon: const Icon(Icons.add, size: 20))),
            ]),
          ),
      ]),
    ));
  }

  Widget _stockRow(CatalogProduct product) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Card(
            child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Icon(product.icon, color: Volt.ink),
          title: Text(product.name,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${product.sku} · ${product.category}'),
          trailing: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${product.stock}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 20)),
                Text(
                    product.stock == 0
                        ? 'Sold out'
                        : product.stock <= 5
                            ? 'Low stock'
                            : 'In stock',
                    style: const TextStyle(fontSize: 10, color: Volt.muted)),
              ])),
        )),
      );

  Widget _cartBar() => Container(
        color: Volt.ink,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: SafeArea(
            top: false,
            bottom: false,
            child: Row(children: [
              Badge(
                  label: Text('$_units'),
                  backgroundColor: Volt.lime,
                  textColor: Volt.ink,
                  child: const Icon(Icons.shopping_cart_outlined,
                      color: Colors.white, size: 27)),
              const SizedBox(width: 20),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('$_units ${_units == 1 ? 'item' : 'items'} · subtotal',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11)),
                    FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(pesos(_subtotal),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 23))),
                  ])),
              const SizedBox(width: 12),
              FilledButton(
                  onPressed: _loading || _error ? null : _checkout,
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('Checkout'),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward, size: 18)
                  ])),
            ])),
      );

  Widget _empty(IconData icon, String title, String description,
          {Widget? action}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(children: [
          Icon(icon, size: 40, color: Volt.muted),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(description,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Volt.muted)),
          if (action != null)
            Padding(padding: const EdgeInsets.only(top: 12), child: action),
        ]),
      );

  Widget _section(String title, String description, List<Widget> children) =>
      Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.7)),
          const SizedBox(height: 6),
          Text(description, style: const TextStyle(color: Volt.muted)),
          const SizedBox(height: 24),
          ...children,
        ]),
      );

  Widget _menu(
          IconData icon, String title, String subtitle, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
            child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: CircleAvatar(
              backgroundColor: Volt.soft, child: Icon(icon, color: Volt.ink)),
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle,
              style: const TextStyle(fontSize: 12, color: Volt.muted)),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        )),
      );

  Widget _reports() =>
      _section('Reports', 'Keep track of your store’s performance.', [
        _menu(
            Icons.receipt_long_outlined,
            'Sales history',
            'Find past sales and receipts',
            () => _open(() => SalesHistoryPage(
                fullName: widget.fullName,
                role: widget.role,
                userId: widget.userId,
                location: _location))),
        if (isStoreManager(widget.role)) ...[
          _menu(
              Icons.bar_chart,
              'Sales reports',
              'View trends and export reports',
              () => _open(() => ViewReportsPage(
                  fullName: widget.fullName,
                  role: widget.role,
                  userId: widget.userId,
                  location: _location))),
          _menu(
              Icons.dashboard_outlined,
              'Store overview',
              'Sales totals, top products, and attendance',
              () => _open(() => HomeScreen(
                  fullName: widget.fullName,
                  role: widget.role,
                  userId: widget.userId,
                  location: _location))),
        ],
      ]);

  Widget _more() =>
      _section('Your store', '${widget.fullName} · ${widget.role}', [
        if (isStoreManager(widget.role)) ...[
          _menu(
              Icons.people_outline,
              'Staff',
              'Manage your store team',
              () => _open(() => UsersPage(
                  fullName: widget.fullName,
                  role: widget.role,
                  userId: widget.userId,
                  location: _location))),
          _menu(
              Icons.local_shipping_outlined,
              'Suppliers',
              'Your supplier contacts and products',
              () => _open(() => SuppliersScreen(
                  fullName: widget.fullName,
                  role: widget.role,
                  userId: widget.userId))),
          _menu(
              Icons.storefront_outlined,
              'Branches & stock',
              'Manage existing branches and inventory',
              () => _open(() => InventoryPage(
                  fullName: widget.fullName,
                  role: widget.role,
                  userId: widget.userId,
                  location: _location))),
        ],
        _menu(
            Icons.person_outline,
            'My profile & attendance',
            'Profile details and attendance records',
            () => _open(() => UserProfileScreen(
                fullName: widget.fullName,
                role: widget.role,
                userId: widget.userId))),
        if (!_source.isPreview)
          _menu(Icons.logout, 'Sign out', 'Return to the sign-in screen',
              () async {
            if (_cart.isNotEmpty) {
              final leave = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                        title: const Text('Sign out with items in your cart?'),
                        content: const Text('Your cart will be cleared.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Stay')),
                          FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Sign out'))
                        ],
                      ));
              if (leave != true || !mounted) return;
            }
            await Supabase.instance.client.auth.signOut();
            if (!mounted) return;
            Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => LoginScreen()), (_) => false);
          }),
        const SizedBox(height: 12),
        const Text('FastPas POS · Graphite Volt',
            style: TextStyle(fontSize: 12, color: Volt.muted)),
      ]);
}
