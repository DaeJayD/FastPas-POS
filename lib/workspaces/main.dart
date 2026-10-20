import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/fastpas_theme.dart';
import 'workspace_screen.dart';

/// Staged workspace entry point. Retail routes require tenant migration first.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (url.isEmpty || key.isEmpty) {
    throw StateError(
      'Supply the Supabase configuration described in README.md.',
    );
  }
  await Supabase.initialize(url: url, anonKey: key);
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FastPas POS',
      theme: Volt.theme,
      home: WorkspaceScreen(client: Supabase.instance.client),
    ),
  );
}
