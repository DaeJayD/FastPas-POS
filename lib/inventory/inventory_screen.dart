import '../branches/branch_repository.dart';
import '../branches/branch_screen.dart';
import '../catalog/catalog_source.dart';

import 'package:vasenizzpos/core/management_ui.dart';
import 'package:vasenizzpos/core/store_connection.dart';
import 'package:vasenizzpos/core/fastpas_theme.dart';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vasenizzpos/inventory/inventory_history.dart';
import 'package:vasenizzpos/products/allproducts_screen.dart';
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
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  final SupabaseClient _supabase = StoreConnection.client;

  List<dynamic> _lowStockItems = [];
  List<dynamic> _calendarEvents = [];
  bool _isLoading = true;

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
      final stockResult = await _supabase.from('branch_stock').select('''
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
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _showBranchSelector(BuildContext context) async {
    try {
      final branches = await BranchRepository().branches();
      if (!context.mounted) return;
      final branch = await showDialog<StoreBranch>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Select branch'),
          content: SizedBox(
            width: 420,
            height: 300,
            child: branches.isEmpty
                ? const Center(child: Text('No branches found'))
                : ListView(
                    children: [
                      for (final branch in branches)
                        ListTile(
                          leading: const Icon(Icons.storefront_outlined),
                          title: Text(branch.name),
                          onTap: () => Navigator.pop(context, branch),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
      if (branch == null || !context.mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BranchScreen(
            fullName: widget.fullName,
            role: widget.role,
            userId: widget.userId,
            location: branch.location,
            branchName: branch.name,
            branch: branch,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        _showErrorSnackbar('Could not load branches. Please try again.');
      }
    }
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
        lowStockProductNames +=
            '\n+ ${_lowStockItems.length - productNames.length} more';
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
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
          Icon(Icons.inventory_rounded, color: alertColor, size: 40),
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
          titleTextStyle: TextStyle(
            fontWeight: FontWeight.bold,
            color: Volt.ink,
          ),
        ),
        calendarStyle: CalendarStyle(
          todayDecoration: BoxDecoration(
            color: Volt.ink,
            shape: BoxShape.circle,
          ),
          selectedDecoration: BoxDecoration(
            color: Volt.ink,
            shape: BoxShape.circle,
          ),
          markerDecoration: BoxDecoration(
            color: Volt.ink,
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
      backgroundColor: Volt.background,
      appBar: AppBar(
        title: ManagementTitle(
          'Branches & stock',
          subtitle: '${widget.fullName} · ${widget.role}',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _initializeData();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Volt.ink))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  ManagementColumns(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Column(
                          children: [
                            _actionButton(
                              "Branch Inventory",
                              Icons.inventory_2_outlined,
                              Volt.ink,
                              onPressed: () => _showBranchSelector(context),
                            ),
                            const SizedBox(height: 10),
                            _actionButton(
                              "Inventory History",
                              Icons.history,
                              Volt.ink,
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        InventoryHistoryScreen(
                                          fullName: widget.fullName,
                                          role: widget.role,
                                          userId: widget.userId,
                                        ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 10),
                            _actionButton(
                              "View All Products",
                              Icons.list_alt,
                              Volt.ink,
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        AllProductsInventoryScreen(
                                          fullName: widget.fullName,
                                          role: widget.role,
                                        ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 10),
                            _actionButton(
                              "Suppliers",
                              Icons.local_shipping,
                              Volt.ink,
                              onPressed: () {
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
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(flex: 2, child: _buildLowStockAlert()),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(height: 480, child: _buildCalendar()),
                ],
              ),
            ),
      bottomNavigationBar: null,
    );
  }

  Widget _actionButton(
    String label,
    IconData icon,
    Color color, {
    VoidCallback? onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: Colors.white),
      label: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
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
  final SupabaseClient _supabase = StoreConnection.client;
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
      debugPrint('Error loading branches: $e');
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
      debugPrint('Error loading existing events: $e');
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
      await _supabase.from('calendar_events').delete().eq('id', eventId);

      if (!mounted) return;

      // Reload existing events
      await _loadExistingEvents();
      widget.onEventRemoved();

      if (!mounted) return;
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
            style: TextButton.styleFrom(foregroundColor: Colors.red),
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
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 10),
              ..._existingEvents.map(
                (event) => Card(
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
                      onPressed: _isLoading
                          ? null
                          : () => _showDeleteConfirmation(
                              event['id'],
                              event['description'] ?? 'this event',
                            ),
                    ),
                  ),
                ),
              ),
              const Divider(),
              const SizedBox(height: 10),
            ],

            // Add New Event Section
            const Text(
              'Add New Event:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),

            // Branch Selection Dropdown
            if (_branches.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                initialValue: _selectedBranchId,
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
                hintText:
                    'e.g., Shipment arriving, Product expiry, Meeting, etc.',
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
                    style: ElevatedButton.styleFrom(backgroundColor: Volt.ink),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Text(
                            'Add Event',
                            style: TextStyle(color: Colors.white),
                          ),
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
