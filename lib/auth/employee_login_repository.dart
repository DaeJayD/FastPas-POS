import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/pos_session.dart';
import '../core/store_connection.dart';

/// Keeps the existing employee-table contract isolated until Phase 3 replaces
/// it with Supabase Auth. This adapter does not make that contract secure.
class EmployeeLoginRepository {
  EmployeeLoginRepository({SupabaseClient? client})
    : _client = client ?? StoreConnection.client;
  final SupabaseClient _client;

  Future<PosSession?> signIn(String username, String password) async {
    final row = await _client
        .from('employees')
        .select()
        .eq('username', username.trim())
        .eq('password', password.trim())
        .maybeSingle();
    if (row == null) return null;
    return PosSession(
      fullName: row['name']?.toString() ?? '',
      role: (row['role']?.toString() ?? '').toLowerCase(),
      userId: row['user_id'].toString(),
      location: row['branch']?.toString() ?? '',
    );
  }
}
