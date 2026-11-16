import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lives above Navigator so changing appearance preserves route/cart state.
class PosThemeHost extends StatefulWidget {
  const PosThemeHost({super.key, required this.builder});
  final Widget Function(ThemeMode mode) builder;
  @override
  State<PosThemeHost> createState() => _PosThemeHostState();
}

class _PosThemeHostState extends State<PosThemeHost> {
  ThemeMode _mode = ThemeMode.dark;
  int _revision = 0;
  Future<void> _writes = Future.value();
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final revision = _revision;
    try {
      final preferences = await SharedPreferences.getInstance();
      final value = preferences.getString('fastpas.appearance');
      if (mounted && revision == _revision) {
        setState(
          () => _mode = value == 'light' ? ThemeMode.light : ThemeMode.dark,
        );
      }
    } catch (_) {
      // Preference storage is independent of account and selling access.
    }
  }

  void _toggle() {
    _revision++;
    setState(
      () => _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
    );
    final value = _mode == ThemeMode.dark ? 'dark' : 'light';
    _writes = _writes.then((_) async {
      try {
        final preferences = await SharedPreferences.getInstance();
        final saved = await preferences.setString('fastpas.appearance', value);
        if (mounted) _storageError.value = !saved;
      } catch (_) {
        if (mounted) {
          // A visible failure is preferable to silently claiming persistence.
          _storageError.value = true;
        }
      }
    });
  }

  final _storageError = ValueNotifier(false);
  @override
  void dispose() {
    _storageError.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ThemeScope(
    mode: _mode,
    toggle: _toggle,
    storageError: _storageError,
    child: widget.builder(_mode),
  );
}

class _ThemeScope extends InheritedWidget {
  const _ThemeScope({
    required this.mode,
    required this.toggle,
    required this.storageError,
    required super.child,
  });
  final ThemeMode mode;
  final VoidCallback toggle;
  final ValueNotifier<bool> storageError;
  @override
  bool updateShouldNotify(_ThemeScope oldWidget) => mode != oldWidget.mode;
}

class ThemeSwitch extends StatelessWidget {
  const ThemeSwitch({super.key});
  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_ThemeScope>();
    if (scope == null) return const SizedBox.shrink();
    final dark = scope.mode == ThemeMode.dark;
    return ValueListenableBuilder<bool>(
      valueListenable: scope.storageError,
      builder: (context, failed, _) => IconButton(
        tooltip: failed
            ? 'Appearance could not be saved. Tap to retry.'
            : dark
            ? 'Switch to Porcelain light'
            : 'Switch to Forest dark',
        onPressed: scope.toggle,
        icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
      ),
    );
  }
}
