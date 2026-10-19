import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AllProductsInventoryScreen extends StatefulWidget {
  final String fullName;
  final String role;

  const AllProductsInventoryScreen({
    Key? key,
    required this.fullName,
    required this.role,
  }) : super(key: key);

  @override
  State<AllProductsInventoryScreen> createState() => _AllProductsInventoryScreenState();
}

class _AllProductsInventoryScreenState extends State<AllProductsInventoryScreen> {
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _filteredProducts = [];
  List<Map<String, dynamic>> _brands = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  bool _hasError = false;
  int _currentPage = 0;
  final int _pageSize = 20;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  String _sortBy = 'name'; // 'name', 'stock', 'sku'
  String? _selectedBrandId;
  String _viewMode = 'all'; // 'all', 'byBrand'
  Map<String, List<Map<String, dynamic>>> _productsByBrand = {};

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _searchController.addListener(_filterProducts);
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      await Future.wait([
        _loadBrands(),
        _loadProducts(),
      ]);
    } catch (e) {
      print('Error loading initial data: $e');
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  Future<void> _loadBrands() async {
    try {
      final response = await Supabase.instance.client
          .from('brands')
          .select('*')
          .order('name');

      setState(() {
        _brands = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      print('Error loading brands: $e');
    }
  }

  Future<void> _loadProducts({bool loadMore = false}) async {
    if (_isLoadingMore) return;

    try {
      if (!loadMore) {
        setState(() {
          _isLoading = true;
          _hasError = false;
          _currentPage = 0;
        });
      } else {
        setState(() {
          _isLoadingMore = true;
        });
      }

      final from = _currentPage * _pageSize;
      final to = from + _pageSize - 1;

      // Build query with brand and category information
      var query = Supabase.instance.client
          .from('products')
          .select('''
          *,
          brands:brand_id(*),
          categories:category_id(*),
          branch_stock(
            current_stock,
            branches:branch_id(*)
          )
        ''');

      // Apply brand filter if selected - using correct Postgrest syntax
      if (_selectedBrandId != null) {
        query = query.eq('brand_id', _selectedBrandId!);
      }

      // Add ordering and range
      final response = await query
          .order('name')
          .range(from, to);

      List<Map<String, dynamic>> products = List<Map<String, dynamic>>.from(response);

      // Process products to calculate branch stock
      for (var product in products) {
        product['total_stock'] = _calculateTotalStock(product);
        product['branch_stock_map'] = _createBranchStockMap(product);
      }

      // Apply sorting
      if (_sortBy == 'name') {
        products.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
      } else if (_sortBy == 'sku') {
        products.sort((a, b) => (a['sku'] ?? '').compareTo(b['sku'] ?? ''));
      } else if (_sortBy == 'stock') {
        products.sort((a, b) {
          final totalStockA = a['total_stock'] ?? 0;
          final totalStockB = b['total_stock'] ?? 0;
          return totalStockB.compareTo(totalStockA);
        });
      }

      setState(() {
        if (loadMore) {
          _products.addAll(products);
        } else {
          _products = products;
        }

        _organizeProductsByBrand();
        _filteredProducts = _products;
        _hasMore = response.length == _pageSize;
        _isLoading = false;
        _isLoadingMore = false;
        if (loadMore) _currentPage++;
      });
    } catch (e) {
      print('Error loading products: $e');
      setState(() {
        _isLoading = false;
        _hasError = true;
        _isLoadingMore = false;
      });
    }
  }

  void _organizeProductsByBrand() {
    _productsByBrand.clear();

    // Group products by brand
    for (var product in _products) {
      final brand = product['brands'];
      if (brand != null) {
        final brandId = brand['id'] as String;
        if (!_productsByBrand.containsKey(brandId)) {
          _productsByBrand[brandId] = [];
        }
        _productsByBrand[brandId]!.add(product);
      } else {
        // Products without brand
        if (!_productsByBrand.containsKey('no_brand')) {
          _productsByBrand['no_brand'] = [];
        }
        _productsByBrand['no_brand']!.add(product);
      }
    }
  }

  int _calculateTotalStock(Map<String, dynamic> product) {
    final branchStock = product['branch_stock'] as List?;
    if (branchStock == null) return 0;

    int total = 0;
    for (var stock in branchStock) {
      total += (stock['current_stock'] as int? ?? 0);
    }
    return total;
  }

  Map<String, int> _createBranchStockMap(Map<String, dynamic> product) {
    final branchStock = product['branch_stock'] as List?;
    final stockMap = <String, int>{};

    if (branchStock != null) {
      for (var stock in branchStock) {
        final branch = stock['branches'];
        if (branch != null) {
          stockMap[branch['name'] as String] = stock['current_stock'] ?? 0;
        }
      }
    }

    // Ensure all branches are represented
    stockMap['JASAAN BRANCH'] ??= 0;
    stockMap['PUERTO BRANCH'] ??= 0;
    stockMap['CARMEN BRANCH'] ??= 0;

    return stockMap;
  }

  void _filterProducts() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredProducts = _products;
      } else {
        _filteredProducts = _products.where((product) {
          final productName = product['name']?.toString().toLowerCase() ?? '';
          final productSku = product['sku']?.toString().toLowerCase() ?? '';
          final brandName = product['brands']?['name']?.toString().toLowerCase() ?? '';
          final categoryName = product['categories']?['name']?.toString().toLowerCase() ?? '';

          return productName.contains(query) ||
              productSku.contains(query) ||
              brandName.contains(query) ||
              categoryName.contains(query);
        }).toList();
      }
      _organizeProductsByBrand();
    });
  }

  void _changeSort(String newSort) {
    setState(() {
      _sortBy = newSort;
      _currentPage = 0;
    });
    _loadProducts();
  }

  void _changeBrandFilter(String? brandId) {
    setState(() {
      _selectedBrandId = brandId;
      _currentPage = 0;
    });
    _loadProducts();
  }

  void _toggleViewMode() {
    setState(() {
      _viewMode = _viewMode == 'all' ? 'byBrand' : 'all';
    });
  }

  void _loadNextPage() {
    if (_hasMore && !_isLoadingMore) {
      _loadProducts(loadMore: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8EDF3),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5C6D3),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            const CircleAvatar(
              radius: 20,
              backgroundImage: AssetImage("assets/logo.png"),
              backgroundColor: Colors.white,
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "All Products Inventory",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  "${widget.fullName} (${widget.role})",
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _viewMode == 'all' ? Icons.view_list : Icons.category,
              color: Colors.white,
            ),
            onPressed: _toggleViewMode,
            tooltip: _viewMode == 'all' ? 'Group by Brand' : 'Show All Products',
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded, color: Colors.white),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadInitialData,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search, Filter, and Sort Controls
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Search Bar
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: "Search products by name, SKU, brand, or category",
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),

                // Filter and Sort Row
                Row(
                  children: [
                    // Brand Filter Dropdown
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            value: _selectedBrandId,
                            isExpanded: true,
                            icon: const Icon(Icons.filter_list, size: 18),
                            hint: const Text('All Brands', style: TextStyle(fontSize: 14)),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('All Brands', style: TextStyle(fontSize: 14)),
                              ),
                              ..._brands.map<DropdownMenuItem<String?>>((brand) {
                                return DropdownMenuItem<String?>(
                                  value: brand['id'] as String?,
                                  child: Text(
                                    brand['name'] as String,
                                    style: const TextStyle(fontSize: 14),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                            ],
                            onChanged: _changeBrandFilter,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Sort Dropdown
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _sortBy,
                            isExpanded: true,
                            icon: const Icon(Icons.sort, size: 18),
                            items: const [
                              DropdownMenuItem<String>(
                                value: 'name',
                                child: Text('Sort by Name', style: TextStyle(fontSize: 14)),
                              ),
                              DropdownMenuItem<String>(
                                value: 'sku',
                                child: Text('Sort by SKU', style: TextStyle(fontSize: 14)),
                              ),
                              DropdownMenuItem<String>(
                                value: 'stock',
                                child: Text('Sort by Stock', style: TextStyle(fontSize: 14)),
                              ),
                            ],
                            onChanged: (value) => _changeSort(value!),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Expanded(
            child: _buildProductDisplay(),
          ),
        ],
      ),
    );
  }

  Widget _buildProductDisplay() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.pink),
            SizedBox(height: 16),
            Text('Loading inventory...'),
          ],
        ),
      );
    }

    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text('Failed to load products'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadInitialData,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF5C6D3),
                foregroundColor: Colors.black87,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_filteredProducts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _searchController.text.isEmpty ? Icons.inventory_2_outlined : Icons.search_off,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isEmpty
                  ? 'No products available'
                  : 'No products found for "${_searchController.text}"',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return _viewMode == 'byBrand' ? _buildBrandGroupedView() : _buildAllProductsView();
  }

  Widget _buildBrandGroupedView() {
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification scrollInfo) {
        if (scrollInfo.metrics.pixels == scrollInfo.metrics.maxScrollExtent && _hasMore) {
          _loadNextPage();
        }
        return false;
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _productsByBrand.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _productsByBrand.length && _isLoadingMore) {
            return const Center(child: CircularProgressIndicator(color: Colors.pink));
          }

          final brandId = _productsByBrand.keys.elementAt(index);
          final brandProducts = _productsByBrand[brandId]!;
          final brand = brandId != 'no_brand'
              ? _brands.firstWhere((b) => b['id'] == brandId, orElse: () => {'name': 'Unknown Brand'})
              : {'name': 'No Brand'};

          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Brand Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5C6D3).withOpacity(0.3),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.branding_watermark, size: 20, color: Colors.pink),
                      const SizedBox(width: 8),
                      Text(
                        brand['name'] as String,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${brandProducts.length} product${brandProducts.length != 1 ? 's' : ''}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),

                // Products Grid
                GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: brandProducts.length,
                  itemBuilder: (context, productIndex) {
                    final product = brandProducts[productIndex];
                    return _buildProductCard(product);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAllProductsView() {
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification scrollInfo) {
        if (scrollInfo.metrics.pixels == scrollInfo.metrics.maxScrollExtent && _hasMore) {
          _loadNextPage();
        }
        return false;
      },
      child: Column(
        children: [
          // Results count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  '${_filteredProducts.length} product${_filteredProducts.length != 1 ? 's' : ''}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                if (_hasMore)
                  Text(
                    'Page ${_currentPage + 1}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Products Grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.75,
              ),
              itemCount: _filteredProducts.length + (_isLoadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _filteredProducts.length && _isLoadingMore) {
                  return const Center(child: CircularProgressIndicator(color: Colors.pink));
                }

                final product = _filteredProducts[index];
                return _buildProductCard(product);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final totalStock = product['total_stock'] ?? 0;
    final branchStockMap = product['branch_stock_map'] as Map<String, int>? ?? {};
    final jasaanStock = branchStockMap['JASAAN BRANCH'] ?? 0;
    final puertoStock = branchStockMap['PUERTO BRANCH'] ?? 0;
    final carmenStock = branchStockMap['CARMEN BRANCH'] ?? 0;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Name and SKU
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product['name'] ?? 'Unnamed Product',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  product['sku'] ?? 'No SKU',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),

            // Brand and Category
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (product['brands'] != null)
                  Text(
                    product['brands']['name'] as String,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.blue[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                if (product['categories'] != null)
                  Text(
                    product['categories']['name'] as String,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
              ],
            ),

            // Branch Stock Information
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStockRow('Jasaan:', jasaanStock),
                _buildStockRow('Puerto:', puertoStock),
                _buildStockRow('Carmen:', carmenStock),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: totalStock <= 30 ? Colors.orange.shade100 : Colors.green.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Total: $totalStock',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: totalStock <= 30 ? Colors.orange.shade800 : Colors.green.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStockRow(String branchName, int stock) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          branchName,
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
        Text(
          stock.toString(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: stock <= 10 ? Colors.red : Colors.black,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}