import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Discovery labels only. Receipts and inventory live in isolated SQLite files.
class WorkspaceCache {
  Future<void> clear(String user, String key) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('fastpas.$user.$key');
  }

  Future<void> save(
    String user,
    String key,
    List<Map<String, dynamic>> rows,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'fastpas.$user.$key',
      jsonEncode({
        'saved_at': DateTime.now().toUtc().toIso8601String(),
        'rows': rows,
      }),
    );
  }

  Future<List<Map<String, dynamic>>> read(String user, String key) async {
    final preferences = await SharedPreferences.getInstance();
    final text = preferences.getString('fastpas.$user.$key');
    if (text == null) return [];
    final record = jsonDecode(text) as Map<String, dynamic>;
    final saved = DateTime.parse(record['saved_at'] as String);
    final now = DateTime.now().toUtc();
    if (now.isBefore(saved) ||
        now.difference(saved) >= const Duration(hours: 24)) {
      return [];
    }
    return (record['rows'] as List).cast<Map<String, dynamic>>();
  }
}
