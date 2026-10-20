import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/fastpas_theme.dart';
import 'auth/login_screen.dart';
export 'auth/login_screen.dart' show LoginScreen;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    throw StateError(
      'Missing Supabase configuration. Run with '
      '--dart-define-from-file=config/supabase.local.json. See README.md.',
    );
  }
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  runApp(const FastPasApp());
}

class FastPasApp extends StatelessWidget {
  const FastPasApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'FastPas POS',
    theme: Volt.theme,
    home: const LoginScreen(),
  );
}
