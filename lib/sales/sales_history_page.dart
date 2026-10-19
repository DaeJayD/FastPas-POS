import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'receipt_page.dart';

class SalesHistoryPage extends StatefulWidget {
  final String fullName;
  final String role;
  final String userId;
  final String location;

  const SalesHistoryPage({
    super.key,
    required this.fullName,
    required this.userId,
    required this.location,
    required this.role,
  });

  @override
  State<SalesHistoryPage> createState() => _SalesHistoryPageState();
}

class _SalesHistoryPageState extends State<SalesHistoryPage> {
  List<Map<String, dynamic>> _sales = [];
  List<Map<String, dynamic>> _filteredSales = [];
  bool _isLoading = true;
  bool _hasError = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSalesHistory();
    _searchController.addListener(_filterSales);
  }

  Future<void> _loadSalesHistory() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });

      // Get all sales from all branches - no join needed since branch_location is text in sales table
      final response = await Supabase.instance.client
          .from('sales')
          .select('*')
          .order('created_at', ascending: false);

      setState(() {
        _sales = List<Map<String, dynamic>>.from(response);
        _filteredSales = _sales;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading sales history: $e');
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  void _filterSales() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredSales = _sales;
      } else {
        _filteredSales = _sales.where((sale) {
          final saleId = sale['id']?.toString().toLowerCase() ?? '';
          final totalAmount = sale['total_amount']?.toString() ?? '';
          final paymentMethod = sale['payment_method']?.toString().toLowerCase() ?? '';
          final cashierName = sale['cashier_name']?.toString().toLowerCase() ?? '';
          final date = _formatDate(sale['created_at']?.toString() ?? '').toLowerCase();
          final time = _formatTime(sale['created_at']?.toString() ?? '').toLowerCase();

          return saleId.contains(query) ||
              totalAmount.contains(query) ||
              paymentMethod.contains(query) ||
              cashierName.contains(query) ||
              date.contains(query) ||
              time.contains(query);
        }).toList();
      }
    });
  }

  String _formatDate(String dateTimeString) {
    try {
      final dateTime = DateTime.parse(dateTimeString);
      return DateFormat('MMM dd, yyyy').format(dateTime);
    } catch (e) {
      return 'Invalid Date';
    }
  }

  String _formatTime(String dateTimeString) {
    try {
      final dateTime = DateTime.parse(dateTimeString);
      return DateFormat('hh:mm a').format(dateTime);
    } catch (e) {
      return 'Invalid Time';
    }
  }

  void _viewSaleDetails(Map<String, dynamic> sale) {

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReceiptPage(
          userId: '',
          location: '',
          saleId: sale['id'],
          paymentMethod: sale['payment_method'] ?? 'Cash',
          subtotal: sale['subtotal_amount'] ?? 0,
          tax: sale['tax_amount'] ?? 0,
          discount: sale['discount_amount'] ?? 0,
          total: sale['total_amount'] ?? 0,
          cartItems: [], // We'll load these in ReceiptPage
          fullName: sale['cashier_name'] ?? 'Unknown',
          role: sale['cashier_role'] ?? 'Cashier',
          cashGiven: sale['total_amount'] ?? 0, // Add cashGiven parameter
          change: 0.0, // Add change parameter
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6E9EE),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: const Color(0xFFF8BBD0),
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.black),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  const CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.receipt_long, color: Colors.pink),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sales History - All Branches',  // Updated title
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        '${widget.fullName} (${widget.role})',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.black),
                    onPressed: _loadSalesHistory,
                  ),
                ],
              ),
            ),
            // Search bar
            Padding(
              padding: const EdgeInsets.all(10),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search by ID, Date, Time, Total',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

            // Summary Cards
            // In your build method, update the summary section:
            if (!_isLoading && !_hasError && _sales.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  children: [
                    // All branches info card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.purple.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.all_inclusive, color: Colors.purple, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Viewing Data From',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              const Text(
                                'All Branches',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              Text(
                                'Your location: ${widget.location}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _buildSummaryCard(
                            'Total Sales',
                            _sales.length.toString(),
                            Icons.receipt,
                            Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildSummaryCard(
                            'Total Revenue',
                            '₱${_sales.fold<double>(0, (sum, sale) => sum + (sale['total_amount'] ?? 0)).toStringAsFixed(2)}',
                            Icons.attach_money,
                            Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 10),

            // Sales list
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _hasError
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    const Text(
                      'Failed to load sales history',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadSalesHistory,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
                  : _filteredSales.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      'No sales records found',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _searchController.text.isEmpty
                          ? 'Start making sales to see history'
                          : 'No sales found for "${_searchController.text}"',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              )
                  : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _filteredSales.length,
                itemBuilder: (context, index) {
                  final sale = _filteredSales[index];
                  return _buildSaleItem(sale);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSaleItem(Map<String, dynamic> sale) {
    final saleId = sale['id']?.toString() ?? '';
    final totalAmount = sale['total_amount'] ?? 0;
    final paymentMethod = sale['payment_method']?.toString() ?? 'Cash';
    final createdAt = sale['created_at']?.toString() ?? '';
    final branchLocation = sale['branch_location']?.toString() ?? 'Main Branch';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => _viewSaleDetails(sale),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF2CED9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black12),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDate(createdAt),
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _getPaymentMethodColor(paymentMethod),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      paymentMethod.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '₱${totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_formatTime(createdAt)} - #${saleId.length >= 8 ? saleId.substring(0, 8).toUpperCase() : saleId.toUpperCase()}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 2),
              // Branch information from the sales table
              Text(
                'Branch: $branchLocation',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.black45,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (sale['cashier_name'] != null)
                Text(
                  'Cashier: ${sale['cashier_name']}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black45,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getPaymentMethodColor(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return Colors.green;
      case 'gcash':
        return Colors.blue;
      case 'card':
        return Colors.purple;
      case 'bank transfer':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}