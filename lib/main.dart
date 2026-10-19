import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/fastpas_theme.dart';
import 'pos/product_home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    throw StateError('Missing Supabase configuration. Run with '
        '--dart-define-from-file=config/supabase.local.json. See README.md.');
  }
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  runApp(const VasenizzApp());
}

class VasenizzApp extends StatelessWidget {
  const VasenizzApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'FastPas POS',
        theme: Volt.theme,
        home: const LoginScreen(),
      );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_loading || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Existing login contract retained until the authentication migration.
      final user = await Supabase.instance.client
          .from('employees')
          .select()
          .eq('username', _username.text.trim())
          .eq('password', _password.text.trim())
          .maybeSingle();
      if (!mounted) return;
      if (user == null) {
        setState(() {
          _loading = false;
          _error = 'Username or password is incorrect.';
        });
        return;
      }
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => ProductHomeScreen(
                fullName: (user['name'] ?? '').toString(),
                role: (user['role'] ?? '').toString().toLowerCase(),
                userId: user['user_id'].toString(),
                location: (user['branch'] ?? '').toString(),
              )));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Couldn’t sign in. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
            child: Center(
                child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FastPasBrand(size: 36),
                      const SizedBox(height: 52),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: Volt.lime.withValues(alpha: .3),
                            borderRadius: BorderRadius.circular(18)),
                        child: const Icon(Icons.storefront_outlined, size: 30),
                      ),
                      const SizedBox(height: 22),
                      const Text('Your store.\nReady to go.',
                          style: TextStyle(
                              fontSize: 38,
                              fontWeight: FontWeight.w800,
                              height: 1.12,
                              letterSpacing: -1.3)),
                      const SizedBox(height: 12),
                      const Text(
                          'Sign in to start selling and manage your day.',
                          style: TextStyle(
                              color: Volt.muted, fontSize: 15, height: 1.5)),
                      const SizedBox(height: 32),
                      TextFormField(
                        controller: _username,
                        autofillHints: const [AutofillHints.username],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                            labelText: 'Username',
                            prefixIcon: Icon(Icons.person_outline)),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Enter your username.'
                                : null,
                      ),
                      const SizedBox(height: 18),
                      TextFormField(
                        controller: _password,
                        obscureText: _hidePassword,
                        autofillHints: const [AutofillHints.password],
                        onFieldSubmitted: (_) => _login(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _hidePassword
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () =>
                                setState(() => _hidePassword = !_hidePassword),
                            icon: Icon(_hidePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                          ),
                        ),
                        validator: (value) => value == null || value.isEmpty
                            ? 'Enter your password.'
                            : null,
                      ),
                      if (_error != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(_error!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error))),
                      const SizedBox(height: 24),
                      SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _loading ? null : _login,
                            child: _loading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                        Text('Sign in'),
                                        SizedBox(width: 12),
                                        Icon(Icons.arrow_forward, size: 19)
                                      ]),
                          )),
                      const SizedBox(height: 28),
                      const Text('Fast sales. A clearer day.',
                          style: TextStyle(color: Volt.muted, fontSize: 12)),
                    ]),
              )),
        ))),
      );
}
