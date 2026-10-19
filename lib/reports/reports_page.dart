import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'generate_report_page.dart';
import 'package:vasenizzpos/dashboard/home_screen.dart';
import 'package:vasenizzpos/sales/sales_screen.dart';
import 'package:vasenizzpos/inventory/inventory_screen.dart';
import 'package:vasenizzpos/users/users_page.dart';
import 'logs.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ViewReportsPage extends StatefulWidget {
  final String fullName;
  final String role;
  final String userId;
  final String location;
  final int initialIndex;

  const ViewReportsPage({
    required this.fullName,
    required this.role,
    required this.userId,
    required this.location,
    this.initialIndex = 3,
    super.key,
  });

  @override
  State<ViewReportsPage> createState() => _ViewReportsPageState();
}

class _ViewReportsPageState extends State<ViewReportsPage> {
  late int _selectedIndex;
  String selectedRange = "1W";
  final supabase = Supabase.instance.client;

  // Real data state variables
  Map<String, dynamic> _salesData = {
    'totalSales': 0.0,
    'previousPeriodSales': 0.0,
    'salesChange': 0.0,
    'salesHistory': [],
    'totalOrders': 0,
  };
  List<Map<String, dynamic>> _topSellingProducts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _loadReportData();
  }

  Future<void> _loadReportData() async {
    setState(() => _isLoading = true);

    try {
      await Future.wait([
        _loadSalesData(),
        _loadTopSellingProducts(),
      ]);
    } catch (e) {
      print('Error loading report data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSalesData() async {
    try {
      final today = DateTime.now();
      DateTime startDate;
      DateTime endDate = DateTime.now();

      // Set date range based on selection
      switch (selectedRange) {
        case "1D":
          startDate = DateTime(today.year, today.month, today.day);
          break;
        case "1W":
          startDate = today.subtract(const Duration(days: 7));
          break;
        case "1M":
          startDate = DateTime(today.year, today.month - 1, today.day);
          break;
        case "3M":
          startDate = DateTime(today.year, today.month - 3, today.day);
          break;
        case "6M":
          startDate = DateTime(today.year, today.month - 6, today.day);
          break;
        case "1Yr":
          startDate = DateTime(today.year - 1, today.month, today.day);
          break;
        default:
          startDate = today.subtract(const Duration(days: 7));
      }

      // Get total sales for current period
      final salesResponse = await supabase
          .from('sales')
          .select('total_amount, created_at')
          .gte('created_at', startDate.toIso8601String())
          .lte('created_at', endDate.toIso8601String());

      final sales = List<Map<String, dynamic>>.from(salesResponse);

      // Previous period
      final previousStartDate = startDate.subtract(endDate.difference(startDate));
      final previousEndDate = startDate.subtract(const Duration(seconds: 1));

      final previousSalesResponse = await supabase
          .from('sales')
          .select('total_amount')
          .gte('created_at', previousStartDate.toIso8601String())
          .lte('created_at', previousEndDate.toIso8601String());

      final previousSales = List<Map<String, dynamic>>.from(previousSalesResponse);

      // Calculate totals
      double totalSales = 0.0;
      double previousTotalSales = 0.0;

      for (final sale in sales) {
        totalSales += (sale['total_amount'] ?? 0.0);
      }

      for (final sale in previousSales) {
        previousTotalSales += (sale['total_amount'] ?? 0.0);
      }

      // Calculate percentage change
      double salesChange = 0.0;
      if (previousTotalSales > 0) {
        salesChange = ((totalSales - previousTotalSales) / previousTotalSales) * 100;
      } else if (totalSales > 0) {
        salesChange = 100.0;
      }

      // Get sales history (last 7 days)
      final List<FlSpot> salesHistory = [];
      for (int i = 6; i >= 0; i--) {
        final day = today.subtract(Duration(days: i));
        final dayStart = DateTime(day.year, day.month, day.day);
        final dayEnd = DateTime(day.year, day.month, day.day, 23, 59, 59);

        final daySalesResponse = await supabase
            .from('sales')
            .select('total_amount')
            .gte('created_at', dayStart.toIso8601String())
            .lte('created_at', dayEnd.toIso8601String());

        final daySales = List<Map<String, dynamic>>.from(daySalesResponse);
        double dayTotal = 0.0;
        for (final sale in daySales) {
          dayTotal += (sale['total_amount'] ?? 0.0);
        }

        salesHistory.add(FlSpot((6 - i).toDouble(), dayTotal.toDouble()));
      }

      setState(() {
        _salesData = {
          'totalSales': totalSales,
          'previousPeriodSales': previousTotalSales,
          'salesChange': salesChange,
          'salesHistory': salesHistory,
          'totalOrders': sales.length,
        };
      });
    } catch (e) {
      print('Error loading sales data: $e');
    }
  }

  Future<void> _loadTopSellingProducts() async {
    try {
      final today = DateTime.now();
      final weekAgo = today.subtract(const Duration(days: 7));

      final response = await supabase
          .from('sale_items')
          .select('''
            product_id, 
            quantity, 
            products(name, price)
          ''')
          .gte('created_at', weekAgo.toIso8601String());

      final saleItems = List<Map<String, dynamic>>.from(response);

      // Aggregate product sales
      final productSales = <String, Map<String, dynamic>>{};
      for (final item in saleItems) {
        final productId = item['product_id'].toString();
        final product = item['products'] ?? {};
        final productName = product['name'] ?? 'Unknown Product';
        final quantity = item['quantity'] ?? 0;

        if (productSales.containsKey(productId)) {
          productSales[productId]!['quantity'] += quantity;
        } else {
          productSales[productId] = {
            'name': productName,
            'quantity': quantity,
            'price': product['price'] ?? 0.0,
          };
        }
      }

      final topSellingList = productSales.values.toList();
      topSellingList.sort((a, b) => (b['quantity'] ?? 0).compareTo(a['quantity'] ?? 0));

      setState(() {
        _topSellingProducts = topSellingList.take(4).toList();
      });
    } catch (e) {
      print('Error loading top selling products: $e');
    }
  }

  void _onNavTapped(int index) {
    if (index == _selectedIndex) return;

    Widget target;
    switch (index) {
      case 0:
        target = HomeScreen(
          fullName: widget.fullName,
          role: widget.role,
          userId: widget.userId,
          location: widget.location,
          initialIndex: 0,
        );
        break;
      case 1:
        target = SalesScreen(
          fullName: widget.fullName,
          role: widget.role,
          userId: widget.userId,
          location: widget.location,
        );
        break;
      case 2:
        target = InventoryPage(
          fullName: widget.fullName,
          role: widget.role,
          userId: widget.userId,
          location: widget.location,
        );
        break;
      case 3:
        target = ViewReportsPage(
          fullName: widget.fullName,
          role: widget.role,
          userId: widget.userId,
          location: widget.location,
        );
        break;
      case 4:
        target = UsersPage(
          fullName: widget.fullName,
          role: widget.role,
          userId: widget.userId,
          location: widget.location,
        );
        break;
      default:
        target = ViewReportsPage(
          fullName: widget.fullName,
          role: widget.role,
          userId: widget.userId,
          location: widget.location,
        );
    }

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => target,
        transitionDuration: Duration.zero,
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8EDF3), // Same as inventory page
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5C6D3), // Same pink as inventory
        elevation: 0, // Normal height like inventory
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
                Text("Reports Page",
                    style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text("${widget.fullName} (${widget.role})",
                    style: const TextStyle(fontSize: 13, color: Colors.black54)),
              ],
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ActivityLogsPage(logs: [],),
                  ),
                );
              },
              icon: const Icon(Icons.article_outlined,
                  size: 16, color: Colors.black),
              label: const Text("Logs",
                  style: TextStyle(color: Colors.black, fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
            ),
            const SizedBox(width: 10),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white, size: 28),
              onPressed: _loadReportData,
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // UNIFORM BUTTONS
            Row(
              children: [
                Expanded(
                  child: _tabButton("Analytics Dashboard", true),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _tabButton("Generate Report", false, onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const GenerateReportPage()),
                    );
                  }),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text("Sales Overview",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    fontFamily: "Poppins")),
            const Divider(thickness: 1),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _statCard(
                    Icons.store,
                    _salesData['totalOrders'].toString(),
                    "Total Orders",
                    const Color(0xFFFAC7D0)),
                _statCard(
                    Icons.attach_money,
                    "₱${_salesData['totalSales'].toStringAsFixed(2)}",
                    "In-Store Total Sales",
                    const Color(0xFFD2C6FC)),
              ],
            ),
            const SizedBox(height: 25),
            Center(
              child: Wrap(
                spacing: 6,
                children: ["1D", "1W", "1M", "3M", "6M", "1Yr"]
                    .map((r) => ChoiceChip(
                  label: Text(r),
                  selected: selectedRange == r,
                  selectedColor: const Color(0xFFD2C6FC),
                  onSelected: (_) {
                    setState(() => selectedRange = r);
                    _loadReportData(); // Reload data when range changes
                  },
                ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 25),
            const Text("Revenue",
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 5),
            Row(
              children: [
                Text("₱${_salesData['totalSales'].toStringAsFixed(2)}",
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87)),
                const SizedBox(width: 10),
                Chip(
                  label: Text(
                      "${_salesData['salesChange'] >= 0 ? '+' : ''}${_salesData['salesChange'].toStringAsFixed(1)}%"),
                  backgroundColor: _salesData['salesChange'] >= 0
                      ? const Color(0xFFD8F9D4)
                      : const Color(0xFFFFE0E0),
                  labelStyle: TextStyle(
                    color: _salesData['salesChange'] >= 0
                        ? Colors.green
                        : Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildLineChart(),
            const SizedBox(height: 30),
            const Text("Top Selling Products",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    fontFamily: "Poppins")),
            const Divider(thickness: 1),
            const SizedBox(height: 15),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.5,
              children: _topSellingProducts
                  .map((product) => _topSellingProductCard(
                  product['name'] ?? 'Unknown',
                  product['quantity'].toString()))
                  .toList(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onNavTapped,
        selectedItemColor: Colors.pink,
        unselectedItemColor: Colors.black54,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: "Dashboard"),
          BottomNavigationBarItem(icon: Icon(Icons.shopping_cart), label: "Sales"),
          BottomNavigationBarItem(icon: Icon(Icons.inventory), label: "Inventory"),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: "Report"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
        ],
      ),
    );
  }

  Widget _buildLineChart() {
    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  const days = ["M", "T", "W", "T", "F", "S", "S"];
                  return value.toInt() < days.length ? Text(days[value.toInt()]) : Text("");
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: _salesData['salesHistory'] ?? [FlSpot(0, 0)],
              color: const Color(0xFF9C89E9),
              barWidth: 3,
              isCurved: true,
              belowBarData: BarAreaData(
                show: true,
                color: const Color(0xFF9C89E9).withOpacity(0.2),
              ),
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topSellingProductCard(String productName, String salesCount) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFFF8C8D9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.inventory_2, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(productName,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.arrow_upward, color: Colors.green, size: 16),
              Text(salesCount,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const Text(" sold", style: TextStyle(fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tabButton(String label, bool active, {VoidCallback? onTap}) {
    return ElevatedButton(
      onPressed: onTap ?? () {},
      style: ElevatedButton.styleFrom(
        backgroundColor: active ? const Color(0xFFD8D0D0) : Colors.grey.shade200,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? Colors.black : Colors.grey,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _statCard(IconData icon, String value, String label, Color bgColor) {
    return Container(
      width: 150,
      height: 100,
      decoration:
      BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.black54, size: 28),
          const SizedBox(height: 8),
          Text(value,
              style:
              const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
