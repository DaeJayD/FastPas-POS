import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'employee_make_sale.dart';
import 'package:vasenizzpos/sales/sales_history_page.dart';

class EmployeeBranchSalesContent extends StatefulWidget {
  final String fullName;
  final String role;
  final String userId;
  final String location;

  const EmployeeBranchSalesContent({
    required this.fullName,
    required this.role,
    required this.userId,
    required this.location,
    super.key,
  });

  @override
  State<EmployeeBranchSalesContent> createState() => _EmployeeBranchSalesContentState();
}

class _EmployeeBranchSalesContentState extends State<EmployeeBranchSalesContent> {
  List<Map<String, dynamic>> _recentSales = [];
  List<Map<String, dynamic>> _filteredSales = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadBranchRecentSales();
    _searchController.addListener(_filterSales);
  }

  Future<void> _loadBranchRecentSales() async {
    try {
      final response = await Supabase.instance.client
          .from('sales')
          .select('*')
          .eq('branch_location', widget.location)
          .order('created_at', ascending: false)
          .limit(7);

      setState(() {
        _recentSales = List<Map<String, dynamic>>.from(response);
        _filteredSales = _recentSales;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading branch sales: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterSales() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredSales = _recentSales;
      } else {
        _filteredSales = _recentSales.where((sale) {
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

  void _showRecentSalesDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Row(
          children: [
            Icon(Icons.receipt_long, color: Colors.pink),
            SizedBox(width: 8),
            Text(
              'Recent Sales - ${widget.location}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontFamily: 'Poppins',
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: _recentSales.isEmpty
              ? Center(
            child: Column(
              children: [
                Icon(Icons.receipt_long, size: 50, color: Colors.grey),
                SizedBox(height: 10),
                Text(
                  'No recent sales in ${widget.location}',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          )
              : ListView.builder(
            shrinkWrap: true,
            itemCount: _recentSales.length,
            itemBuilder: (context, index) {
              final sale = _recentSales[index];
              return _buildRecentSaleDialogItem(sale);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SalesHistoryPage(
                    fullName: widget.fullName,
                    role: widget.role,
                    userId: widget.userId,
                    location: widget.location,
                  ),
                ),
              );
            },
            child: Text('View All'),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentSaleDialogItem(Map<String, dynamic> sale) {
    final saleId = sale['id']?.toString() ?? '';
    final totalAmount = sale['total_amount'] ?? 0;
    final paymentMethod = sale['payment_method']?.toString() ?? 'Cash';
    final createdAt = sale['created_at']?.toString() ?? '';

    return Container(
      margin: EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color(0xFFF8EDF3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _getPaymentMethodColor(paymentMethod),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _getPaymentMethodIcon(paymentMethod),
              color: Colors.white,
              size: 20,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Receipt #${saleId.substring(0, 8).toUpperCase()}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    fontFamily: 'Poppins',
                  ),
                ),
                Text(
                  '${_formatDate(createdAt)} • ${_formatTime(createdAt)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.black54,
                    fontFamily: 'Poppins',
                  ),
                ),
                Text(
                  paymentMethod.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    color: _getPaymentMethodColor(paymentMethod),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '₱${totalAmount.toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.green,
              fontFamily: 'Poppins',
            ),
          ),
        ],
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

  IconData _getPaymentMethodIcon(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return Icons.payments;
      case 'gcash':
        return Icons.account_balance_wallet;
      case 'card':
        return Icons.credit_card;
      case 'bank transfer':
        return Icons.account_balance;
      default:
        return Icons.payment;
    }
  }

  Widget _buildRecentSaleItem(Map<String, dynamic> sale) {
    final saleId = sale['id']?.toString() ?? '';
    final totalAmount = sale['total_amount'] ?? 0;
    final createdAt = sale['created_at']?.toString() ?? '';

    return Container(
      margin: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _getPaymentMethodIcon(sale['payment_method']?.toString() ?? 'Cash'),
              color: Colors.white,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Receipt #${saleId.substring(0, 8).toUpperCase()}",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Poppins',
                    fontSize: 14,
                  ),
                ),
                Text(
                  '₱${totalAmount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatDate(createdAt),
                style: TextStyle(
                  color: Colors.black54,
                  fontFamily: 'Poppins',
                  fontSize: 12,
                ),
              ),
              Text(
                _formatTime(createdAt),
                style: TextStyle(
                  color: Colors.black54,
                  fontFamily: 'Poppins',
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF6E9EE),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Color(0xFFF5C6D3),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black54),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              backgroundImage: AssetImage('assets/logo.png'),
              radius: 20,
              backgroundColor: Colors.white,
            ),
            SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${widget.location} Sales",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  "${widget.fullName} (${widget.role})",
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.notifications_none_rounded, color: Colors.black54),
            onPressed: () {},
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search Bar
            Padding(
              padding: EdgeInsets.only(left: 16, right: 16, top: 15, bottom: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4,
                      offset: Offset(2, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search by ID, Date, Time, Total',
                    hintStyle: TextStyle(color: Colors.black54, fontFamily: 'Poppins'),
                    prefixIcon: Icon(Icons.search, color: Colors.black54),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  ),
                ),
              ),
            ),

            SizedBox(height: 20),

            // Make a Sale Button
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EmployeeMakeASale(
                      fullName: widget.fullName,
                      role: widget.role,
                      userId: widget.userId,
                      location: widget.location,
                    ),
                  ),
                );
              },
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: 25),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: Offset(2, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      SizedBox(width: 25),
                      Icon(Icons.shopping_cart_outlined, size: 35, color: Colors.black87),
                      SizedBox(width: 20),
                      Text(
                        "Make a Sale",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Poppins',
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            SizedBox(height: 20),

            // Sales History Button
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SalesHistoryPage(
                      fullName: widget.fullName,
                      role: widget.role,
                      userId: widget.userId,
                      location: widget.location,
                    ),
                  ),
                );
              },
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: 23),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: Offset(2, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      SizedBox(width: 25),
                      Icon(Icons.inventory_2_outlined, size: 33, color: Colors.black87),
                      SizedBox(width: 20),
                      Text(
                        "Sales History",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Poppins',
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            SizedBox(height: 25),

            // Recent Sales Section
            GestureDetector(
              onTap: _showRecentSalesDialog,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 6,
                        offset: Offset(2, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            "Recent Sales - ${widget.location}",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              fontFamily: 'Poppins',
                            ),
                          ),
                          Spacer(),
                          Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                        ],
                      ),
                      Divider(),

                      if (_isLoading)
                        Center(child: CircularProgressIndicator())
                      else if (_filteredSales.isEmpty)
                        Center(
                          child: Text(
                            'No recent sales in ${widget.location}',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      else
                        ..._filteredSales
                            .take(4)
                            .map((sale) => _buildRecentSaleItem(sale))
                            .toList(),

                      if (_filteredSales.length > 4)
                        Center(
                          child: Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'Tap to view more...',
                              style: TextStyle(
                                color: Colors.pink,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}