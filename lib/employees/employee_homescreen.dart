import 'package:flutter/material.dart';
import 'package:vasenizzpos/employees/employee_branch_sales_content.dart';
import 'package:vasenizzpos/employees/employee_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EmployeeHomeScreen extends StatefulWidget {
  final String fullName;
  final String role;
  final String userId;
  final String location;
  final int initialIndex;

  const EmployeeHomeScreen({
    required this.fullName,
    required this.role,
    required this.location,
    required this.userId,
    this.initialIndex = 0,
    super.key,
  });

  @override
  State<EmployeeHomeScreen> createState() => _EmployeeHomeScreenState();
}

class _EmployeeHomeScreenState extends State<EmployeeHomeScreen> {
  String? _userBranchLocation;
  Map<String, dynamic> _salesData = {
    'itemsSoldToday': 0,
    'totalSalesToday': 0.0,
    'totalSalesYesterday': 0.0,
  };
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserBranch();
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
          _userBranchLocation = response['branch'];
        });
        await _loadDashboardData();
      } else {
        // If no branch assigned, use location parameter
        setState(() {
          _userBranchLocation = widget.location;
        });
        await _loadDashboardData();
      }
    } catch (e) {
      print('Error fetching user branch: $e');
      setState(() {
        _userBranchLocation = widget.location;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);

    try {
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final yesterdayStart = todayStart.subtract(const Duration(days: 1));
      final yesterdayEnd = todayStart.subtract(const Duration(seconds: 1));

      // Get the actual branch name
      final branchName = _userBranchLocation ?? widget.location;

      // Get today's sales for THIS SPECIFIC BRANCH ONLY
      final todaySalesResponse = await Supabase.instance.client
          .from('sales')
          .select('''
        *,
        sale_items!inner(
          quantity,
          unit_price,
          total_price
        )
      ''')
          .eq('branch_location', branchName) // CRITICAL: Filter by branch
          .gte('created_at', todayStart.toIso8601String())
          .order('created_at', ascending: false);

      final todaySales = List<Map<String, dynamic>>.from(todaySalesResponse);

      // Get yesterday's sales for THIS SPECIFIC BRANCH ONLY
      final yesterdaySalesResponse = await Supabase.instance.client
          .from('sales')
          .select('''
        *,
        sale_items!inner(
          quantity,
          unit_price,
          total_price
        )
      ''')
          .eq('branch_location', branchName) // CRITICAL: Filter by branch
          .gte('created_at', yesterdayStart.toIso8601String())
          .lte('created_at', yesterdayEnd.toIso8601String())
          .order('created_at', ascending: false);

      final yesterdaySales = List<Map<String, dynamic>>.from(yesterdaySalesResponse);

      // Calculate today's data
      int itemsSoldToday = 0;
      double totalSalesToday = 0.0;

      for (final sale in todaySales) {
        totalSalesToday += (sale['total_amount'] ?? 0).toDouble();

        final saleItems = sale['sale_items'] as List?;
        if (saleItems != null) {
          for (final item in saleItems) {
            itemsSoldToday += (item['quantity'] as int? ?? 0);
          }
        }
      }

      // Calculate yesterday's total
      double totalSalesYesterday = 0.0;
      for (final sale in yesterdaySales) {
        totalSalesYesterday += (sale['total_amount'] ?? 0).toDouble();
      }

      setState(() {
        _salesData = {
          'itemsSoldToday': itemsSoldToday,
          'totalSalesToday': totalSalesToday,
          'totalSalesYesterday': totalSalesYesterday,
        };
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

  // Home Dashboard Content
  Widget _buildDashboard() {
    return Scaffold(
      backgroundColor: const Color(0xFFF8EDF3),
      body: SafeArea(
        child: Column(
          children: [
            // Welcome Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF5C6D3),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    backgroundImage: AssetImage('assets/logo.png'),
                    radius: 30,
                    backgroundColor: Colors.white,
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Welcome, ${widget.fullName}!",
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "${_userBranchLocation ?? widget.location} Branch • ${widget.role}",
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black54,
                          ),
                        ),
                        if (_isLoading)
                          const SizedBox(height: 4),
                        const Text(
                          "",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.black54),
                    onPressed: _loadDashboardData,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // Today's Performance Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Today's Performance",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 15),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Colors.pink.shade50, Colors.purple.shade50],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.pink.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        // Items Sold
                        Expanded(
                          child: Column(
                            children: [
                              Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.pink.withOpacity(0.2),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.shopping_basket,
                                  color: Colors.pink.shade400,
                                  size: 30,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                _isLoading ? "..." : "${_salesData['itemsSoldToday']}",
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const Text(
                                "Items Sold",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Vertical Divider
                        Container(
                          width: 1,
                          height: 60,
                          color: Colors.pink.shade200,
                        ),

                        // Total Sales
                        Expanded(
                          child: Column(
                            children: [
                              Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.purple.withOpacity(0.2),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.attach_money_rounded,
                                  color: Colors.purple.shade400,
                                  size: 30,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                _isLoading ? "..." : "₱${_salesData['totalSalesToday'].toStringAsFixed(2)}",
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              Text(
                                _salesChange,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _salesChangeColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // Branch Info Display
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.pink.shade100),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
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
                        color: Colors.pink.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.store,
                        color: Colors.pink,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Current Branch",
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          Text(
                            _userBranchLocation ?? widget.location,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Showing data for ${_userBranchLocation ?? widget.location} branch only",
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.verified,
                      color: Colors.green.shade400,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),

            // Quick Actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Quick Actions",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 15),

                  // Sales Card
                  _buildActionCard(
                    title: "Sales",
                    subtitle: "Process transactions and view sales history",
                    icon: Icons.point_of_sale,
                    iconColor: Colors.pink,
                    backgroundColor: Colors.pink.shade50,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EmployeeBranchSalesContent(
                            fullName: widget.fullName,
                            role: widget.role,
                            userId: widget.userId,
                            location: _userBranchLocation ?? widget.location,
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 15),

                  // Profile Card
                  _buildActionCard(
                    title: "Profile",
                    subtitle: "View and manage your account information",
                    icon: Icons.person,
                    iconColor: Colors.purple,
                    backgroundColor: Colors.purple.shade50,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => UserProfileScreen(
                            userId: widget.userId,
                            fullName: widget.fullName,
                            role: widget.role,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color backgroundColor,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 28,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: iconColor,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildDashboard();
  }
}