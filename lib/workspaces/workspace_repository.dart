import 'dart:math';
import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'workspace_cache.dart';

class BusinessWorkspace {
  const BusinessWorkspace({
    required this.id,
    required this.name,
    required this.role,
  });
  final String id;
  final String name;
  final String role;
}

class WorkspaceBranch {
  const WorkspaceBranch({
    required this.id,
    required this.businessId,
    required this.name,
  });
  final String id;
  final String businessId;
  final String name;
}

/// Uses only the new workspace contract, never the legacy retail tables.
class WorkspaceRepository {
  WorkspaceRepository(this.client);
  final SupabaseClient client;
  final _cache = WorkspaceCache();
  bool lastReadOffline = false;

  Future<List<Map<String, dynamic>>> _cachedRead(
    String key,
    Future<List<Map<String, dynamic>>> Function() load,
  ) async {
    final user = client.auth.currentUser?.id;
    if (user == null) return [];
    lastReadOffline = false;
    try {
      final rows = await load().timeout(const Duration(seconds: 12));
      if (client.auth.currentUser?.id != user) {
        throw StateError('Account changed');
      }
      await _cache.save(user, key, rows);
      return rows;
    } catch (error) {
      if (error is PostgrestException &&
          ['42501', 'PGRST301'].contains(error.code)) {
        await _cache.clear(user, key);
      }
      if (error is! SocketException &&
          error is! ClientException &&
          error is! TimeoutException) {
        rethrow;
      }
      if (client.auth.currentUser?.id != user) rethrow;
      lastReadOffline = true;
      return _cache.read(user, key);
    }
  }

  static String newRequestId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<List<BusinessWorkspace>> businesses() async {
    final rows = await _cachedRead('businesses', () async {
      final user = client.auth.currentUser;
      if (user == null) return [];
      final memberships = await client
          .from('pos_memberships')
          .select('business_id,role')
          .eq('user_id', user.id);
      final roles = {
        for (final row in memberships)
          row['business_id'] as String: row['role'] as String,
      };
      final rows = await client
          .from('pos_businesses')
          .select('id,name')
          .order('name');
      return rows
          .map((row) => {...row, 'role': roles[row['id']] ?? 'employee'})
          .toList();
    });
    return rows
        .map(
          (r) => BusinessWorkspace(
            id: r['id'] as String,
            name: r['name'] as String,
            role: r['role'] as String,
          ),
        )
        .toList();
  }

  Future<List<WorkspaceBranch>> branches(String businessId) async {
    final rows = await _cachedRead(
      'branches.$businessId',
      () async => await client
          .from('pos_branches')
          .select('id,business_id,name')
          .eq('business_id', businessId)
          .order('name'),
    );
    return rows
        .map(
          (r) => WorkspaceBranch(
            id: r['id'] as String,
            businessId: r['business_id'] as String,
            name: r['name'] as String,
          ),
        )
        .toList();
  }

  Future<String> createBusiness({
    required String requestId,
    required String name,
    required String branchName,
  }) async => await client.rpc(
    'pos_create_business',
    params: {
      'request_id': requestId,
      'business_name': name.trim(),
      'branch_name': branchName.trim(),
    },
  ) as String;

  Future<String> inviteStaff({
    required String businessId,
    required String branchId,
    required String email,
    required String role,
  }) async => await client.rpc(
    'pos_invite_staff',
    params: {
      'business': businessId,
      'branch': branchId,
      'invite_email': email.trim(),
      'invite_role': role,
    },
  ) as String;

  Future<String> acceptInvitation(String code) async => await client.rpc(
    'pos_accept_invitation',
    params: {'invite_code': code.trim()},
  ) as String;

  Future<Map<String, dynamic>> staffAccess(String businessId) async =>
      Map<String, dynamic>.from(
        await client.rpc('pos_staff_access', params: {'business': businessId})
            as Map,
      );

  Future<void> changeStaffAccess(
    String businessId,
    String userId,
    String? role,
  ) async {
    await client.rpc(
      'pos_change_staff_access',
      params: {'business': businessId, 'member': userId, 'new_role': role},
    );
  }

  Future<void> cancelInvitation(String code) async {
    await client.rpc('pos_cancel_invitation', params: {'invite_code': code});
  }
}
