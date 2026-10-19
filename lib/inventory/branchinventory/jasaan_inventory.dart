
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vasenizzpos/inventory/brand_inventory.dart';

class JasaanInventory extends StatefulWidget {
  final String fullName;
  final String role;
  final String userId;
  final String location;

  const JasaanInventory({
    super.key,
    required this.fullName,
    required this.role,
    required this.location,
    required this.userId,
  });

  @override
  State<JasaanInventory> createState() => _JasaanInventoryState();
}

class _JasaanInventoryState extends State<JasaanInventory> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<dynamic> _brands = [];
  List<dynamic> _filteredBrands = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String? _jasaanBranchId;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get Jasaan branch ID
      final branchResult = await _supabase
          .from('branches')
          .select('id')
          .eq('name', 'JASAAN BRANCH')
          .single();

      _jasaanBranchId = branchResult['id'];
      await _loadBrands();
    } catch (e) {
      _showErrorSnackbar('Failed to load data');
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadBrands() async {
    try {
      // Load only brands assigned to Jasaan branch
      final result = await _supabase
          .from('branch_brands')
          .select('''
          brands:brand_id(
            id,
            name,
            description,
            created_at
          )
        ''')
          .eq('branch_id', _jasaanBranchId!)
          .order('brands(name)');

      // Extract brands from the result
      final brands = result.map((item) => item['brands']).toList();

      setState(() {
        _brands = brands;
        _filteredBrands = brands;
      });
    } catch (e) {
      print('Error loading brands for Jasaan: $e');
      _showErrorSnackbar('Failed to load brands for Jasaan branch');
    }
  }

  void _filterBrands(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredBrands = _brands;
      } else {
        _filteredBrands = _brands.where((brand) {
          final name = brand['name']?.toString().toLowerCase() ?? '';
          return name.contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0FFF0), // Jasaan green background
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HEADER - Jasaan Specific
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                color: Color(0xFF90EE90), // Jasaan green
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Text(
                        "LOGO",
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Jasaan Branch Inventory",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          "${widget.fullName} (${widget.role})",
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.notifications_none, size: 28),
                    onPressed: () {},
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 24),
                    onPressed: _initializeData,
                  ),
                ],
              ),
            ),

            // SEARCH BAR
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: TextField(
                      onChanged: _filterBrands,
                      decoration: InputDecoration(
                        hintText: 'Search Brands in Jasaan Branch',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Jasaan Brands (${_filteredBrands.length})",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                  if (_searchQuery.isNotEmpty)
                    Text(
                      '${_filteredBrands.length} result${_filteredBrands.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // BRAND LIST
            Expanded(
              child: _isLoading
                  ? const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF90EE90), // Jasaan green
                ),
              )
                  : _filteredBrands.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _searchQuery.isEmpty
                          ? Icons.inventory_2_outlined
                          : Icons.search_off,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _searchQuery.isEmpty
                          ? 'No brands available in Jasaan Branch'
                          : 'No brands found for "$_searchQuery"',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                    if (_searchQuery.isEmpty)
                      const SizedBox(height: 8),
                    if (_searchQuery.isEmpty)
                      Text(
                        'Add brands using "Update Brands"',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                  ],
                ),
              )
                  : RefreshIndicator(
                onRefresh: _loadBrands,
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: _filteredBrands.length,
                  itemBuilder: (context, index) {
                    final brand = _filteredBrands[index];
                    final name = brand['name'] ?? 'Unknown Brand';
                    final description = brand['description'];

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            const BoxShadow(
                              color: Colors.black12,
                              blurRadius: 6,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ListTile(
                          contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          title: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.black87,
                            ),
                          ),
                          subtitle: description != null
                              ? Text(
                            description,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.black54,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                              : null,
                          trailing: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: const Color(0xFF90EE90), // Jasaan green
                              borderRadius: BorderRadius.circular(40),
                            ),
                            child: const Icon(Icons.business, color: Colors.white),
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => BrandInventoryPage(
                                  brandName: name,
                                  fullName: widget.fullName,
                                  role: widget.role,
                                  userId: widget.userId,
                                  branchManager: widget.fullName,
                                  branchCode: widget.location,
                                  branchName: "JASAAN BRANCH", // Jasaan branch name
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}