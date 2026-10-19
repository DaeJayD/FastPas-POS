import 'package:flutter/material.dart';
import 'package:vasenizzpos/sales/checkout_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EmployeeBrandProductsPage extends StatefulWidget {
  final Map<String, dynamic> brand;
  final String fullName;
  final String role;
  final String userId;
  final String location;
  final List<Map<String, dynamic>>? existingCart;

  const EmployeeBrandProductsPage({
    Key? key,
    required this.brand,
    required this.fullName,
    required this.role,
    required this.userId,
    required this.location,
    this.existingCart,
  }) : super(key: key);

  @override
  _EmployeeBrandProductsPageState createState() => _EmployeeBrandProductsPageState();
}

class _EmployeeBrandProductsPageState extends State<EmployeeBrandProductsPage> {
  final List<Map<String, dynamic>> cart = [];
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _filteredProducts = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  bool _hasError = false;
  String? _userBranchLocation;

  // Safe string conversion method
  String _safeToString(dynamic value) {
    if (value == null) return '';
    return value.toString();
  }

  @override
  void initState() {
    super.initState();
    cart.clear();
    if (widget.existingCart != null) {
      cart.addAll(List<Map<String, dynamic>>.from(widget.existingCart!));
    }
    _fetchUserBranch();
    _searchController.addListener(_filterProducts);
  }

  Future<void> _fetchUserBranch() async {
    try {
      final response = await Supabase.instance.client
          .from('employees')
          .select('branch')
          .eq('user_id', widget.userId)
          .maybeSingle();

      if (response != null && response['branch'] != null) {
        setState(() {
          _userBranchLocation = _safeToString(response['branch']);
        });
        _loadBranchProducts();
      } else {
        setState(() {
          _userBranchLocation = widget.location;
          _loadBranchProducts();
        });
      }
    } catch (e) {
      print('Error fetching user branch: $e');
      setState(() {
        _userBranchLocation = widget.location;
        _loadBranchProducts();
      });
    }
  }

