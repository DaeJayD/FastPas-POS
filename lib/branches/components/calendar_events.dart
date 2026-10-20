import '../calendar_repository.dart';

import 'package:vasenizzpos/core/fastpas_theme.dart';
import 'package:flutter/material.dart';

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
  final _repository = CalendarRepository();
  bool _isLoading = false;
  List<CalendarRecord> _existingEvents = [];
  String? _branchName;

  @override
  void initState() {
    super.initState();
    _loadExistingEvents();
    _loadBranchName();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadBranchName() async {
    try {
      final name = await _repository.branchName(widget.branchId);
      if (!mounted) return;
      setState(() {
        _branchName = name;
      });
    } catch (e) {
      debugPrint('Could not load branch name');
    }
  }

  Future<void> _loadExistingEvents() async {
    try {
      final events = await _repository.forDay(
        widget.branchId,
        widget.selectedDate,
      );
      if (!mounted) return;
      setState(() {
        _existingEvents = events;
      });
    } catch (e) {
      debugPrint('Error loading existing events: $e');
    }
  }

  Future<void> _addEvent() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await _repository.add(
        widget.branchId,
        widget.selectedDate,
        _descriptionController.text,
        widget.userId,
      );

      if (!mounted) return;

      _descriptionController.clear();
      await _loadExistingEvents();

      // Notify parent to refresh calendar
      if (!mounted) return;
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
      await _repository.remove(widget.branchId, eventId);

      if (!mounted) return;

      await _loadExistingEvents();

      // Notify parent to refresh calendar
      if (!mounted) return;
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
            // Branch Info
            if (_branchName != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Volt.soft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    const Icon(Icons.business, color: Volt.ink),
                    const SizedBox(width: 8),
                    Text(
                      'Branch: $_branchName',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Volt.ink,
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
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 10),
              ..._existingEvents.map(
                (event) => Card(
                  color: Colors.grey[50],
                  child: ListTile(
                    title: Text(
                      event.description,
                      style: const TextStyle(fontSize: 14),
                    ),
                    subtitle: Text(
                      'Added by: ${event.createdBy}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: _isLoading
                          ? null
                          : () => _showDeleteConfirmation(
                              event.id,
                              event.description,
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
                    child: const Text('Close'),
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
}
