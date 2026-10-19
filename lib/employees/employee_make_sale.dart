import 'package:flutter/material.dart';
import 'package:vasenizzpos/products/employee_allproducts.dart';
import 'package:vasenizzpos/products/employee_products_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vasenizzpos/sales/checkout_page.dart';

class EmployeeMakeASale extends StatefulWidget {
  final String fullName;
  final String role;
  final String userId;
  final String location;
  final List<Map<String, dynamic>>? existingCart;

  const EmployeeMakeASale({
    required this.fullName,
    required this.role,
    required this.location,
    required this.userId,
    this.existingCart,
    Key? key
  }) : super(key: key);

  @override
  State<EmployeeMakeASale> createState() => _EmployeeMakeASaleState();
}

class _EmployeeMakeASaleState extends State<EmployeeMakeASale> {
  final List<Map<String, dynamic>> _brands = [];
  final List<Map<String, dynamic>> _filteredBrands = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  bool _hasError = false;
  List<Map<String, dynamic>> cart = [];
  String? _userBranchLocation;

  // Add this method to your class
  String _safeToString(dynamic value) {
    if (value == null) return '';
    return value.toString();
  }

  @override
  void initState() {
    super.initState();
    if (widget.existingCart != null) {
      cart = List<Map<String, dynamic>>.from(widget.existingCart!);
      _standardizeCartFields();
    }
    _fetchUserBranch();
    _searchController.addListener(_filterBrands);
  }

  // Standardize cart field names
  void _standardizeCartFields() {
    for (var item in cart) {
      if (item.containsKey('cart_quantity') && !item.containsKey('quantity')) {
        item['quantity'] = item['cart_quantity'];
      }
    }
  }

