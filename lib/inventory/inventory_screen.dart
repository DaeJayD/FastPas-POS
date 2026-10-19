import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vasenizzpos/branches/jasaan_branch.dart';
import 'package:vasenizzpos/branches/puerto_branch.dart';
import 'package:vasenizzpos/inventory/inventory_history.dart';
import 'package:vasenizzpos/products/allproducts_screen.dart';
import 'package:vasenizzpos/dashboard/home_screen.dart';
import 'package:vasenizzpos/sales/sales_screen.dart';
import 'package:vasenizzpos/reports/reports_page.dart';
import 'package:vasenizzpos/users/users_page.dart';
import 'package:vasenizzpos/branches/carmen_branch.dart';
import 'package:vasenizzpos/suppliers/suppliers_creen.dart';

class InventoryPage extends StatefulWidget {
  final String fullName;
  final String role;
  final String userId;
  final String location;
  final int initialIndex;

  const InventoryPage({
    required this.fullName,
    required this.role,
    required this.userId,
    required this.location,
    this.initialIndex = 2,
    super.key,
  });

  @override
  State<InventoryPage> createState() => _InventoryScreenPageState();
}

class _InventoryScreenPageState extends State<InventoryPage> {
  late int _selectedIndex;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  final SupabaseClient _supabase = Supabase.instance.client;

