import 'package:flutter/material.dart';
import 'package:vasenizzpos/sales/checkout_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BrandProductsPage extends StatefulWidget {
  final Map<String, dynamic> brand;
  final String fullName;
  final String role;
  final String userId;
  final String location;
  final List<Map<String, dynamic>>? existingCart;

  const BrandProductsPage({
    Key? key,
    required this.brand,
    required this.fullName,
    required this.role,
    required this.userId,
    required this.location,
    this.existingCart,
  }) : super(key: key);

  @override
  _BrandProductsPageState createState() => _BrandProductsPageState();
}

class _BrandProductsPageState extends State<BrandProductsPage> {
  final List<Map<String, dynamic>> cart = [];
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _filteredProducts = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  bool _hasError = false;
  int _currentPage = 0;
  final int _pageSize = 20;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
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

      // Use the same approach as AllProductsPage but filtered by brand_id
      final response = await Supabase.instance.client
          .from('products')
          .select('''
          id,
          name,
          price,
          sku,
          categories(name),
          brands!inner(id, name, description),
          branch_stock(
            current_stock,
            branches(name)
          )
        ''')
          .eq('brand_id', widget.brand['id']) // Filter by specific brand
          .order('name')
          .range(from, from + _pageSize - 1);

      print('Products response length: ${response.length}');

      List<Map<String, dynamic>> products = [];

      for (final product in response) {
        // Calculate total stock across all branches
        final branchStocks = product['branch_stock'] as List?;
        int totalStock = 0;
        List<String> branches = [];

        if (branchStocks != null && branchStocks.isNotEmpty) {
          for (final stock in branchStocks) {
            totalStock += (stock['current_stock'] as int? ?? 0);
            final branchName = stock['branches']?['name']?.toString();
            if (branchName != null) {
              branches.add(branchName);
            }
          }
        }

        products.add({
          ...product,
          'stock': totalStock,
          'branches': branches,
        });
      }

      setState(() {
        if (loadMore) {
          _products.addAll(products);
        } else {
          _products = products;
        }
        _filteredProducts = _products;
        _hasMore = response.length == _pageSize;
        _isLoading = false;
        _isLoadingMore = false;
        if (loadMore) _currentPage++;
      });

      print(' Loaded ${products.length} products for brand ${widget.brand['name']}');

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
      if (query.isEmpty) {
        _filteredProducts = _products;
      } else {
        _filteredProducts = _products.where((product) {
          final productName = product['name']?.toString().toLowerCase() ?? '';
          final categoryName = product['categories']?['name']?.toString().toLowerCase() ?? '';
          final brandName = product['brands']?['name']?.toString().toLowerCase() ?? '';

          return productName.contains(query) ||
              categoryName.contains(query) ||
              brandName.contains(query);
        }).toList();
      }
    });
  }

  void addToCart(Map<String, dynamic> product) {
    final productStock = product['stock'] is int ? product['stock'] : int.tryParse(product['stock']?.toString() ?? '0') ?? 0;

    if (productStock <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${product['name']} is out of stock'),
          backgroundColor: Colors.red,
        ),
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
        SnackBar(
          content: Text('Cannot add more than available stock ($productStock)'),
          backgroundColor: Colors.orange,
        ),
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
      SnackBar(
        content: Text('${product['name']} added to cart'),
        backgroundColor: Colors.green,
      ),
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

  String _getBrandInitial(String brandName) {
    if (brandName.isEmpty) return 'B';
    return brandName[0].toUpperCase();
  }

  Color _getBrandColor(String brandName) {
    final colors = [
      const Color(0xFF7FC8F8), // Blue
      const Color(0xFFF5C6D3), // Pink
      const Color(0xFFC6F5D3), // Green
      const Color(0xFFF5E6C6), // Yellow
      const Color(0xFFD3C6F5), // Purple
    ];
    final index = brandName.hashCode % colors.length;
    return colors[index];
  }


  void _goToCheckout() {
    if (cart.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CheckoutPage(
          cartItems: cart,
          fullName: widget.fullName,
          role: widget.role,
          userId: widget.userId,
          location: widget.location,
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
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: _getBrandColor(widget.brand['name']),
              radius: 20,
              child: Text(
                _getBrandInitial(widget.brand['name']),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.brand['name'],
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  ),
                  if (widget.brand['description'] != null)
                    Text(
                      widget.brand['description'],
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
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
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Search products by name, SKU, or category",
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: (value) => _filterProducts(),
            ),
          ),

          // Results Count
          if (!_isLoading && !_hasError)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    '${_filteredProducts.length} products found',
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 8),

          // Products Grid
          Expanded(
            child: _buildProductGrid(),
          ),
        ],
      ),
    );
  }

  Widget _buildProductGrid() {
    if (_isLoading && _products.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading products...'),
          ],
        ),
      );
    }

    if (_hasError && _products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text('Failed to load products'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadProducts,
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
            const Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isEmpty
                  ? 'No products available for ${widget.brand['name']}'
                  : 'No products found for "${_searchController.text}"',
              textAlign: TextAlign.center,
            ),
            if (_searchController.text.isNotEmpty)
              TextButton(
                onPressed: () {
                  _searchController.clear();
                  _filterProducts();
                },
                child: const Text('Clear search'),
              ),
          ],
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification scrollInfo) {
        if (scrollInfo.metrics.pixels == scrollInfo.metrics.maxScrollExtent && _hasMore && !_isLoadingMore) {
          _loadNextPage();
        }
        return false;
      },
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
            return const Center(child: CircularProgressIndicator());
          }

          final product = _filteredProducts[index];
          final inCart = cart.any((item) => item['id'] == product['id']);
          final cartQuantity = inCart
              ? (cart.firstWhere((item) => item['id'] == product['id'])['cart_quantity'] as int)
              : 0;
          final productStock = product['stock'] is int ? product['stock'] : int.tryParse(product['stock']?.toString() ?? '0') ?? 0;
          final branches = product['branches'] as List<String>? ?? [];

          return Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product Icon and Basic Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.shopping_bag,
                              size: 30,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Product Name
                        Text(
                          product['name'] ?? 'Unnamed Product',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),

                        const SizedBox(height: 4),

                        // Category
                        if (product['categories'] != null && product['categories']['name'] != null)
                          Text(
                            product['categories']['name'],
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.blue[600],
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),

                        // Available Branches
                        if (branches.isNotEmpty)
                          Text(
                            '${branches.length} branch${branches.length > 1 ? 'es' : ''}',
                            style: const TextStyle(
                              fontSize: 9,
                              color: Colors.grey,
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Price and Stock
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '₱${(product['price'] ?? 0).toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green[700],
                          fontSize: 14,
                        ),
                      ),

                      Text(
                        productStock > 0 ? '$productStock in stock' : 'Out of stock',
                        style: TextStyle(
                          fontSize: 10,
                          color: productStock > 0 ? Colors.grey[600] : Colors.red,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),

                  // Add to Cart Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (inCart)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '$cartQuantity in cart',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                      IconButton(
                        icon: Icon(
                          Icons.add_circle,
                          color: productStock > 0 ? Colors.pink : Colors.grey,
                          size: 24,
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
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}