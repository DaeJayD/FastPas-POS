import 'package:vasenizzpos/core/management_ui.dart';
import 'package:vasenizzpos/core/store_connection.dart';
import 'package:vasenizzpos/core/fastpas_theme.dart';
import 'package:flutter/material.dart';

class ActivityLogsPage extends StatefulWidget {
  const ActivityLogsPage({super.key, required List<Map<String, String>> logs});

  @override
  State<ActivityLogsPage> createState() => _ActivityLogsPageState();
}

class _ActivityLogsPageState extends State<ActivityLogsPage> {
  final supabase = StoreConnection.client;
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;

  // Filter states
  String _selectedActivity = "All activity";
  String _selectedTime = "All Time";
  String _searchQuery = "";

  final List<String> _activityOptions = [
    "All activity",
    "Sold",
    "Stock In",
    "Stock Out",
    "Updated",
    "Low Stock",
  ];

  final List<String> _timeOptions = [
    "All Time",
    "Today",
    "This Week",
    "This Month",
  ];

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);

    try {
      // Load inventory movements and sales in parallel
      final [inventoryMovements, salesData] = await Future.wait([
        _loadInventoryMovements(),
        _loadSalesData(),
      ]);

      // Combine and sort all activities by date
      final allLogs = [...inventoryMovements, ...salesData];
      allLogs.sort((a, b) => b['created_at'].compareTo(a['created_at']));

      setState(() {
        _logs = allLogs;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading logs: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _loadInventoryMovements() async {
    final response = await supabase
        .from('inventory_movements')
        .select('''
          *,
          products(name, brand_id),
          branches(name),
          employees(name)
        ''')
        .order('created_at', ascending: false)
        .limit(100);

    final movements = List<Map<String, dynamic>>.from(response);

    // Convert to log format
    return movements.map((movement) {
      return {
        'id': movement['id'],
        'type': 'inventory_movement',
        'created_at': movement['created_at'],
        'user_id': movement['user_id'],
        'employee_name': _getEmployeeName(movement),
        'movement_type': movement['movement_type'],
        'quantity': movement['quantity'],
        'product_name': _getProductName(movement),
        'branch_name': _getBranchName(movement),
        'previous_stock': movement['previous_stock'],
        'new_stock': movement['new_stock'],
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _loadSalesData() async {
    // First get sales with their items
    final salesResponse = await supabase
        .from('sales')
        .select('''
          *,
          sale_items(
            quantity,
            unit_price,
            total_price,
            products(name, brand_id)
          )
        ''')
        .order('created_at', ascending: false)
        .limit(100);

    final sales = List<Map<String, dynamic>>.from(salesResponse);

    // Convert sales to log format
    final salesLogs = <Map<String, dynamic>>[];

    for (final sale in sales) {
      final saleItems = List<Map<String, dynamic>>.from(
        sale['sale_items'] ?? [],
      );

      // Create one log entry per sold item
      for (final item in saleItems) {
        final productData = item['products'] is Map ? item['products'] : {};

        salesLogs.add({
          'id': 'sale_${sale['id']}_${item['id']}',
          'type': 'sale',
          'created_at': sale['created_at'],
          'user_id': null, // Sales don't have user_id, use cashier_name
          'employee_name': sale['cashier_name'],
          'movement_type': 'sale',
          'quantity': item['quantity'],
          'product_name': productData['name'] ?? 'Unknown Product',
          'branch_name': sale['branch_location'],
          'total_amount': item['total_price'],
          'sale_id': sale['id'],
        });
      }

      // Also create a summary log for the entire sale
      if (saleItems.isNotEmpty) {
        salesLogs.add({
          'id': 'sale_summary_${sale['id']}',
          'type': 'sale_summary',
          'created_at': sale['created_at'],
          'user_id': null,
          'employee_name': sale['cashier_name'],
          'movement_type': 'sale_completed',
          'quantity': saleItems.length,
          'product_name': 'Multiple Products',
          'branch_name': sale['branch_location'],
          'total_amount': sale['total_amount'],
          'sale_id': sale['id'],
          'item_count': saleItems.length,
        });
      }
    }

    return salesLogs;
  }

  String _getActionDescription(Map<String, dynamic> log) {
    final movementType = log['movement_type'];
    final quantity = log['quantity'] ?? 0;
    final productName = log['product_name'] ?? 'Unknown Product';
    final branchName = log['branch_name'] ?? 'Unknown Branch';

    switch (movementType) {
      case 'sale':
        return 'Sold $quantity units of $productName at $branchName for ₱${(log['total_amount'] ?? 0).toStringAsFixed(2)}';
      case 'sale_completed':
        final itemCount = log['item_count'] ?? 0;
        return 'Completed sale with $itemCount items at $branchName for ₱${(log['total_amount'] ?? 0).toStringAsFixed(2)}';
      case 'stock_in':
        return 'Added $quantity units of $productName to $branchName';
      case 'stock_out':
        return 'Removed $quantity units of $productName from $branchName';
      case 'stock_adjustment':
        return 'Adjusted stock by $quantity units for $productName at $branchName';
      case 'low_stock_alert':
        return 'Low stock alert for $productName at $branchName (${log['new_stock']} units remaining)';
      default:
        return '${movementType.replaceAll('_', ' ')}: $productName';
    }
  }

  String _getActionType(Map<String, dynamic> log) {
    final movementType = log['movement_type'];

    switch (movementType) {
      case 'sale':
      case 'sale_completed':
        return 'Sale';
      case 'stock_in':
        return 'Stock In';
      case 'stock_out':
        return 'Stock Out';
      case 'stock_adjustment':
        return 'Update';
      case 'low_stock_alert':
        return 'Low Stock';
      default:
        return movementType.replaceAll('_', ' ');
    }
  }

  String _getEmployeeName(Map<String, dynamic> log) {
    // For inventory movements
    if (log['employee_name'] != null) {
      return log['employee_name'];
    }

    // For sales (use cashier_name)
    if (log['type'] == 'sale' || log['type'] == 'sale_summary') {
      return log['employee_name'] ?? 'Unknown Cashier';
    }

    return 'System';
  }

  String _getProductName(Map<String, dynamic> log) {
    return log['product_name'] ?? 'Unknown Product';
  }

  String _getBranchName(Map<String, dynamic> log) {
    return log['branch_name'] ?? 'Unknown Branch';
  }

  String _formatTime(DateTime date) {
    // Always return exact time in 12-hour format with AM/PM
    final hour = date.hour % 12;
    final hourDisplay = hour == 0 ? 12 : hour;
    final amPm = date.hour < 12 ? 'AM' : 'PM';
    final minute = date.minute.toString().padLeft(2, '0');

    return '${date.month}/${date.day}/${date.year} $hourDisplay:$minute $amPm';
  }

  // Filter logs based on search query and activity type
  List<Map<String, dynamic>> get _filteredLogs {
    var filtered = _logs;

    // Apply activity filter
    if (_selectedActivity != "All activity") {
      filtered = filtered.where((log) {
        switch (_selectedActivity) {
          case "Sold":
            return log['movement_type'] == 'sale' ||
                log['movement_type'] == 'sale_completed';
          case "Stock In":
            return log['movement_type'] == 'stock_in';
          case "Stock Out":
            return log['movement_type'] == 'stock_out';
          case "Low Stock":
            return log['movement_type'] == 'low_stock_alert';
          case "Updated":
            return log['movement_type'] == 'stock_adjustment';
          default:
            return true;
        }
      }).toList();
    }

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((log) {
        final employeeName = _getEmployeeName(log).toLowerCase();
        final productName = _getProductName(log).toLowerCase();
        final description = _getActionDescription(log).toLowerCase();
        final branchName = _getBranchName(log).toLowerCase();

        return employeeName.contains(_searchQuery.toLowerCase()) ||
            productName.contains(_searchQuery.toLowerCase()) ||
            description.contains(_searchQuery.toLowerCase()) ||
            branchName.contains(_searchQuery.toLowerCase());
      }).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: Column(
        children: [
          // Header with Back Button
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(
              top: 50,
              bottom: 20,
              left: 20,
              right: 20,
            ),
            decoration: BoxDecoration(
              color: Volt.soft,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                    size: 28,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 10),
                // Logo matching inventory page - updated
                const CircleAvatar(
                  radius: 25,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.bolt_rounded, color: Volt.ink),
                ),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Activity Logs",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        "System Activity History",
                        style: TextStyle(fontSize: 16, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Volt.ink, size: 28),
                  onPressed: _loadLogs,
                ),
              ],
            ),
          ),

          // Search & Filters
          Padding(
            padding: const EdgeInsets.all(15.0),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: "Search by user, product, branch, or action",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
                const SizedBox(height: 10),
                ManagementColumns(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _selectedActivity,
                        items: _activityOptions
                            .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)),
                            )
                            .toList(),
                        onChanged: (value) => setState(() {
                          _selectedActivity = value!;
                          _loadLogs();
                        }),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _selectedTime,
                        items: _timeOptions
                            .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)),
                            )
                            .toList(),
                        onChanged: (value) => setState(() {
                          _selectedTime = value!;
                          _loadLogs();
                        }),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Logs Table
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredLogs.isEmpty
                ? const Center(
                    child: Text(
                      "No activity logs found",
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(Volt.soft),
                          columns: const [
                            DataColumn(label: Text('Time')),
                            DataColumn(label: Text('User')),
                            DataColumn(label: Text('Action')),
                            DataColumn(label: Text('Description')),
                            DataColumn(label: Text('Branch')),
                          ],
                          rows: _filteredLogs.asMap().entries.map((entry) {
                            final index = entry.key;
                            final log = entry.value;
                            final createdAt = DateTime.parse(log['created_at']);

                            return DataRow(
                              color: WidgetStateProperty.resolveWith<Color?>(
                                (Set<WidgetState> states) => index % 2 == 0
                                    ? Colors.white
                                    : Colors.grey[100],
                              ),
                              cells: [
                                DataCell(Text(_formatTime(createdAt))),
                                DataCell(Text(_getEmployeeName(log))),
                                DataCell(Text(_getActionType(log))),
                                DataCell(Text(_getActionDescription(log))),
                                DataCell(Text(_getBranchName(log))),
                              ],
                            );
                          }).toList(),
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
