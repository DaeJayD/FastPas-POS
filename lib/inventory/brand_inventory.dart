import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vasenizzpos/inventory/add_new_item.dart';

class BrandInventoryPage extends StatefulWidget {
  final String brandName;
  final String fullName;
  final String role;
  final String branchManager;
  final String branchCode;
  final String branchName;
  final String? brandId;
  final String userId;

  const BrandInventoryPage({
    super.key,
    required this.brandName,
    required this.fullName,
    required this.role,
    required this.branchManager,
    required this.branchCode,
    required this.branchName,
    required this.userId,
    this.brandId,
  });

  @override
  State<BrandInventoryPage> createState() => _BrandInventoryPageState();
}

class _BrandInventoryPageState extends State<BrandInventoryPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool removeMode = false;
  bool _isLoading = true;
  List<dynamic> _products = [];
  String? _brandId;
  String? _branchId;
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _filteredProducts = [];

  // Filter and Sort variables
  String _selectedFilter = 'All';
  String _selectedSort = 'Name A-Z';
  String _selectedCategory = 'All Categories';
  List<String> _filterOptions = ['All', 'Low Stock', 'Out of Stock'];
  final List<String> _sortOptions = ['Name A-Z', 'Name Z-A', 'Price Low-High', 'Price High-Low', 'Stock Low-High'];
  List<String> _categoryOptions = ['All Categories'];

  @override
  void initState() {
    super.initState();
    _initializeData();
    _searchController.addListener(_filterProducts);
  }

  Future<void> _initializeData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Use provided brandId if available, otherwise query by name
      if (widget.brandId != null) {
        _brandId = widget.brandId;
      } else {
        final brandResult = await _supabase
            .from('brands')
            .select('id')
            .eq('name', widget.brandName)
            .single();
        _brandId = brandResult['id'];
      }

      // Get branch ID
      final branchResult = await _supabase
          .from('branches')
          .select('id')
          .eq('name', widget.branchName)
          .single();
      _branchId = branchResult['id'];

      await _loadProducts();
      await _loadCategories();
    } catch (e) {
      print('Error initializing data: $e');
      _showErrorSnackbar('Failed to load inventory data');
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadProducts() async {
    try {
      // Load products for this brand in the specific branch
      final result = await _supabase
          .from('products')
          .select('''
            *,
            categories(name),
            branch_stock!inner(
              current_stock,
              low_stock_threshold
            )
          ''')
          .eq('brand_id', _brandId!)
          .eq('branch_stock.branch_id', _branchId!)
          .order('name');

      setState(() {
        _products = result;
        _applyFilterAndSort();
      });
    } catch (e) {
      print('Error loading products: $e');
      _showErrorSnackbar('Failed to load products');
    }
  }

  Future<void> _loadCategories() async {
    try {
      // Load unique categories for this brand
      final result = await _supabase
          .from('products')
          .select('categories(name)')
          .eq('brand_id', _brandId!);

      // Extract unique category names
      final categoryNames = result
          .map((item) => item['categories']?['name']?.toString())
          .where((name) => name != null && name.isNotEmpty)
          .toSet()
          .toList();

      setState(() {
        _categoryOptions = ['All Categories']..addAll(categoryNames.cast<String>());
      });
    } catch (e) {
      print('Error loading categories: $e');
    }
  }

  void _filterProducts() {
    _applyFilterAndSort();
  }

  void _applyFilterAndSort() {
    String query = _searchController.text.toLowerCase();

    // Apply search filter
    List<dynamic> filtered = _products.where((product) {
      final productName = product['name']?.toString().toLowerCase() ?? '';
      final productSku = product['sku']?.toString().toLowerCase() ?? '';
      final categoryName = product['categories']?['name']?.toString().toLowerCase() ?? '';
      return productName.contains(query) ||
          productSku.contains(query) ||
          categoryName.contains(query);
    }).toList();

    // Apply category filter
    if (_selectedCategory != 'All Categories') {
      filtered = filtered.where((product) {
        final categoryName = product['categories']?['name']?.toString() ?? '';
        return categoryName == _selectedCategory;
      }).toList();
    }

    // Apply stock filter
    if (_selectedFilter == 'Low Stock') {
      filtered = filtered.where((product) {
        final currentStock = product['branch_stock'][0]['current_stock'] ?? 0;
        final lowStockThreshold = product['branch_stock'][0]['low_stock_threshold'] ?? 10;
        return currentStock > 0 && currentStock <= lowStockThreshold;
      }).toList();
    } else if (_selectedFilter == 'Out of Stock') {
      filtered = filtered.where((product) {
        final currentStock = product['branch_stock'][0]['current_stock'] ?? 0;
        return currentStock == 0;
      }).toList();
    }

    // Apply sorting
    filtered.sort((a, b) {
      switch (_selectedSort) {
        case 'Name Z-A':
          return (b['name'] ?? '').compareTo(a['name'] ?? '');
        case 'Price Low-High':
          return ((a['price'] ?? 0) as num).compareTo((b['price'] ?? 0) as num);
        case 'Price High-Low':
          return ((b['price'] ?? 0) as num).compareTo((a['price'] ?? 0) as num);
        case 'Stock Low-High':
          final stockA = a['branch_stock'][0]['current_stock'] ?? 0;
          final stockB = b['branch_stock'][0]['current_stock'] ?? 0;
          return stockA.compareTo(stockB);
        default: // 'Name A-Z'
          return (a['name'] ?? '').compareTo(b['name'] ?? '');
      }
    });

    setState(() {
      _filteredProducts = filtered;
    });
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Filter by Stock"),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _filterOptions.length,
              itemBuilder: (context, index) {
                final option = _filterOptions[index];
                return RadioListTile<String>(
                  title: Text(option),
                  value: option,
                  groupValue: _selectedFilter,
                  onChanged: (value) {
                    setState(() {
                      _selectedFilter = value!;
                    });
                    Navigator.pop(context);
                    _applyFilterAndSort();
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showCategoryDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Filter by Category"),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _categoryOptions.length,
              itemBuilder: (context, index) {
                final option = _categoryOptions[index];
                return RadioListTile<String>(
                  title: Text(option),
                  value: option,
                  groupValue: _selectedCategory,
                  onChanged: (value) {
                    setState(() {
                      _selectedCategory = value!;
                    });
                    Navigator.pop(context);
                    _applyFilterAndSort();
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showSortDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Sort Products"),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _sortOptions.length,
              itemBuilder: (context, index) {
                final option = _sortOptions[index];
                return RadioListTile<String>(
                  title: Text(option),
                  value: option,
                  groupValue: _selectedSort,
                  onChanged: (value) {
                    setState(() {
                      _selectedSort = value!;
                    });
                    Navigator.pop(context);
                    _applyFilterAndSort();
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showProductDetails(dynamic product) {
    final branchStock = product['branch_stock'][0];
    final currentStock = branchStock['current_stock'] ?? 0;
    final lowStockThreshold = branchStock['low_stock_threshold'] ?? 10;
    final isOutOfStock = currentStock == 0;
    final isLowStock = currentStock > 0 && currentStock <= lowStockThreshold;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(product['name'] ?? 'Product Details'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (product['sku'] != null) ...[
                Text(
                  'SKU: ${product['sku']}',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                'Category: ${product['categories']?['name'] ?? '—'}',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 8),
              Text(
                'Price: ₱${(product['price'] ?? 0).toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    'Stock: $currentStock',
                    style: TextStyle(
                      fontSize: 14,
                      color: isOutOfStock ? Colors.red : (isLowStock ? Colors.orange : Colors.green),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isOutOfStock)
                    const Icon(Icons.error_outline, color: Colors.red, size: 16)
                  else if (isLowStock)
                    const Icon(Icons.warning_amber, color: Colors.orange, size: 16),
                ],
              ),
              if (isLowStock) ...[
                const SizedBox(height: 4),
                Text(
                  'Low stock threshold: $lowStockThreshold',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Close"),
            ),
          ],
        );
      },
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showRemoveDialog(int index) {
    final TextEditingController qtyController = TextEditingController();
    final product = _filteredProducts[index];
    final currentStock = product['branch_stock'][0]['current_stock'] ?? 0;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Remove from ${product['name']}"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Available stock: $currentStock"),
              const SizedBox(height: 10),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Quantity to remove",
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                final int removeQty = int.tryParse(qtyController.text) ?? 0;
                if (removeQty > 0 && removeQty <= currentStock) {
                  try {
                    // Update stock in database
                    await _supabase
                        .from('branch_stock')
                        .update({
                      'current_stock': currentStock - removeQty,
                      'last_updated': DateTime.now().toIso8601String(),
                    })
                        .eq('product_id', product['id'])
                        .eq('branch_id', _branchId!);

                    // Record inventory movement
                    await _supabase
                        .from('inventory_movements')
                        .insert({
                      'product_id': product['id'],
                      'branch_id': _branchId!,
                      'movement_type': 'out',
                      'quantity': removeQty,
                      'previous_stock': currentStock,
                      'new_stock': currentStock - removeQty,
                      'username': widget.fullName,
                      'user_id': widget.userId,
                      'reason': 'Manual stock adjustment',
                    });

                    await _loadProducts(); // Refresh data
                    Navigator.pop(context);

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Removed $removeQty from ${product['name']}'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error updating stock: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Invalid quantity entered")),
                  );
                }
              },
              child: const Text("Confirm"),
            ),
          ],
        );
      },
    );
  }

  void _showAddStockDialog(int index) {
    final TextEditingController qtyController = TextEditingController();
    final product = _filteredProducts[index];
    final currentStock = product['branch_stock'][0]['current_stock'] ?? 0;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Add Stock to ${product['name']}"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Current stock: $currentStock"),
              const SizedBox(height: 10),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Quantity to add",
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () async {
                final int addQty = int.tryParse(qtyController.text) ?? 0;
                if (addQty > 0) {
                  try {
                    // Update stock in database
                    await _supabase
                        .from('branch_stock')
                        .update({
                      'current_stock': currentStock + addQty,
                      'last_updated': DateTime.now().toIso8601String(),
                    })
                        .eq('product_id', product['id'])
                        .eq('branch_id', _branchId!);

                    // Record inventory movement
                    await _supabase
                        .from('inventory_movements')
                        .insert({
                      'product_id': product['id'],
                      'branch_id': _branchId!,
                      'movement_type': 'in',
                      'quantity': addQty,
                      'previous_stock': currentStock,
                      'new_stock': currentStock + addQty,
                      'user_id': widget.userId,
                      'username': widget.fullName,
                      'reason': 'Manual stock adjustment',
                    });

                    await _loadProducts(); // Refresh data
                    Navigator.pop(context);

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Added $addQty to ${product['name']}'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error updating stock: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please enter a valid quantity")),
                  );
                }
              },
              child: const Text("Add Stock"),
            ),
          ],
        );
      },
    );
  }

  Widget _tableRow(dynamic product, int index) {
    final branchStock = product['branch_stock'][0];
    final currentStock = branchStock['current_stock'] ?? 0;
    final lowStockThreshold = branchStock['low_stock_threshold'] ?? 10;
    final isOutOfStock = currentStock == 0;
    final isLowStock = currentStock > 0 && currentStock <= lowStockThreshold;

    return InkWell(
      onTap: () => _showProductDetails(product),
      child: Container(
        color: isOutOfStock ? Colors.red[50] : (isLowStock ? Colors.orange[50] : (index % 2 == 0 ? Colors.pink[50] : Colors.white)),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product['name'] ?? 'Unknown',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (product['sku'] != null)
                      Text(
                        product['sku'],
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _TableCell(product['categories']?['name'] ?? '—'),
            ),
            Expanded(
              child: _TableCell('₱${(product['price'] ?? 0).toStringAsFixed(2)}'),
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    currentStock.toString(),
                    style: TextStyle(
                      fontSize: 12,
                      color: isOutOfStock ? Colors.red : (isLowStock ? Colors.orange : Colors.black87),
                      fontWeight: (isOutOfStock || isLowStock) ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  if (isOutOfStock) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.error_outline, color: Colors.red, size: 14),
                  ] else if (isLowStock) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.warning_amber, color: Colors.orange, size: 14),
                  ],
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: IconButton(
                  icon: Icon(
                    removeMode ? Icons.delete_outline : Icons.add_circle_outline,
                    color: removeMode ? Colors.redAccent : Colors.green,
                    size: 20,
                  ),
                  onPressed: () {
                    if (removeMode) {
                      _showRemoveDialog(index);
                    } else {
                      _showAddStockDialog(index);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8EDF3),
      appBar: AppBar(
        backgroundColor: Colors.orangeAccent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            const CircleAvatar(
              radius: 20,
              backgroundColor: Colors.white,
              child: Icon(Icons.business, color: Colors.orangeAccent, size: 20),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.brandName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    "${widget.branchManager} (${widget.branchCode}) - ${widget.branchName}",
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                _smallButton(
                  "Refresh",
                  Colors.white,
                  Colors.orangeAccent,
                  _loadProducts,
                ),
                const SizedBox(width: 6),
                _smallButton(
                  removeMode ? "Done" : "Remove Stock",
                  Colors.white,
                  Colors.redAccent,
                      () {
                    setState(() {
                      removeMode = !removeMode;
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orangeAccent))
          : Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Search and filter bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.black26),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      "${_filteredProducts.length} Products",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: "Search products...",
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 8),
                        hintStyle: TextStyle(fontSize: 12),
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _actionButton("Category", _showCategoryDialog),
                  const SizedBox(width: 6),
                  _actionButton("Filter", _showFilterDialog),
                  const SizedBox(width: 6),
                  _actionButton("Sort", _showSortDialog),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Active filters display
            if (_selectedCategory != 'All Categories' || _selectedFilter != 'All')
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    if (_selectedCategory != 'All Categories')
                      _filterChip(
                        'Category: $_selectedCategory',
                        onRemove: () {
                          setState(() {
                            _selectedCategory = 'All Categories';
                            _applyFilterAndSort();
                          });
                        },
                      ),
                    if (_selectedFilter != 'All')
                      _filterChip(
                        'Stock: $_selectedFilter',
                        onRemove: () {
                          setState(() {
                            _selectedFilter = 'All';
                            _applyFilterAndSort();
                          });
                        },
                      ),
                  ],
                ),
              ),
            _smallButton(
              "Add Item",
              Colors.white,
              Colors.green,
                  () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AddNewItemPage(
                      brandId: _brandId,
                      branchId: _branchId,
                      brandName: widget.brandName,
                      branchName: widget.branchName,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),

            // Products table
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black26),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    // Table header
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.pink[50],
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          topRight: Radius.circular(8),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: _TableHeaderCell("Product"),
                          ),
                          Expanded(
                            child: _TableHeaderCell("Category"),
                          ),
                          Expanded(
                            child: _TableHeaderCell("Price"),
                          ),
                          Expanded(
                            child: _TableHeaderCell("Stock"),
                          ),
                          Expanded(
                            child: _TableHeaderCell("Action"),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Colors.black26, thickness: 1),

                    // Products list
                    Expanded(
                      child: _filteredProducts.isEmpty
                          ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey),
                            const SizedBox(height: 12),
                            const Text(
                              'No products found',
                              style: TextStyle(fontSize: 14),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'in ${widget.branchName}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            if (_searchController.text.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Search: "${_searchController.text}"',
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ],
                        ),
                      )
                          : ListView.builder(
                        itemCount: _filteredProducts.length,
                        itemBuilder: (context, index) =>
                            _tableRow(_filteredProducts[index], index),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _smallButton(
      String text, Color bg, Color borderColor, VoidCallback onPressed) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: borderColor,
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Widget _actionButton(String text, VoidCallback onPressed) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        minimumSize: Size.zero,
      ),
      onPressed: onPressed,
      child: Text(
        text,
        style: const TextStyle(fontSize: 11),
      ),
    );
  }

  Widget _filterChip(String label, {required VoidCallback onRemove}) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      child: Chip(
        label: Text(
          label,
          style: const TextStyle(fontSize: 10),
        ),
        onDeleted: onRemove,
        deleteIcon: const Icon(Icons.close, size: 14),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

class _TableHeaderCell extends StatelessWidget {
  final String text;
  const _TableHeaderCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        color: Colors.black87,
        fontSize: 12,
      ),
    );
  }
}

class _TableCell extends StatelessWidget {
  final String text;
  final Color textColor;
  final bool isBold;

  const _TableCell(this.text, {this.textColor = Colors.black87, this.isBold = false});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: textColor,
        fontSize: 11,
        fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
      ),
      overflow: TextOverflow.ellipsis,
    );
  }
}