  Future<void> _loadBranchProducts() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });

      // Get branch ID first
      final branchResponse = await Supabase.instance.client
          .from('branches')
          .select('id')
          .eq('location', _userBranchLocation ?? widget.location)
          .maybeSingle();

      if (branchResponse == null) {
        throw Exception('Branch not found');
      }

      final branchId = branchResponse['id'];
      final brandId = widget.brand['id'];

      // SIMPLIFIED QUERY: Get products from branch_stock that belong to this brand
      final response = await Supabase.instance.client
          .from('branch_stock')
          .select('''
            current_stock,
            product:products(
              id, 
              name, 
              price, 
              sku,
              brand_id,
              category_id,
              brands(name),
              categories(name)
            )
          ''')
          .eq('branch_id', branchId)
          .eq('product.brand_id', brandId)
          .gt('current_stock', 0);

      if (response != null && response.isNotEmpty) {
        List<Map<String, dynamic>> products = [];
        for (var item in response) {
          final product = item['product'];
          if (product != null) {
            products.add({
              'id': product['id'],
              'name': _safeToString(product['name']),
              'price': (product['price'] as num?)?.toDouble() ?? 0.0,
              'sku': _safeToString(product['sku']),
              'brand': _safeToString(product['brands']?['name']),
              'category': _safeToString(product['categories']?['name']),
              'stock': (item['current_stock'] as num?)?.toInt() ?? 0,
            });
          }
        }

        // Sort by name with safe comparison
        products.sort((a, b) => _safeToString(a['name']).compareTo(_safeToString(b['name'])));

        setState(() {
          _products = products;
          _filteredProducts = _products;
          _isLoading = false;
        });
      } else {
        setState(() {
          _products = [];
          _filteredProducts = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading branch products: $e');
      setState(() {
        _isLoading = false;
        _hasError = true;
        _products = [];
        _filteredProducts = [];
      });
    }
  }

  void _filterProducts() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredProducts = _products.where((product) {
        final productName = _safeToString(product['name']).toLowerCase();
        final productSku = _safeToString(product['sku']).toLowerCase();
        final categoryName = _safeToString(product['category']).toLowerCase();
        final brandName = _safeToString(product['brand']).toLowerCase();

        return productName.contains(query) ||
            productSku.contains(query) ||
            categoryName.contains(query) ||
            brandName.contains(query);
      }).toList();
    });
  }

  void addToCart(Map<String, dynamic> product) {
    final productStock = product['stock'] is int ? product['stock'] : int.tryParse(_safeToString(product['stock'])) ?? 0;

    if (productStock <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_safeToString(product['name'])} is out of stock')),
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
      SnackBar(content: Text('${_safeToString(product['name'])} added to cart')),
    );
  }

  int get _totalCartItems {
    return cart.fold<int>(0, (sum, item) => sum + ((item['cart_quantity'] as int?) ?? 0));
  }

  String _getBrandInitial(String? brandName) {
    if (brandName == null || brandName.isEmpty) return 'B';
    return brandName[0].toUpperCase();
  }

  Color _getBrandColor(String? brandName) {
    final colors = [
      Color(0xFFF5C6D3), // Pink
      Color(0xFFC6F5D3), // Green
      Color(0xFFC6D3F5), // Blue
      Color(0xFFF5E6C6), // Yellow
      Color(0xFFD3C6F5), // Purple
    ];
    final index = (brandName?.hashCode ?? 0) % colors.length;
    return colors[index];
  }

  void _goToCheckout() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CheckoutPage(
          cartItems: cart,
          fullName: widget.fullName,
          role: widget.role,
          userId: widget.userId,
          location: _userBranchLocation ?? widget.location,
        ),
      ),
    );
  }

  // Navigate back with cart items
  void _popWithCart() {
    Navigator.of(context).pop(cart);
  }

  @override
  Widget build(BuildContext context) {
    final brandName = _safeToString(widget.brand['name']);
    final brandDescription = _safeToString(widget.brand['description']);

    return Scaffold(
      backgroundColor: const Color(0xFFF8EDF3),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5C6D3),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black54),
          onPressed: _popWithCart,
        ),
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: _getBrandColor(brandName),
              radius: 20,
              child: Text(
                _getBrandInitial(brandName),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    brandName,
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (brandDescription.isNotEmpty)
                    Text(
                      brandDescription,
                      style: TextStyle(color: Colors.black54, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Branch Badge
          if (_userBranchLocation != null)
            Container(
              margin: EdgeInsets.only(right: 8),
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.pink.shade200),
              ),
              child: Text(
                _userBranchLocation!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.pink,
                ),
              ),
            ),
          // Cart Icon
          Stack(
            children: [
              IconButton(
                icon: Icon(Icons.shopping_cart_outlined, color: Colors.black54),
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
                      style: TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.black54),
            onPressed: _loadBranchProducts,
          ),
        ],
      ),
      body: Column(
        children: [
          // Branch Info Banner
          if (_userBranchLocation != null)
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.pink.shade50,
                border: Border.all(color: Colors.pink.shade100),
              ),
              child: Row(
                children: [
                  Icon(Icons.store, color: Colors.pink, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Products available in $_userBranchLocation branch only',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.pink,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
            Text('Loading products for ${_userBranchLocation ?? widget.location}...'),
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
              onPressed: _loadBranchProducts,
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
                  ? 'No products available for ${_safeToString(widget.brand['name'])} in ${_userBranchLocation ?? widget.location}'
                  : 'No products found for "${_searchController.text}"',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: _filteredProducts.length,
      itemBuilder: (context, index) {
        final product = _filteredProducts[index];
        final inCart = cart.any((item) => item['id'] == product['id']);
        final cartQuantity = inCart
            ? ((cart.firstWhere((item) => item['id'] == product['id'])['cart_quantity'] as int?) ?? 0)
            : 0;
        final productStock = product['stock'] is int ? product['stock'] : int.tryParse(_safeToString(product['stock'])) ?? 0;

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
                  _safeToString(product['name']),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),

                // SKU
                Text(
                  'SKU: ${_safeToString(product['sku'])}',
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                ),

                // Category
                if (_safeToString(product['category']).isNotEmpty)
                  Text(
                    _safeToString(product['category']),
                    style: TextStyle(fontSize: 10, color: Colors.blue[600]),
                  ),

                // Price and Stock
                Text(
                  '₱${((product['price'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
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
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}