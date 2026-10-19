import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InventoryHistoryScreen extends StatefulWidget {
  final String fullName;
  final String role;
  final String userId;

  const InventoryHistoryScreen({
    Key? key,
    required this.fullName,
    required this.role,
    required this.userId,
  }) : super(key: key);

  @override
  State<InventoryHistoryScreen> createState() => _InventoryHistoryScreenState();
}

class _InventoryHistoryScreenState extends State<InventoryHistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final SupabaseClient _supabase = Supabase.instance.client;

  List<dynamic> _historyData = [];
  List<dynamic> _filteredData = [];
  bool _isLoading = true;
  bool _hasMore = true;
  int _currentPage = 1;
  final int _pageSize = 50;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadHistoryData();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
      _filterData();
    });
  }

  void _filterData() {
    if (_searchQuery.isEmpty) {
      _filteredData = _historyData;
    } else {
      _filteredData = _historyData.where((item) {
        final productName = item['product_name']?.toString().toLowerCase() ?? '';
        final movementType = item['movement_type']?.toString().toLowerCase() ?? '';
        final reason = item['reason']?.toString().toLowerCase() ?? '';
        final user = item['employee_name']?.toString().toLowerCase() ?? '';
        final sku = item['product_sku']?.toString().toLowerCase() ?? '';
        final query = _searchQuery.toLowerCase();

        return productName.contains(query) ||
            movementType.contains(query) ||
            reason.contains(query) ||
            user.contains(query) ||
            sku.contains(query);
      }).toList();
    }
  }

  Future<void> _loadHistoryData({bool loadMore = false}) async {
    if (!loadMore) {
      setState(() {
        _isLoading = true;
        _currentPage = 1;
      });
    }

    try {
      final from = (loadMore ? _currentPage : 0) * _pageSize; // Fixed calculation

      final data = await _supabase
          .from('inventory_movements')
          .select('''
          *,
          products:product_id (
            name,
            sku,
            brands (name),
            categories (name)
          ),
          employees:user_id (
            name
          ),
          branches:branch_id (
            name
          )
        ''')
          .order('created_at', ascending: false)
          .range(from, from + _pageSize - 1);

      if (!mounted) return;

      // Transform the data to match the expected format
      final newData = (data as List).map((movement) {
        final product = movement['products'] ?? {};
        final employee = movement['employees'] ?? {};
        final branch = movement['branches'] ?? {};

        return {
          'id': movement['id'],
          'created_at': movement['created_at'],
          'movement_type': movement['movement_type'],
          'quantity': movement['quantity'],
          'previous_stock': movement['previous_stock'],
          'new_stock': movement['new_stock'],
          'reason': movement['reason'],
          'product_name': product['name'] ?? 'Unknown Product',
          'product_sku': product['sku'] ?? 'N/A',
          'brand_name': product['brands']?['name'] ?? 'N/A',
          'category_name': product['categories']?['name'] ?? 'N/A',
          'employee_name': employee['name'] ?? 'Unknown User',
          'branch_name': branch['name'] ?? 'Unknown Branch',
          'user_id': movement['user_id'],
          'reference_id': movement['reference_id'],
        };
      }).toList();

      setState(() {
        if (loadMore) {
          _historyData.addAll(newData);
        } else {
          _historyData = newData;
        }

        _filterData();
        _hasMore = newData.length == _pageSize;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showErrorSnackbar('Error loading inventory history: $e');
    }
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _loadMoreData() {
    if (_hasMore && !_isLoading) {
      setState(() {
        _currentPage++;
      });
      _loadHistoryData(loadMore: true);
    }
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
    } catch (e) {
      return dateString.length > 10 ? dateString.substring(0, 10) : dateString;
    }
  }

  String _formatTime(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      if (dateString.length > 16) {
        return dateString.substring(11, 16);
      }
      return dateString;
    }
  }

  String _getMovementTypeText(String type) {
    switch (type) {
      case 'in': return 'Stock In';
      case 'out': return 'Stock Out';
      case 'sold': return 'Sold';
      case 'adjustment': return 'Adjustment';
      case 'transfer': return 'Transfer';
      default: return type;
    }
  }

  Color _getMovementColor(String type) {
    switch (type) {
      case 'in': return Colors.green;
      case 'out':
      case 'sold': return Colors.red;
      case 'adjustment': return Colors.orange;
      case 'transfer': return Colors.blue;
      default: return Colors.grey;
    }
  }

  String _getQuantityDisplay(String type, dynamic quantity) {
    final qty = quantity is int ? quantity : int.tryParse(quantity.toString()) ?? 0;
    switch (type) {
      case 'in': return '+$qty';
      case 'out':
      case 'sold': return '-$qty';
      case 'adjustment':
        return qty >= 0 ? '+$qty' : '$qty';
      case 'transfer': return '→$qty';
      default: return qty.toString();
    }
  }

  Widget _buildStockChangeWidget(String type, int previousStock, int newStock) {
    final change = newStock - previousStock;
    final isPositive = change >= 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$previousStock',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
        Icon(
          isPositive ? Icons.arrow_upward : Icons.arrow_downward,
          color: isPositive ? Colors.green : Colors.red,
          size: 16,
        ),
        Text(
          '$newStock',
          style: TextStyle(
            color: isPositive ? Colors.green : Colors.red,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
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
          icon: const Icon(Icons.arrow_back, color: Colors.black54),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            const CircleAvatar(
              backgroundImage: AssetImage('assets/logo.png'),
              radius: 22,
              backgroundColor: Colors.white,
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Inventory History",
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87),
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
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black54),
            onPressed: () => _loadHistoryData(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Section
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3)],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Search Inventory History",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8EDF3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search by product, type, reason, or user...',
                        border: InputBorder.none,
                        suffixIcon: Icon(Icons.search, color: Colors.pink.shade300),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // History Table
          Expanded(
            child: _isLoading && _historyData.isEmpty
                ? const Center(child: CircularProgressIndicator(color: Colors.pink))
                : _filteredData.isEmpty
                ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No inventory movements found',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  Text(
                    'Inventory movements will appear here',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            )
                : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3)],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            "Stock Movement History",
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const Spacer(),
                          Text(
                            "Total: ${_filteredData.length} records",
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                      const Divider(height: 20, color: Colors.black26),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columnSpacing: 24,
                          columns: const [
                            DataColumn(label: Text("Date", style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text("Time", style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text("Product", style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text("Type", style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text("Qty", style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text("Stock Change", style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text("User", style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text("Reason", style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text("SKU", style: TextStyle(fontWeight: FontWeight.bold))),
                          ],
                          rows: [
                            ..._filteredData.map((item) {
                              final movementType = item['movement_type']?.toString() ?? '';
                              final quantity = item['quantity'] ?? 0;
                              final previousStock = item['previous_stock'] ?? 0;
                              final newStock = item['new_stock'] ?? 0;

                              return DataRow(
                                cells: [
                                  DataCell(Text(_formatDate(item['created_at']?.toString() ?? ''))),
                                  DataCell(Text(_formatTime(item['created_at']?.toString() ?? ''))),
                                  DataCell(Text(item['product_name']?.toString() ?? 'N/A')),
                                  DataCell(Text(
                                    _getMovementTypeText(movementType),
                                    style: TextStyle(color: _getMovementColor(movementType), fontWeight: FontWeight.bold),
                                  )),
                                  DataCell(Text(
                                    _getQuantityDisplay(movementType, quantity),
                                    style: TextStyle(
                                      color: _getMovementColor(movementType),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )),
                                  DataCell(_buildStockChangeWidget(movementType, previousStock, newStock)),
                                  DataCell(Text(item['employee_name']?.toString() ?? 'N/A')),
                                  DataCell(Text(item['reason']?.toString() ?? 'N/A')),
                                  DataCell(Text(item['product_sku']?.toString() ?? 'N/A')),
                                ],
                              );
                            }).toList(),
                            if (_hasMore && !_isLoading)
                              DataRow(
                                cells: [
                                  DataCell(
                                    SizedBox(
                                      width: 120,
                                      child: TextButton(
                                        onPressed: _loadMoreData,
                                        child: const Text('Load More...'),
                                      ),
                                    ),
                                  ),
                                  const DataCell(Text('')),
                                  const DataCell(Text('')),
                                  const DataCell(Text('')),
                                  const DataCell(Text('')),
                                  const DataCell(Text('')),
                                  const DataCell(Text('')),
                                  const DataCell(Text('')),
                                  const DataCell(Text('')),
                                ],
                              ),
                            if (_isLoading && _historyData.isNotEmpty)
                              DataRow(
                                cells: [
                                  DataCell(
                                    const Center(child: CircularProgressIndicator(color: Colors.pink)),
                                  ),
                                  const DataCell(Text('')),
                                  const DataCell(Text('')),
                                  const DataCell(Text('')),
                                  const DataCell(Text('')),
                                  const DataCell(Text('')),
                                  const DataCell(Text('')),
                                  const DataCell(Text('')),
                                  const DataCell(Text('')),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}