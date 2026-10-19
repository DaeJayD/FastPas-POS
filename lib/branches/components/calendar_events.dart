import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CalendarEventDialog extends StatefulWidget {
  final DateTime selectedDate;
  final String branchId;
  final String userId;
  final VoidCallback onEventChanged; // Callback to refresh parent

  const CalendarEventDialog({
    super.key,
    required this.selectedDate,
    required this.branchId,
    required this.userId,
    required this.onEventChanged,
  });

  @override
  State<CalendarEventDialog> createState() => _CalendarEventDialogState();
}

class _CalendarEventDialogState extends State<CalendarEventDialog> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isLoading = false;
  List<dynamic> _existingEvents = [];
  String? _branchName;

  @override
  void initState() {
    super.initState();
    _loadExistingEvents();
    _loadBranchName();
  }

  Future<void> _loadBranchName() async {
    try {
      final result = await _supabase
          .from('branches')
          .select('name')
          .eq('id', widget.branchId)
          .single();

      setState(() {
        _branchName = result['name'] as String?;
      });
    } catch (e) {
      print('Error loading branch name: $e');
    }
  }

  Future<void> _loadExistingEvents() async {
    try {
      final result = await _supabase
          .from('calendar_events')
          .select('*')
          .eq('event_date', widget.selectedDate.toIso8601String().split('T')[0])
          .eq('branch_id', widget.branchId)
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

    setState(() {
      _isLoading = true;
    });

    try {
      await _supabase.from('calendar_events').insert({
        'branch_id': widget.branchId,
        'event_date': widget.selectedDate.toIso8601String().split('T')[0],
        'event_type': 'custom',
        'description': _descriptionController.text.trim(),
        'created_by': widget.userId,
      });

      if (!mounted) return;

      _descriptionController.clear();
      await _loadExistingEvents();

      // Notify parent to refresh calendar
      widget.onEventChanged();

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

      await _loadExistingEvents();

      // Notify parent to refresh calendar
      widget.onEventChanged();

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
            // Branch Info
            if (_branchName != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.pink[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.business, color: Colors.pink),
                    const SizedBox(width: 8),
                    Text(
                      'Branch: $_branchName',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.pink,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

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
                    'Added by: ${event['created_by']}',
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
                    child: const Text('Close'),
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
}