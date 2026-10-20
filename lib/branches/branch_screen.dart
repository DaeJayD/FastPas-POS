import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../catalog/catalog_source.dart';
import '../core/fastpas_theme.dart';
import '../core/management_ui.dart';
import '../inventory/branchinventory/branch_inventory_screen.dart';
import 'branch_repository.dart';
import 'components/calendar_events.dart';

class BranchScreen extends StatefulWidget {
  const BranchScreen({
    super.key,
    required this.fullName,
    required this.role,
    required this.userId,
    required this.location,
    required this.branchName,
    this.branch,
    this.repository,
  });
  final String fullName, role, userId, location, branchName;
  final StoreBranch? branch;
  final BranchRepository? repository;
  @override
  State<BranchScreen> createState() => _BranchScreenState();
}

class _BranchScreenState extends State<BranchScreen> {
  late final _repository = widget.repository ?? BranchRepository();
  StoreBranch? _branch;
  List<BranchBrand> _brands = [];
  List<StockWarning> _warnings = [];
  List<BranchEvent> _events = [];
  bool _loading = true;
  bool _error = false;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final branch =
          widget.branch ?? await _repository.findByName(widget.branchName);
      final results = await Future.wait<Object>([
        _repository.brands(branch.id),
        _repository.warnings(branch.id),
        _repository.events(branch.id),
      ]);
      if (!mounted) return;
      setState(() {
        _branch = branch;
        _brands = results[0] as List<BranchBrand>;
        _warnings = results[1] as List<StockWarning>;
        _events = results[2] as List<BranchEvent>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _addBrand() async {
    final branch = _branch;
    if (branch == null) return;
    final values = await showDialog<List<String>>(
      context: context,
      builder: (_) => const _BrandForm(),
    );
    if (values == null || !mounted) return;
    try {
      await _repository.addBrand(branch.id, values[0], values[1]);
      if (!mounted) return;
      await _load();
      _message('Brand added to ${branch.name}');
    } catch (_) {
      _message('Could not add brand. Please try again.');
    }
  }

  Future<void> _removeBrand() async {
    final branch = _branch;
    if (branch == null) return;
    final brand = await showDialog<BranchBrand>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove brand from ${branch.name}'),
        content: SizedBox(
          width: 420,
          height: 300,
          child: _brands.isEmpty
              ? const Center(child: Text('No brands assigned'))
              : ListView(
                  children: [
                    for (final item in _brands)
                      ListTile(
                        title: Text(item.name),
                        subtitle: item.description.isEmpty
                            ? null
                            : Text(item.description),
                        trailing: IconButton(
                          tooltip: 'Remove ${item.name}',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => Navigator.pop(context, item),
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (brand == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm removal'),
        content: Text("Remove '${brand.name}' from ${branch.name}?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _repository.removeBrand(branch.id, brand.id);
      if (!mounted) return;
      await _load();
      _message('Brand removed from ${branch.name}');
    } catch (_) {
      _message('Could not remove brand. Please try again.');
    }
  }

  Future<void> _openEvents(DateTime day) async {
    if (_branch == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Events for ${day.year}-${day.month}-${day.day}'),
        scrollable: true,
        content: CalendarEventDialog(
          selectedDate: day,
          branchId: _branch!.id,
          userId: widget.userId,
          onEventChanged: _load,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: ManagementTitle(
        _branch?.name ?? widget.branchName,
        subtitle: '${widget.fullName} · ${widget.role}',
      ),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load branch'),
                TextButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          )
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ManagementColumns(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.inventory_2_outlined),
                        label: const Text('View Inventory'),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BranchInventoryScreen(
                              branchName: widget.branchName,
                              branch: _branch,
                              fullName: widget.fullName,
                              role: widget.role,
                              userId: widget.userId,
                              location: widget.location,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        onPressed: _addBrand,
                        icon: const Icon(Icons.edit_note),
                        label: const Text('Add Brand'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _removeBrand,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Remove Brand'),
                      ),
                    ],
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.inventory_outlined, color: Volt.ink),
                          const SizedBox(height: 10),
                          Text(
                            _warnings.isEmpty
                                ? 'STOCK STATUS'
                                : 'LOW STOCK ALERT',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          if (_warnings.isEmpty)
                            const Text('All items stocked')
                          else
                            for (final item in _warnings.take(3))
                              Text('${item.name} · ${item.quantity} left'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: TableCalendar<BranchEvent>(
                    firstDay: DateTime(2020),
                    lastDay: DateTime(2100),
                    focusedDay: _focusedDay,
                    selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                    headerStyle: const HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                    ),
                    calendarStyle: const CalendarStyle(
                      selectedDecoration: BoxDecoration(
                        color: Volt.ink,
                        shape: BoxShape.circle,
                      ),
                      todayDecoration: BoxDecoration(
                        color: Volt.muted,
                        shape: BoxShape.circle,
                      ),
                    ),
                    eventLoader: (day) => _events
                        .where((event) => isSameDay(event.date, day))
                        .toList(),
                    onPageChanged: (day) => _focusedDay = day,
                    onDaySelected: (selected, focused) {
                      setState(() {
                        _selectedDay = selected;
                        _focusedDay = focused;
                      });
                      _openEvents(selected);
                    },
                  ),
                ),
              ),
            ],
          ),
  );
}

class _BrandForm extends StatefulWidget {
  const _BrandForm();
  @override
  State<_BrandForm> createState() => _BrandFormState();
}

class _BrandFormState extends State<_BrandForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(), _description = TextEditingController();
  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add brand to branch'),
    scrollable: true,
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Brand name'),
            validator: (value) =>
                (value ?? '').trim().isEmpty ? 'Enter a brand name' : null,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _description,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
            ),
            maxLines: 3,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, [
              _name.text.trim(),
              _description.text.trim(),
            ]);
          }
        },
        child: const Text('Add brand'),
      ),
    ],
  );
}
