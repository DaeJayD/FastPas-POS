import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vasenizzpos/sales/checkout_page.dart';

class AllProductsPage extends StatefulWidget {
  final String fullName;
  final String role;
  final String userId;
  final String location;
  final List<Map<String, dynamic>>? existingCart;

  const AllProductsPage({
    Key? key,
    required this.fullName,
    required this.role,
    required this.userId,
    required this.location,
    this.existingCart,
  }) : super(key: key);

  @override
  State<AllProductsPage> createState() => _AllProductsPageState();
}

class _AllProductsPageState extends State<AllProductsPage> {
  final List<Map<String, dynamic>> cart = [];
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _filteredProducts = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  bool _hasError = false;
  int _currentPage = 0;
  final int _pageSize = 10;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  String _sortBy = 'name'; // 'name', 'stock'

  @override
  void initState() {
    super.initState();
    if (widget.existingCart != null) {
      cart.addAll(widget.existingCart!);
    }
    _loadProducts();
    _searchController.addListener(_filterProducts);
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

      // Get products with branch stock information
      final response = await Supabase.instance.client
          .from('branch_brands')
          .select('''
          brands:brand_id(
            id,
            name,
            description,
            products(
              id,
              name,
              price,
              categories(name),
              brands(name),
              branch_stock(
                current_stock
              )
            )
          )
        ''')
          .range(from, to);

      // Extract and flatten products from all brands
      List<Map<String, dynamic>> products = [];
      for (final branchBrand in response) {
        final brand = branchBrand['brands'];
        if (brand != null && brand['products'] != null) {
          final brandProducts = List<Map<String, dynamic>>.from(brand['products']);
          for (final product in brandProducts) {
            // Add stock from branch_stock or default to 0
            final branchStock = product['branch_stock'] as List?;
            final stock = branchStock != null && branchStock.isNotEmpty
                ? (branchStock[0]['current_stock'] ?? 0)
                : 0;

            products.add({
              ...product,
              'stock': stock,
            });
          }
        }
      }

      // Remove duplicates by product ID
      final uniqueProducts = <String, Map<String, dynamic>>{};
      for (final product in products) {
        final productId = product['id']?.toString();
        if (productId != null && !uniqueProducts.containsKey(productId)) {
          uniqueProducts[productId] = product;
        }
      }

      List<Map<String, dynamic>> finalProducts = uniqueProducts.values.toList();

      // Apply client-side sorting
      if (_sortBy == 'name') {
        finalProducts.sort((a, b) => (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? ''));
      } else if (_sortBy == 'stock') {
        finalProducts.sort((a, b) {
          final stockA = a['stock'] is int ? a['stock'] : int.tryParse(a['stock']?.toString() ?? '0') ?? 0;
          final stockB = b['stock'] is int ? b['stock'] : int.tryParse(b['stock']?.toString() ?? '0') ?? 0;
          return stockB.compareTo(stockA);
        });
      }

      setState(() {
        if (loadMore) {
          _products.addAll(finalProducts);
        } else {
          _products = finalProducts;
        }

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

  void _filterProducts() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredProducts = _products.where((product) {
        final productName = product['name']?.toString().toLowerCase() ?? '';
        final categoryName = product['categories']?['name']?.toString().toLowerCase() ?? '';
        final brandName = product['brands']?['name']?.toString().toLowerCase() ?? '';
        return productName.contains(query) ||
            categoryName.contains(query) ||
            brandName.contains(query);
      }).toList();
    });
  }

  void _changeSort(String newSort) {
    setState(() {
      _sortBy = newSort;
      _currentPage = 0;
    });
    _loadProducts();
  }

  void addToCart(Map<String, dynamic> product) {
    final productStock = product['stock'] is int ? product['stock'] : int.tryParse(product['stock']?.toString() ?? '0') ?? 0;

    if (productStock <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${product['name']} is out of stock')),
      );
      return;
    }

    final existingItem = cart.firstWhere(
          (item) => item['id'] == product['id'],
      orElse: () => {},
    );

