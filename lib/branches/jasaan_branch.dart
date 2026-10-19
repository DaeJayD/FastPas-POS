import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:vasenizzpos/inventory/branchinventory/jasaan_inventory.dart';
import 'package:vasenizzpos/branches/components/calendar_events.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class JasaanScreen extends StatefulWidget {
  final String fullName;
  final String role;
  final String location;
  final String userId;

  const JasaanScreen({
    super.key,
    required this.fullName,
    required this.role,
    required this.location,
    required this.userId,
  });

  @override
  State<JasaanScreen> createState() => _JasaanScreenState();
}

class _JasaanScreenState extends State<JasaanScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  final SupabaseClient _supabase = Supabase.instance.client;

  List<dynamic> _brands = [];
  List<dynamic> _lowStockItems = [];
  List<dynamic> _calendarEvents = [];
  bool _isLoading = true;
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
          .maybeSingle();

      if (branchResult != null) {
        _jasaanBranchId = branchResult['id'];
      }

      // Load all data in parallel
      await Future.wait([
        _loadBrands(),
        _loadLowStockItems(),
        _loadCalendarEvents(),
      ]);
    } catch (e) {
      _showErrorSnackbar('Failed to load data');
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadBrands() async {
    try {
      if (_jasaanBranchId == null) return;

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
      });
    } catch (e) {
      _showErrorSnackbar('Failed to load brands for Jasaan branch');
    }
  }

  Future<void> _loadLowStockItems() async {
    try {
      if (_jasaanBranchId == null) return;

      final stockResult = await _supabase
          .from('branch_stock')
          .select('''
            *,
            products(
              name,
              sku,
              brands(name)
            )
          ''')
          .eq('branch_id', _jasaanBranchId!);

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

  Future<void> _loadCalendarEvents() async {
    try {
      if (_jasaanBranchId == null) return;

      final result = await _supabase
          .from('calendar_events')
          .select('*')
          .eq('branch_id', _jasaanBranchId!)
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

  // ADD THIS METHOD
  List<dynamic> _getEventsForDay(DateTime day) {
    return _calendarEvents.where((event) {
      final eventDate = DateTime.parse(event['event_date']);
      return isSameDay(eventDate, day);
    }).toList();
  }

  // ADD THIS METHOD
  void _showCalendarEventDialog(DateTime selectedDate) {
    if (_jasaanBranchId == null) {
      _showErrorSnackbar('Branch not loaded yet');
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Events for ${_formatDate(selectedDate)}'),
        content: CalendarEventDialog(
          selectedDate: selectedDate,
          branchId: _jasaanBranchId!,
          userId: widget.userId,
          onEventChanged: () {
            _loadCalendarEvents(); // Refresh events in Jasaan screen
          },
        ),
      ),
    );
  }

  // ADD THIS METHOD
  String _formatDate(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showUpdateBrandPopup() {
    final TextEditingController brandNameController = TextEditingController();
    final TextEditingController brandDescController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(16),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Add Brand to Jasaan Branch",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined, size: 32, color: Colors.grey),
                        SizedBox(height: 4),
                        Text("Brand Logo", style: TextStyle(fontSize: 10, color: Colors.grey)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: brandNameController,
                    decoration: const InputDecoration(
                      labelText: "Brand Name *",
                      border: OutlineInputBorder(),
                      hintText: "Enter brand name",
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: brandDescController,
                    decoration: const InputDecoration(
                      labelText: "Brand Description",
                      border: OutlineInputBorder(),
                      hintText: "Enter brand description (optional)",
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green,
                            side: const BorderSide(color: Colors.green),
                            minimumSize: const Size(0, 45),
                          ),
                          child: const Text("CANCEL"),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            final name = brandNameController.text.trim();
                            final description = brandDescController.text.trim();

                            if (name.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Brand name is required')),
                              );
                              return;
                            }

                            if (_jasaanBranchId == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Branch not found')),
                              );
                              return;
                            }

                            try {
                              // Create new brand
                              final result = await _supabase
                                  .from('brands')
                                  .insert({
                                'name': name,
                                'description': description.isEmpty ? null : description,
                              })
                                  .select();

                              final newBrandId = result[0]['id'];

                              // Add to Jasaan branch
                              await _supabase
                                  .from('branch_brands')
                                  .insert({
                                'branch_id': _jasaanBranchId!,
                                'brand_id': newBrandId,
                              });

                              await _loadBrands();
                              Navigator.pop(context);

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('$name added to Jasaan branch'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error adding brand: $e'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green[300],
                            minimumSize: const Size(0, 45),
                          ),
                          child: const Text("ADD TO JASAAN", style: TextStyle(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showRemoveBrandPopup() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Remove Brands from Jasaan Branch",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Tap delete icon to remove a brand from Jasaan branch",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 300,
                  child: _brands.isEmpty
                      ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey),
                        SizedBox(height: 8),
                        Text('No brands in Jasaan branch'),
                      ],
                    ),
                  )
                      : ListView.builder(
                    itemCount: _brands.length,
                    itemBuilder: (context, index) {
                      final brand = _brands[index];
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: const [
                            BoxShadow(color: Colors.black12, blurRadius: 3)
                          ],
                        ),
                        child: ListTile(
                          title: Text(brand['name'] ?? 'Unknown Brand'),
                          subtitle: brand['description'] != null
                              ? Text(brand['description']!)
                              : const Text('No description'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.green),
                            onPressed: () => _confirmBrandRemoval(brand),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[300],
                    minimumSize: const Size(double.infinity, 45),
                  ),
                  child: const Text("CLOSE", style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmBrandRemoval(Map<String, dynamic> brand) async {
    final bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Removal"),
        content: Text(
          "Are you sure you want to remove '${brand['name']}' from Jasaan branch?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("CANCEL"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text("REMOVE", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ) ?? false;

    if (confirm) {
      try {
        // Remove from branch_brands (not delete the brand entirely)
        await _supabase
            .from('branch_brands')
            .delete()
            .eq('branch_id', _jasaanBranchId!)
            .eq('brand_id', brand['id']);

        await _loadBrands();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${brand['name']} removed from Jasaan branch'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error removing brand: $e'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Widget _buildLowStockAlert() {
    final hasLowStock = _lowStockItems.isNotEmpty;
    final alertColor = hasLowStock ? Colors.green : Colors.green;
    final alertText = hasLowStock ? "LOW STOCK ALERT" : "STOCK STATUS";

    String lowStockProductNames = "All items stocked";
    if (hasLowStock) {
      lowStockProductNames = _lowStockItems.take(2).map((item) {
        final product = item['products'] ?? {};
        return product['name'] ?? 'Unknown Product';
      }).join('\n');
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
          if (_lowStockItems.length > 2) ...[
            const SizedBox(height: 4),
            Text(
              "+ ${_lowStockItems.length - 2} more items",
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
          _showCalendarEventDialog(selectedDay); // Add this line
        },
        eventLoader: _getEventsForDay, // Add this line
        headerStyle: const HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          titleTextStyle: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
        ),
        calendarStyle: CalendarStyle(
          todayDecoration: BoxDecoration(
            color: Colors.green.shade200,
            shape: BoxShape.circle,
          ),
          selectedDecoration: BoxDecoration(
            color: Colors.green.shade400,
            shape: BoxShape.circle,
          ),
          markerDecoration: BoxDecoration( // Add this for event dots
            color: Colors.green,
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
      backgroundColor: const Color(0xFFF0FFF0),
      appBar: AppBar(
        backgroundColor: const Color(0xFF90EE90),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
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
                const Text("Jasaan Branch",
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
          ? const Center(child: CircularProgressIndicator(color: Colors.green))
          : Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              decoration: InputDecoration(
                hintText: "Search Brands or Products",
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      _branchButton("View Inventory", Icons.inventory_2_outlined,
                          Colors.green[300]!, onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => JasaanInventory(
                                    fullName: widget.fullName,
                                    role: widget.role,
                                    userId: widget.userId,
                                    location  : widget.location
                                ),
                              ),
                            );
                          }),
                      const SizedBox(height: 10),
                      _branchButton("Add Brand", Icons.edit_note,
                          Colors.green[200]!, onPressed: _showUpdateBrandPopup),
                      const SizedBox(height: 10),
                      _branchButton("Remove Brand", Icons.delete_outline,
                          Colors.green[100]!, onPressed: _showRemoveBrandPopup),
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
            const SizedBox(height: 20),
            Expanded(
              child: _buildCalendar(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _branchButton(String label, IconData icon, Color color,
      {VoidCallback? onPressed}) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: Colors.white),
      label: Text(label,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}