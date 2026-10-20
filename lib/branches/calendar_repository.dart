import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/store_connection.dart';

class CalendarRecord {
  const CalendarRecord(this.id, this.description, this.createdBy);
  final String id, description, createdBy;
}

class CalendarRepository {
  CalendarRepository({SupabaseClient? client})
    : _client = client ?? StoreConnection.client;
  final SupabaseClient _client;
  String _date(DateTime date) => date.toIso8601String().split('T').first;
  Future<String> branchName(String branchId) async {
    final row = await _client
        .from('branches')
        .select('name')
        .eq('id', branchId)
        .single();
    return row['name'].toString();
  }

  Future<List<CalendarRecord>> forDay(String branchId, DateTime day) async {
    final rows = await _client
        .from('calendar_events')
        .select('*')
        .eq('event_date', _date(day))
        .eq('branch_id', branchId)
        .order('created_at');
    return [
      for (final row in rows)
        CalendarRecord(
          row['id'].toString(),
          row['description']?.toString() ?? '',
          row['created_by']?.toString() ?? '',
        ),
    ];
  }

  Future<void> add(
    String branchId,
    DateTime day,
    String description,
    String userId,
  ) async {
    await _client.from('calendar_events').insert({
      'branch_id': branchId,
      'event_date': _date(day),
      'event_type': 'custom',
      'description': description.trim(),
      'created_by': userId,
    });
  }

  Future<void> remove(String branchId, String eventId) async {
    await _client
        .from('calendar_events')
        .delete()
        .eq('id', eventId)
        .eq('branch_id', branchId);
  }
}
