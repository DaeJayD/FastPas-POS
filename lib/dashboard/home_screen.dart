import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vasenizzpos/inventory/inventory_screen.dart';
import 'package:vasenizzpos/sales/sales_screen.dart';
import 'package:vasenizzpos/reports/reports_page.dart';
import 'package:vasenizzpos/users/users_page.dart';

class HomeScreen extends StatefulWidget {
  final String fullName;
  final String role;
  final String location;
  final String userId;
  final int initialIndex;

  const HomeScreen({
    required this.fullName,
    required this.role,
    required this.location,
    required this.userId,
    this.initialIndex = 0,
    Key? key,
  }) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late int _selectedIndex;
  Map<String, dynamic> _salesData = {
    'itemsSoldToday': 0,
    'totalSalesToday': 0.0,
    'totalSalesYesterday': 0.0,
  };
  List<Map<String, dynamic>> _topSelling = [];
  List<Map<String, dynamic>> _lowStockProducts = [];
  List<Map<String, dynamic>> _recentAttendance = [];
  bool _isLoading = true;
  bool _isLoadingLowStock = true;
  bool _isLoadingAttendance = true;
  bool _showLowStockList = false;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _loadDashboardData();
    _loadLowStockProducts();
    _loadRecentAttendance();
  }

  Future<void> _loadRecentAttendance() async {
    try {
      final response = await Supabase.instance.client
          .from('attendance')
          .select('''
          time_in,
          time_out,
          date,
          employees!attendance_user_id_fkey (
            name,
            branch,
            role
          )
        ''')
          .order('date', ascending: false)
          .order('time_in', ascending: false)
          .limit(3);

      setState(() {
        _recentAttendance = List<Map<String, dynamic>>.from(response);
        _isLoadingAttendance = false;
      });
    } catch (e) {
      print('Error loading recent attendance: $e');
      setState(() {
        _isLoadingAttendance = false;
      });
    }
  }

  Future<void> _loadLowStockProducts() async {
    try {
      final response = await Supabase.instance.client
          .from('branch_stock')
          .select('''
            current_stock,
            low_stock_threshold,
            products(name, price, categories(name)),
            branches(name)
          ''')
          .eq('branches.name', widget.location);

      final stockData = List<Map<String, dynamic>>.from(response);

      final lowStock = stockData.where((item) {
        final currentStock = item['current_stock'] ?? 0;
        return currentStock <= 5; // Running low: ≤5 pieces
      }).toList();

      setState(() {
        _lowStockProducts = lowStock;
        _isLoadingLowStock = false;
      });
    } catch (e) {
      print('Error loading low stock products: $e');
      setState(() {
        _isLoadingLowStock = false;
      });
    }
  }

  Future<void> _loadDashboardData() async {
    try {
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final yesterdayStart = todayStart.subtract(const Duration(days: 1));
      final yesterdayEnd = todayStart.subtract(const Duration(seconds: 1));

      // Get today's sales from ALL branches (remove branch filtering)
      final todaySalesResponse = await Supabase.instance.client
          .from('sales')
          .select('*')
          .gte('created_at', todayStart.toIso8601String());

      final todaySales = List<Map<String, dynamic>>.from(todaySalesResponse);

      // Get yesterday's sales from ALL branches for comparison
      final yesterdaySalesResponse = await Supabase.instance.client
          .from('sales')
          .select('*')
          .gte('created_at', yesterdayStart.toIso8601String())
          .lte('created_at', yesterdayEnd.toIso8601String());

      final yesterdaySales = List<Map<String, dynamic>>.from(yesterdaySalesResponse);

      // Get top selling products from ALL branches (last 7 days)
      final weekAgo = today.subtract(const Duration(days: 7));
      final topSellingResponse = await Supabase.instance.client
          .from('sale_items')
          .select('''
          product_id,
          quantity,
          products(name, price)
        ''')
          .gte('created_at', weekAgo.toIso8601String());

      final topSellingItems = List<Map<String, dynamic>>.from(topSellingResponse);

      // Calculate totals from ALL branches
      int itemsSoldToday = 0;
      double totalSalesToday = 0.0;
      double totalSalesYesterday = 0.0;

      // Calculate today's data from all branches
      for (final sale in todaySales) {
        totalSalesToday += (sale['total_amount'] ?? 0).toDouble();

        // Get sale items for this sale to count quantities
        final saleItemsResponse = await Supabase.instance.client
            .from('sale_items')
            .select('quantity')
            .eq('sale_id', sale['id']);

        final saleItems = List<Map<String, dynamic>>.from(saleItemsResponse);
        for (final item in saleItems) {
          itemsSoldToday += (item['quantity'] as int? ?? 0);
        }
      }

      // Calculate yesterday's total from all branches
      for (final sale in yesterdaySales) {
        totalSalesYesterday += (sale['total_amount'] ?? 0).toDouble();
      }

      // Aggregate product sales from all branches
      final productSales = <String, Map<String, dynamic>>{};
      for (final item in topSellingItems) {
        final productId = item['product_id'].toString();
        final product = item['products'] ?? {};
        final productName = product['name'] ?? 'Unknown Product';
        final productPrice = product['price'] ?? 0.0;
        final quantity = item['quantity'] ?? 0;

        if (productSales.containsKey(productId)) {
          productSales[productId]!['quantity'] += quantity;
        } else {
          productSales[productId] = {
            'name': productName,
            'quantity': quantity,
            'price': productPrice,
          };
        }
      }

      // Convert to list and sort by quantity
      final topSellingList = productSales.values.toList();
      topSellingList.sort((a, b) => (b['quantity'] ?? 0).compareTo(a['quantity'] ?? 0));

      setState(() {
        _salesData = {
          'itemsSoldToday': itemsSoldToday,
          'totalSalesToday': totalSalesToday,
          'totalSalesYesterday': totalSalesYesterday,
        };
        _topSelling = topSellingList.take(3).toList(); // Top 3 products
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading dashboard data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  String get _salesChange {
    final today = _salesData['totalSalesToday'] ?? 0.0;
    final yesterday = _salesData['totalSalesYesterday'] ?? 0.0;

    if (yesterday == 0) {
      return today > 0 ? '+100%' : '0%';
    }

    final change = ((today - yesterday) / yesterday) * 100;
    return '${change >= 0 ? '+' : ''}${change.toStringAsFixed(0)}%';
  }

  Color get _salesChangeColor {
    final today = _salesData['totalSalesToday'] ?? 0.0;
    final yesterday = _salesData['totalSalesYesterday'] ?? 0.0;
    return today >= yesterday ? Colors.green : Colors.red;
  }

  void _onItemTapped(int index) {
    if (index == _selectedIndex) return;

    setState(() => _selectedIndex = index);

    Widget nextPage;
    switch (index) {
      case 0:
        nextPage = HomeScreen(
          fullName: widget.fullName,
          role: widget.role,
          userId: widget.userId,
          location: widget.location,
          initialIndex: 0,
        );
        break;
      case 1:
        nextPage = SalesScreen(
          fullName: widget.fullName,
          role: widget.role,
          userId: widget.userId,
          location: widget.location,
        );
        break;
      case 2:
        nextPage = InventoryPage(
          fullName: widget.fullName,
          role: widget.role,
          userId: widget.userId,
          location: widget.location,
        );
        break;
      case 3:
        nextPage = ViewReportsPage(
          fullName: widget.fullName,
          role: widget.role,
          userId: widget.userId,
          location: widget.location,
        );
        break;
      case 4:
        nextPage = UsersPage(
          fullName: widget.fullName,
          role: widget.role,
          userId: widget.userId,
          location: widget.location,
          initialIndex: 4,
        );
        break;
      default:
        return;
    }

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation1, animation2) => nextPage,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  void _toggleLowStockList() {
    setState(() {
      _showLowStockList = !_showLowStockList;
    });
  }

  Widget _buildLowStockSummary() {
    final outOfStockCount = _lowStockProducts.where((item) => (item['current_stock'] ?? 0) == 0).length;
    final runningLowCount = _lowStockProducts.where((item) => (item['current_stock'] ?? 0) > 0 && (item['current_stock'] ?? 0) <= 5).length;
    final totalLowStock = outOfStockCount + runningLowCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _toggleLowStockList,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3)],
              border: Border.all(
                color: totalLowStock > 0 ? Colors.orange : Colors.green,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  totalLowStock > 0 ? Icons.warning_amber : Icons.inventory_2,
                  color: totalLowStock > 0 ? Colors.orange : Colors.green,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Running Low Inventory',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: totalLowStock > 0 ? Colors.orange : Colors.green,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$totalLowStock items need attention',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                      if (totalLowStock > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            _buildStockIndicator('Out of Stock', outOfStockCount, Colors.red),
                            const SizedBox(width: 8),
                            _buildStockIndicator('Running Low', runningLowCount, Colors.orange),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  _showLowStockList ? Icons.expand_less : Icons.expand_more,
                  color: Colors.grey,
                ),
              ],
            ),
          ),
        ),

        if (_showLowStockList && totalLowStock > 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              children: [
                ..._lowStockProducts.take(10).map((product) => _buildLowStockItem(product)).toList(),
                if (_lowStockProducts.length > 10)
                  Text(
                    '+ ${_lowStockProducts.length - 10} more items...',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () => _onItemTapped(2), // Navigate to Inventory
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  ),
                  child: const Text('View All in Inventory'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStockIndicator(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$count $label',
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLowStockItem(Map<String, dynamic> product) {
    final currentStock = product['current_stock'] ?? 0;
    final productName = product['products']?['name'] ?? 'Unknown Product';
    final category = product['products']?['categories']?['name'] ?? 'Uncategorized';
    final isOutOfStock = currentStock == 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isOutOfStock ? Colors.red.withOpacity(0.3) : Colors.orange.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isOutOfStock ? Icons.error_outline : Icons.warning_amber,
            color: isOutOfStock ? Colors.red : Colors.orange,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  productName,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  category,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isOutOfStock ? Colors.red.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isOutOfStock ? 'Out of Stock' : '$currentStock pcs left',
              style: TextStyle(
                fontSize: 10,
                color: isOutOfStock ? Colors.red : Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceCard() {
    return Container(
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
              Icon(Icons.access_time, color: Colors.pink.shade400, size: 20),
              const SizedBox(width: 8),
              const Text(
                "Recent Attendance",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.refresh, size: 18, color: Colors.grey),
                onPressed: _loadRecentAttendance,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isLoadingAttendance)
            const Center(child: CircularProgressIndicator())
          else if (_recentAttendance.isEmpty)
            const Center(
              child: Text(
                'No attendance records',
                style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
              ),
            )
          else
            Column(
              children: _recentAttendance.map((attendance) => _buildAttendanceItem(attendance)).toList(), // Removed .take(5)
            ),
        ],
      ),
    );
  }

  Widget _buildAttendanceItem(Map<String, dynamic> attendance) {
    final employee = attendance['employees'] ?? {};
    final userName = employee['name'] ?? 'Unknown User';
    final branch = employee['branch'] ?? 'Unknown Branch';
    final role = employee['role'] ?? '';
    final timeIn = attendance['time_in'] != null ? DateTime.parse(attendance['time_in']) : null;
    final timeOut = attendance['time_out'] != null ? DateTime.parse(attendance['time_out']) : null;
    final date = attendance['date'] ?? '';

    final isClockedIn = timeOut == null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Color(0xFF878383)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isClockedIn ? Colors.green : Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  userName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$branch • $role',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.deepPurpleAccent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  date,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (timeIn != null)
                Text(
                  'In: ${timeIn.hour}:${timeIn.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
              if (timeOut != null)
                Text(
                  'Out: ${timeOut.hour}:${timeOut.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
              if (isClockedIn)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'On Duty',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
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
      backgroundColor: const Color(0xFFF8EDF3),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFFF5C6D3),
        elevation: 0,
        title: Row(
          children: [
            CircleAvatar(
              backgroundImage: const AssetImage('assets/logo.png'),
              radius: 22,
              backgroundColor: Colors.white,
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Dashboard",
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                Text(
                  "Welcome Back!\n${widget.fullName} (${widget.role})",
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black54),
            onPressed: () {
              _loadDashboardData();
              _loadLowStockProducts();
              _loadRecentAttendance();
            },
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded, color: Colors.black54),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            sectionTitle("Sales Activity"),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: dashboardCard(
                    icon: Icons.shopping_cart,
                    title: _isLoading ? "..." : "${_salesData['itemsSoldToday']}",
                    subtitle: "Items Sold Today",
                    extra: "Today",
                    color: Colors.pink.shade50,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _onItemTapped(1),
                    child: dashboardCard(
                      icon: Icons.attach_money_rounded,
                      title: _isLoading ? "..." : "₱${_salesData['totalSalesToday'].toStringAsFixed(2)}",
                      subtitle: "Sales Today",
                      extra: _salesChange,
                      color: Colors.orange.shade50,
                      extraColor: _salesChangeColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Running Low Inventory Section
            sectionTitle("Inventory Alert"),
            const SizedBox(height: 10),
            _isLoadingLowStock
                ? Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(child: CircularProgressIndicator()),
            )
                : _buildLowStockSummary(),

            const SizedBox(height: 20),

            // Recent Attendance Section (Replaces Packages/Shipment)
            sectionTitle("Employee Activity"),
            const SizedBox(height: 10),
            _buildAttendanceCard(),

            const SizedBox(height: 20),

            sectionTitle("Top Selling (Last 7 Days)"),
            const SizedBox(height: 10),
            buildTopSellingTable(),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.pink,
        unselectedItemColor: Colors.black54,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: "Dashboard"),
          BottomNavigationBarItem(icon: Icon(Icons.shopping_cart), label: "Sales"),
          BottomNavigationBarItem(icon: Icon(Icons.inventory), label: "Inventory"),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: "Report"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
        ],
      ),
    );
  }

  // ... (Keep all your existing helper methods: sectionTitle, dashboardCard, buildTopSellingTable)
  Widget sectionTitle(String title) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3)],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
    );
  }

  Widget dashboardCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String extra,
    required Color color,
    Color? extraColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.pink.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.pinkAccent),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Colors.black54)),
          Text(
            extra,
            style: TextStyle(
              color: extraColor ?? (extra.contains('-') ? Colors.red : Colors.green),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildTopSellingTable() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3)],
      ),
      child: Column(
        children: [
          Row(
            children: const [
              Expanded(flex: 2, child: Text("Name", style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(child: Text("Sold", style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(child: Text("Price", style: TextStyle(fontWeight: FontWeight.bold))),
            ],
          ),
          const Divider(),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_topSelling.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('No sales data available', style: TextStyle(color: Colors.grey)),
            )
          else
            ..._topSelling.map((item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      item['name']?.toString() ?? 'Unknown Product',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${item['quantity'] ?? 0}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '₱${(item['price'] ?? 0).toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            )).toList(),
        ],
      ),
    );
  }
}