    final currentCartQty = (existingItem['cart_quantity'] as int?) ?? 0;
    if (currentCartQty >= productStock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot add more than available stock')),
      );
      return;
    }

    setState(() {
      if (existingItem.isEmpty) {
        // Add new item to cart
        cart.add({
          ...product,
          'cart_quantity': 1,
        });
      } else {
        // Update existing item quantity
        final index = cart.indexWhere((item) => item['id'] == product['id']);
        cart[index]['cart_quantity'] = (cart[index]['cart_quantity'] as int) + 1;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${product['name']} added to cart')),
    );
  }

  void _loadNextPage() {
    if (_hasMore && !_isLoadingMore) {
      _loadProducts(loadMore: true);
    }
  }

  int get _totalCartItems {
    return cart.fold<int>(0, (sum, item) => sum + (item['cart_quantity'] as int));
  }

  void _goToCheckout() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CheckoutPage(
          userId: widget.userId,
          location: widget.location,
          cartItems: cart,
          fullName: widget.fullName,
          role: widget.role,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8EDF3),
      appBar: AppBar(
        backgroundColor: const Color(0xFF7FC8F8),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "All Products",
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart_outlined, color: Colors.white),
                onPressed: cart.isEmpty ? null : _goToCheckout,
              ),
              if (cart.isNotEmpty)
                Positioned(
                  right: 6,
                  top: 6,
                  child: CircleAvatar(
                    radius: 10,
                    backgroundColor: Colors.red,
                    child: Text(
                      _totalCartItems.toString(),
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadProducts,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search and Sort Controls
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                // Search Bar
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: "Search all products by name, SKU, category, or brand",
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),

                // Sort Dropdown
                Container(
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
                        DropdownMenuItem(
                          value: 'name',
                          child: Text('Sort by Name', style: TextStyle(fontSize: 14)),
                        ),
                        DropdownMenuItem(
                          value: 'stock',
                          child: Text('Sort by Stock', style: TextStyle(fontSize: 14)),
                        ),
                      ],
                      onChanged: (value) => _changeSort(value!),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: _buildProductGrid(),
          ),
        ],
      ),
    );
  }

  Widget _buildProductGrid() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading all products...'),
          ],
        ),
      );
    }

    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red),
            SizedBox(height: 16),
            Text('Failed to load products'),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadProducts,
              child: Text('Retry'),
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
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
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
                  '${_filteredProducts.length} product${_filteredProducts.length != 1 ? 's' : ''} found',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
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
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.85,
              ),
              itemCount: _filteredProducts.length + (_isLoadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _filteredProducts.length && _isLoadingMore) {
                  return Center(child: CircularProgressIndicator());
                }

                final product = _filteredProducts[index];
                final inCart = cart.any((item) => item['id'] == product['id']);
                final cartQuantity = inCart
                    ? (cart.firstWhere((item) => item['id'] == product['id'])['cart_quantity'] as int)
                    : 0;
                final productStock = product['stock'] is int ? product['stock'] : int.tryParse(product['stock']?.toString() ?? '0') ?? 0;

                return Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Product Image/Icon
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.shopping_bag,
                              size: 40,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),

                        // Product Name
                        Text(
                          product['name'] ?? 'Unnamed Product',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),

                        // Brand Name
                        if (product['brands'] != null)
                          Text(
                            product['brands']['name'],
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.blue[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),

                        // Category
                        if (product['categories'] != null)
                          Text(
                            product['categories']['name'],
                            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                          ),

                        // Price and Stock
                        Text(
                          '₱${(product['price'] ?? 0).toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green[700],
                          ),
                        ),

                        Text(
                          'Stock: $productStock',
                          style: TextStyle(
                            fontSize: 10,
                            color: productStock > 0 ? Colors.grey[600] : Colors.red,
                          ),
                        ),

                        // Add to Cart Button
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (inCart)
                              Text(
                                'In cart: $cartQuantity',
                                style: TextStyle(fontSize: 10, color: Colors.green),
                              ),
                            IconButton(
                              icon: Icon(
                                Icons.add_circle_outline,
                                color: productStock > 0 ? Colors.pink : Colors.grey,
                              ),
                              onPressed: productStock > 0
                                  ? () => addToCart(product)
                                  : null,
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
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}