  List<dynamic> _lowStockItems = [];
  List<dynamic> _calendarEvents = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _initializeData();
  }

  Future<void> _initializeData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load all branches data
      await Future.wait([
        _loadAllBranchesLowStock(),
        _loadAllBranchesCalendarEvents(),
      ]);
    } catch (e) {
      _showErrorSnackbar('Failed to load data');
    }

    setState(() {
      _isLoading = false;
    });
  }

  void _showAddEventDialog(DateTime selectedDate) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Events for ${_formatDate(selectedDate)}'),
        content: AddEventForm(
          selectedDate: selectedDate,
          branchId: null,
          userId: widget.userId,
          onEventAdded: () {
            _loadAllBranchesCalendarEvents(); // Refresh events
          },
          onEventRemoved: () {
            _loadAllBranchesCalendarEvents(); // Refresh events
          },
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  List<dynamic> _getEventsForDay(DateTime day) {
    return _calendarEvents.where((event) {
      final eventDate = DateTime.parse(event['event_date']);
      return isSameDay(eventDate, day);
    }).toList();
  }

  Future<void> _loadAllBranchesLowStock() async {
    try {
      // Get low stock items from all branches
      final stockResult = await _supabase
          .from('branch_stock')
          .select('''
            *,
            products(
              name,
              sku,
              brands(name)
            ),
            branches(name)
          ''');

      final lowStockItems = stockResult.where((item) {
        final currentStock = item['current_stock'] ?? 0;
        final threshold = item['low_stock_threshold'] ?? 10;
        return currentStock <= threshold;
      }).toList();

      setState(() {
        _lowStockItems = lowStockItems;
      });
    } catch (e) {
      setState(() {
        _lowStockItems = [];
      });
    }
  }

  Future<void> _loadAllBranchesCalendarEvents() async {
    try {
      final result = await _supabase
          .from('calendar_events')
          .select('*')
          .gte('event_date', DateTime.now().toIso8601String())
          .order('event_date');

      setState(() {
        _calendarEvents = result;
      });
    } catch (e) {
      setState(() {
        _calendarEvents = [];
      });
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

  void _showBranchSelector(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "SELECT BRANCH",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.pink,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 20),

              _branchButton(
                context,
                icon: Icons.home,
                label: "CARMEN BRANCH",
                color: Colors.pink[300]!,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context, MaterialPageRoute(
                      builder: (context) => CarmenScreen(
                        fullName: widget.fullName,
                        role: widget.role,
                        userId: widget.userId,
                        location: widget.location,)
                  ),
                  );
                },
              ),

              const SizedBox(height: 10),

              _branchButton(
                context,
                icon: Icons.home,
                label: "PUERTO BRANCH",
                color: Colors.pink[200]!,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PuertoScreen(
                        fullName: widget.fullName,
                        role: widget.role,
                        userId: widget.userId,
                        location: widget.location,
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 10),

              _branchButton(
                context,
                icon: Icons.home,
                label: "JASAAN BRANCH",
                color: Colors.pink[100]!,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => JasaanScreen(
                        fullName: widget.fullName,
                        role: widget.role,
                        userId: widget.userId,
                        location: widget.location,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _branchButton(
      BuildContext context, {
        required IconData icon,
        required String label,
        required Color color,
        required VoidCallback onTap,
      }) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, color: Colors.white),
      label: Text(label,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _onItemTapped(int index) {
    if (index == _selectedIndex) return;

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
          initialIndex: 1,
        );
        break;

      case 2:
        nextPage = InventoryPage(
          fullName: widget.fullName,
          role: widget.role,
          userId: widget.userId,
          location: widget.location,
          initialIndex: 2,
        );
        break;

      case 3:
        nextPage = ViewReportsPage(
          fullName: widget.fullName,
          role: widget.role,
          userId: widget.userId,
          location: widget.location,

          initialIndex: 3,
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
        pageBuilder: (context, a, b) => nextPage,
        transitionDuration: Duration.zero,
      ),
    );
  }

  Widget _buildLowStockAlert() {
    final hasLowStock = _lowStockItems.isNotEmpty;
    final alertColor = hasLowStock ? Colors.red : Colors.green;
    final alertText = hasLowStock ? "LOW STOCK ALERT" : "STOCK STATUS";

    // Group low stock items by branch
    final branchLowStock = <String, int>{};
    final productNames = <String>[];

    for (final item in _lowStockItems.take(3)) {
      final branch = item['branches']?['name'] ?? 'Unknown Branch';
      branchLowStock[branch] = (branchLowStock[branch] ?? 0) + 1;

      final product = item['products'] ?? {};
      final productName = product['name'] ?? 'Unknown Product';
      if (productNames.length < 2) {
        productNames.add(productName);
      }
    }

    String lowStockProductNames = "All items stocked";
    if (hasLowStock) {
      lowStockProductNames = productNames.join('\n');
      if (productNames.length < _lowStockItems.length) {
        lowStockProductNames += '\n+ ${_lowStockItems.length - productNames.length} more';
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4)
        ],
      ),
      child: Column(
        children: [
          Text(
            alertText,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: alertColor,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          Icon(
            Icons.inventory_rounded,
            color: alertColor,
            size: 40,
          ),
          const SizedBox(height: 5),
          Text(
            "${_lowStockItems.length}",
            style: TextStyle(
              color: alertColor,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            lowStockProductNames,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: hasLowStock ? Colors.black54 : alertColor,
              fontSize: 13,
            ),
          ),
          if (branchLowStock.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              "Across ${branchLowStock.length} branch${branchLowStock.length == 1 ? '' : 'es'}",
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.orange,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCalendar() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: TableCalendar(
        firstDay: DateTime.utc(2020, 1, 1),
        lastDay: DateTime.utc(2030, 12, 31),
        focusedDay: _focusedDay,
        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
        onDaySelected: (selectedDay, focusedDay) {
          setState(() {
            _selectedDay = selectedDay;
            _focusedDay = focusedDay;
          });
          _showAddEventDialog(selectedDay);
        },
        eventLoader: _getEventsForDay,
        headerStyle: const HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          titleTextStyle: TextStyle(fontWeight: FontWeight.bold, color: Colors.pink),
        ),
        calendarStyle: CalendarStyle(
          todayDecoration: BoxDecoration(
            color: Colors.pink.shade200,
            shape: BoxShape.circle,
          ),
          selectedDecoration: BoxDecoration(
            color: Colors.pink.shade400,
            shape: BoxShape.circle,
          ),
          markerDecoration: BoxDecoration(
            color: Colors.pink,
            shape: BoxShape.circle,
          ),
          markersAlignment: Alignment.bottomCenter,
          markersMaxCount: 3,
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
        title: Row(
          children: [
            const CircleAvatar(
              radius: 24,
              backgroundImage: AssetImage("assets/logo.png"),
              backgroundColor: Colors.white,
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("All Branches Inventory",
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.black87)),
                Text("${widget.fullName} (${widget.role})",
                    style: const TextStyle(fontSize: 13, color: Colors.black54)),
              ],
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.notifications_none_rounded,
                  color: Colors.white, size: 26),
              onPressed: () {},
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _initializeData,
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.pink))
          : Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      _actionButton("Branch Inventory", Icons.inventory_2_outlined,
                          Color(0xFFD1828B), onPressed: () => _showBranchSelector(context)),
                      const SizedBox(height: 10),
                      _actionButton("Inventory History", Icons.history,
                          Color(0xFFD1828B), onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => InventoryHistoryScreen(
                                  fullName: widget.fullName,
                                  role: widget.role,
                                  userId: widget.userId,
                                ),
                              ),
                            );
                          }),
                      const SizedBox(height: 10),
                      _actionButton("View All Products", Icons.list_alt,
                          Color(0xFFD1828B), onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AllProductsInventoryScreen(
                                  fullName: widget.fullName,
                                  role: widget.role,
                                ),
                              ),
                            );
                          }),
                      const SizedBox(height: 10),
                      _actionButton("Suppliers", Icons.local_shipping,
                          Color(0xFFD1828B), onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => SuppliersScreen(
                                  fullName: widget.fullName,
                                  role: widget.role,
                                  userId: widget.userId,
                                ),
                              ),
                            );
                          }),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: _buildLowStockAlert(),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _buildCalendar(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.pink,
        unselectedItemColor: Colors.black54,
        onTap: _onItemTapped,
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
  Widget _actionButton(String label, IconData icon, Color color,
      {VoidCallback? onPressed}) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: Colors.white),
      label: Text(label,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        minimumSize: const Size(double.infinity, 70),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class AddEventForm extends StatefulWidget {
  final DateTime selectedDate;
  final String? branchId;
  final String userId;
  final VoidCallback onEventAdded;
  final VoidCallback onEventRemoved;

  const AddEventForm({
    super.key,
    required this.selectedDate,
    this.branchId,
    required this.userId,
    required this.onEventAdded,
    required this.onEventRemoved,
  });

  @override
  State<AddEventForm> createState() => _AddEventFormState();
}

class _AddEventFormState extends State<AddEventForm> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isLoading = false;
  String? _selectedBranchId;
  List<Map<String, dynamic>> _branches = [];
  List<dynamic> _existingEvents = [];

  @override
  void initState() {
    super.initState();
    _loadBranches();
    _loadExistingEvents();
  }

  Future<void> _loadBranches() async {
    try {
      final result = await _supabase
          .from('branches')
          .select('id, name')
          .order('name');

      setState(() {
        _branches = List<Map<String, dynamic>>.from(result);
        if (_branches.isNotEmpty) {
          _selectedBranchId = _branches.first['id'] as String?;
        }
      });
    } catch (e) {
      print('Error loading branches: $e');
    }
  }

  Future<void> _loadExistingEvents() async {
    try {
      final result = await _supabase
          .from('calendar_events')
          .select('*')
          .eq('event_date', widget.selectedDate.toIso8601String().split('T')[0])
          .order('created_at');

      setState(() {
        _existingEvents = result;
      });
    } catch (e) {
      print('Error loading existing events: $e');
    }
  }

  Future<void> _addEvent() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedBranchId == null && _branches.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a branch'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _supabase.from('calendar_events').insert({
        'branch_id': _selectedBranchId,
        'event_date': widget.selectedDate.toIso8601String().split('T')[0],
        'event_type': 'custom',
        'description': _descriptionController.text.trim(),
        'created_by': widget.userId,
      });

      if (!mounted) return;

      Navigator.pop(context);
      widget.onEventAdded();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Event added successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error adding event: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _removeEvent(String eventId) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _supabase
          .from('calendar_events')
          .delete()
          .eq('id', eventId);

      if (!mounted) return;

      // Reload existing events
      await _loadExistingEvents();
      widget.onEventRemoved();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Event removed successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error removing event: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showDeleteConfirmation(String eventId, String description) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Event'),
        content: Text('Are you sure you want to remove "$description"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _removeEvent(eventId);
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.maxFinite,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Existing Events Section
            if (_existingEvents.isNotEmpty) ...[
              const Text(
                'Existing Events:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              ..._existingEvents.map((event) => Card(
                color: Colors.grey[50],
                child: ListTile(
                  title: Text(
                    event['description'] ?? 'No description',
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    'Branch: ${_getBranchName(event['branch_id'])}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: _isLoading ? null : () => _showDeleteConfirmation(
                      event['id'],
                      event['description'] ?? 'this event',
                    ),
                  ),
                ),
              )).toList(),
              const Divider(),
              const SizedBox(height: 10),
            ],

            // Add New Event Section
            const Text(
              'Add New Event:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),

            // Branch Selection Dropdown
            if (_branches.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                value: _selectedBranchId,
                decoration: const InputDecoration(
                  labelText: 'Select Branch',
                  border: OutlineInputBorder(),
                ),
                items: _branches.map<DropdownMenuItem<String>>((branch) {
                  return DropdownMenuItem<String>(
                    value: branch['id'] as String?,
                    child: Text(branch['name'] as String),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedBranchId = value;
                  });
                },
                validator: (value) {
                  if (value == null && _branches.isNotEmpty) {
                    return 'Please select a branch';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
            ],

            // Description Field
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Event Description',
                border: OutlineInputBorder(),
                hintText: 'e.g., Shipment arriving, Product expiry, Meeting, etc.',
              ),
              maxLines: 3,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter event description';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _addEvent,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.pink,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                        : const Text('Add Event', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getBranchName(String? branchId) {
    if (branchId == null) return 'All Branches';
    final branch = _branches.firstWhere(
          (b) => b['id'] == branchId,
      orElse: () => {'name': 'Unknown Branch'},
    );
    return branch['name'] as String;
  }
}