import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/fastpas_theme.dart';
import 'workspace_screen.dart';
import 'workspace_account.dart';

/// Business-scoped entry point shared by the default app and workspace target.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (url.isEmpty || key.isEmpty) {
    throw StateError(
      'Supply the Supabase configuration described in README.md.',
    );
  }
  await Supabase.initialize(
    url: url,
    anonKey: key,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      detectSessionInUri: false,
    ),
  );
  runApp(WorkspaceApp(client: Supabase.instance.client));
}

class WorkspaceApp extends StatefulWidget {
  const WorkspaceApp({super.key, required this.client});
  final SupabaseClient client;
  @override
  State<WorkspaceApp> createState() => _WorkspaceAppState();
}

class _WorkspaceAppState extends State<WorkspaceApp> {
  late final WorkspaceAccount _account;
  @override
  void initState() {
    super.initState();
    _account = WorkspaceAccount(widget.client);
    final links = AppLinks();
    _account.attachLinks(links.uriLinkStream, links.getInitialLink());
  }

  @override
  void dispose() {
    _account.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'FastPas POS',
    theme: Volt.theme,
    home: WorkspaceScreen(client: widget.client, account: _account),
  );
}