  // Get the user's actual branch location
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
        _loadBranchBrands();
      } else {
        setState(() {
          _userBranchLocation = widget.location;
        });
        _loadBranchBrands();
      }
    } catch (e) {
      print('Error fetching user branch: $e');
      setState(() {
        _userBranchLocation = widget.location;
        _loadBranchBrands();
      });
    }
  }

  // Load only brands that have products available in this branch
  Future<void> _loadBranchBrands() async {
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

      // Get products that have stock in this branch
      final productsResponse = await Supabase.instance.client
          .from('branch_stock')
          .select('''
            product:products(id, brand_id, brand:brands(id, name, description))
          ''')
          .eq('branch_id', branchId)
          .gt('current_stock', 0);

      Set<String> uniqueBrandIds = {};
      List<Map<String, dynamic>> availableBrands = [];

      // Process products to get unique brands
      if (productsResponse != null && productsResponse.isNotEmpty) {
        for (var item in productsResponse) {
          final brand = item['product']?['brand'];
          if (brand != null && brand['id'] != null) {
            final brandId = _safeToString(brand['id']);
            if (!uniqueBrandIds.contains(brandId)) {
              uniqueBrandIds.add(brandId);
              availableBrands.add({
                'id': brand['id'],
                'name': _safeToString(brand['name']),
                'description': _safeToString(brand['description'])
              });
            }
          }
        }
      }

      setState(() {
        _brands.clear();
        _brands.addAll(availableBrands);
        _filteredBrands.clear();
        _filteredBrands.addAll(_brands);
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading branch brands: $e');
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  void _filterBrands() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredBrands.clear();
      if (query.isEmpty) {
        _filteredBrands.addAll(_brands);
      } else {
        _filteredBrands.addAll(_brands.where((brand) {
          final brandName = _safeToString(brand['name']).toLowerCase();
          final description = _safeToString(brand['description']).toLowerCase();
          return brandName.contains(query) || description.contains(query);
        }).toList());
      }
    });
  }

  Future<void> _navigateToAllProducts() async {
    final updatedCart = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EmployeeAllProducts(
          fullName: widget.fullName,
          role: widget.role,
          existingCart: cart,
          userId: widget.userId,
          location: _userBranchLocation ?? widget.location,
        ),
      ),
    );

    if (updatedCart != null && updatedCart is List<Map<String, dynamic>>) {
      setState(() {
        cart = updatedCart;
        _standardizeCartFields();
      });
    }
  }

  Future<void> _navigateToEmployeeBrandProductsPage(Map<String, dynamic> brand) async {
    final updatedCart = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EmployeeBrandProductsPage(
          brand: brand,
          fullName: widget.fullName,
          role: widget.role,
          existingCart: cart,
          userId: widget.userId,
          location: _userBranchLocation ?? widget.location,
        ),
      ),
    );

    if (updatedCart != null && updatedCart is List<Map<String, dynamic>>) {
      setState(() {
        cart = updatedCart;
        _standardizeCartFields();
      });
    }
  }

  Future<void> _navigateToCheckout() async {
    final updatedCart = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CheckoutPage(
          cartItems: cart,
          fullName: widget.fullName,
          userId: widget.userId,
          location: _userBranchLocation ?? widget.location,
          role: widget.role,
        ),
      ),
    );

    if (updatedCart != null && updatedCart is List<Map<String, dynamic>>) {
      setState(() {
        cart = updatedCart;
        _standardizeCartFields();
      });
    }
  }

  int _getItemQuantity(Map<String, dynamic> item) {
    return (item['quantity'] as num?)?.toInt() ?? 1;
  }

  int _getTotalCartItems() {
    return cart.fold(0, (total, item) {
      return total + _getItemQuantity(item);
    });
  }

  double _calculateItemTotal(Map<String, dynamic> item) {
    final price = (item['price'] as num?)?.toDouble() ?? 0.0;
    final quantity = _getItemQuantity(item);
    return price * quantity;
  }

  void _clearCart() {
    setState(() {
      cart.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Cart cleared'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _viewCartSummary() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Cart Summary',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            SizedBox(height: 16),
            if (cart.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('Your cart is empty'),
                    Text(
                      'Add some products to get started',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              )
            else
              Column(
                children: [
                  ...cart.asMap().entries.map((entry) {
                    final item = entry.value;
                    final itemTotal = _calculateItemTotal(item);
                    final quantity = _getItemQuantity(item);
                    return ListTile(
                      leading: item['image_url'] != null
                          ? CircleAvatar(backgroundImage: NetworkImage(item['image_url']))
                          : CircleAvatar(
                        backgroundColor: _getBrandColor(_safeToString(item['name'])),
                        child: Text(_getBrandInitial(_safeToString(item['name']))),
                      ),
                      title: Text(_safeToString(item['name'])),
                      subtitle: Text(
                        '₱${(item['price'] as num?)?.toStringAsFixed(2) ?? '0.00'} x $quantity',
                      ),
                      trailing: Text(
                        '₱${itemTotal.toStringAsFixed(2)}',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    );
                  }),
                  Divider(),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _navigateToCheckout,
                    child: Text('Proceed to Checkout'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.pink,
                      foregroundColor: Colors.white,
                      minimumSize: Size(double.infinity, 50),
                    ),
                  ),
                ],
              ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Continue Shopping'),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 50),
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
        backgroundColor: const Color(0xFFF5C6D3),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              backgroundImage: const AssetImage('assets/logo.png'),
              radius: 20,
              backgroundColor: Colors.white,
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${_userBranchLocation ?? widget.location} Sales",
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                Text(
                  "${widget.fullName} (${widget.role})",
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Branch Badge
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.pink.shade200),
            ),
            child: Text(
              _userBranchLocation ?? widget.location,
              style: const TextStyle(
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
                icon: const Icon(Icons.shopping_cart, color: Colors.white),
                onPressed: cart.isNotEmpty ? _viewCartSummary : null,
              ),
              if (cart.isNotEmpty)
                Positioned(
                  right: 6,
                  top: 6,
                  child: CircleAvatar(
                    radius: 8,
                    backgroundColor: Colors.red,
                    child: Text(
                      _getTotalCartItems().toString(),
                      style: const TextStyle(fontSize: 10, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
          // More options menu
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              if (value == 'clear_cart' && cart.isNotEmpty) {
                _clearCart();
              } else if (value == 'refresh') {
                _loadBranchBrands();
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              if (cart.isNotEmpty)
                PopupMenuItem<String>(
                  value: 'clear_cart',
                  child: Row(
                    children: [
                      Icon(Icons.clear_all, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Clear Cart'),
                    ],
                  ),
                ),
              PopupMenuItem<String>(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('Refresh Brands'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Branch Info Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.pink.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.pink.shade100),
              ),
              child: Row(
                children: [
                  Icon(Icons.store, color: Colors.pink, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Products available in ${_userBranchLocation ?? widget.location} branch only',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.pink,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Search Bar
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Search brands in ${_userBranchLocation ?? widget.location}",
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 20),

            // All Products Button
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 20),
              child: ElevatedButton.icon(
                onPressed: _navigateToAllProducts,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.pink,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                icon: const Icon(Icons.all_inclusive, size: 24),
                label: const Text(
                  "BROWSE ALL PRODUCTS",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            // Brands Section Header
            Row(
              children: [
                const Text(
                  "Available Brands",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.pink.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _brands.length.toString(),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Brands List
            if (_isLoading)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Loading ${_userBranchLocation ?? widget.location} brands...'),
                    ],
                  ),
                ),
              )
            else if (_hasError)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.red),
                      SizedBox(height: 16),
                      Text('Failed to load brands'),
                      SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadBranchBrands,
                        child: Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_filteredBrands.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          _searchController.text.isEmpty
                              ? 'No brands available in ${_userBranchLocation ?? widget.location}'
                              : 'No brands found for "${_searchController.text}"',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Check inventory or contact manager',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: _filteredBrands.length,
                    itemBuilder: (context, index) {
                      final brand = _filteredBrands[index];
                      final brandName = _safeToString(brand['name']);
                      final brandDescription = _safeToString(brand['description']);

                      return Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        elevation: 2,
                        child: ListTile(
                          leading: CircleAvatar(
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
                          title: Text(
                            brandName,
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(brandDescription),
                          trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.pink),
                          onTap: () => _navigateToEmployeeBrandProductsPage(brand),
                        ),
                      );
                    },
                  ),
                ),
          ],
        ),
      ),
    );
  }

  String _getBrandInitial(String brandName) {
    if (brandName.isEmpty) return 'B';
    return brandName[0].toUpperCase();
  }

  Color _getBrandColor(String brandName) {
    final colors = [
      Color(0xFFF5C6D3), // Pink
      Color(0xFFC6F5D3), // Green
      Color(0xFFC6D3F5), // Blue
      Color(0xFFF5E6C6), // Yellow
      Color(0xFFD3C6F5), // Purple
    ];
    final index = brandName.hashCode % colors.length;
    return colors[index];
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}