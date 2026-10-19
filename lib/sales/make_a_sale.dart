import 'package:flutter/material.dart';
import 'package:vasenizzpos/products/brand_products_page.dart';
import 'package:vasenizzpos/products/allproducts_sale.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'checkout_page.dart';

class MakeASale extends StatefulWidget {
  final String fullName;
  final String role;
  final String userId;
  final String location;
  final List<Map<String, dynamic>>? existingCart;

  const MakeASale({
    required this.fullName,
    required this.role,
    required this.location,
    required this.userId,
    this.existingCart,
    Key? key
  }) : super(key: key);

  @override
  State<MakeASale> createState() => _MakeASaleState();
}

class _MakeASaleState extends State<MakeASale> {
  final List<Map<String, dynamic>> _brands = [];
  final List<Map<String, dynamic>> _filteredBrands = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  bool _hasError = false;
  List<Map<String, dynamic>> cart = [];

  @override
  void initState() {
    super.initState();


    // Initialize cart with existing items if provided
    if (widget.existingCart != null) {
      cart = List<Map<String, dynamic>>.from(widget.existingCart!);
    }
    _loadBrands();
    _searchController.addListener(_filterBrands);
  }



  Future<void> _loadBrands() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });

      final response = await Supabase.instance.client
          .from('brands')
          .select('*')
          .order('name');

      setState(() {
        _brands.clear();
        _brands.addAll(List<Map<String, dynamic>>.from(response));
        _filteredBrands.clear();
        _filteredBrands.addAll(_brands);
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading brands: $e');
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
          final brandName = brand['name']?.toString().toLowerCase() ?? '';
          final brandId = brand['id']?.toString().toLowerCase() ?? '';
          final description = brand['description']?.toString().toLowerCase() ?? '';
          return brandName.contains(query) ||
              brandId.contains(query) ||
              description.contains(query);
        }).toList());
      }
    });
  }

  // Add this method for All Products navigation
  void _navigateToAllProducts() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AllProductsPage(
          fullName: widget.fullName,
          role: widget.role,
          existingCart: cart,
          userId: widget.userId,
          location: widget.location,
        ),
      ),
    );
  }

  void _addToCart(String brand, String product, double price) {
    setState(() {
      cart.add({'brand': brand, 'product': product, 'price': price});
    });
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
                const Text(
                  "Sales Manager",
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                Text(
                  "${widget.fullName} ${widget.role}",
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                if (cart.isNotEmpty)
                  Text(
                    "${cart.length} items in cart",
                    style: const TextStyle(fontSize: 10, color: Colors.white70),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          if (cart.isNotEmpty)
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.shopping_cart, color: Colors.white),
                  onPressed: () {
                    // Navigate to checkout with existing cart
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CheckoutPage(
                          cartItems: cart,
                          fullName: widget.fullName,
                          userId: widget.userId,
                          location: widget.location,
                          role: 'Cashier',
                        ),
                      ),
                    );
                  },
                ),
                Positioned(
                  right: 6,
                  top: 6,
                  child: CircleAvatar(
                    radius: 8,
                    backgroundColor: Colors.red,
                    child: Text(
                      cart.length.toString(),
                      style: const TextStyle(fontSize: 10, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadBrands,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Search by Name, Brand, Type, ID",
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 20),

            // Add this All Products Button
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
                  "ALL PRODUCTS",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const Text(
              "All Brands",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 10),

            if (_isLoading)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Loading brands...'),
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
                        onPressed: _loadBrands,
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
                              ? 'No brands available'
                              : 'No brands found for "${_searchController.text}"',
                          textAlign: TextAlign.center,
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
                      final brandName = brand['name']?.toString() ?? 'Unknown Brand';
                      final brandDescription = brand['description']?.toString() ?? 'No description';

                      return Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        margin: const EdgeInsets.symmetric(vertical: 6),
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
                          trailing: Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => BrandProductsPage(
                                  brand: brand,
                                  fullName: widget.fullName,
                                  role: widget.role,
                                  existingCart: cart,
                                  userId: widget.userId,
                                  location: widget.location,
                                ),
                              ),
                            );
                          },
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