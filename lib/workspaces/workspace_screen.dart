import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/fastpas_theme.dart';
import '../hybrid/hybrid_pos_screen.dart';
import 'workspace_repository.dart';
import 'staff_access_screen.dart';
import 'workspace_account.dart';
import 'business_settings_screen.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key, required this.client, this.account});
  final SupabaseClient client;
  final WorkspaceAccount? account;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  late final WorkspaceAccount _account;
  bool _wasRecovering = false;
  late final WorkspaceRepository _repository = WorkspaceRepository(
    widget.client,
  );
  StreamSubscription<AuthState>? _auth;
  List<BusinessWorkspace> _businesses = [];
  List<WorkspaceBranch> _branches = [];
  BusinessWorkspace? _selected;
  String? _message;
  bool _busy = false;
  bool _register = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _account = widget.account ?? WorkspaceAccount(widget.client);
    _account.addListener(_accountChanged);
    _wasRecovering = _account.recoveringPassword;
    _auth = widget.client.auth.onAuthStateChange.listen(
      (event) {
        if (!mounted) return;
        // Discard every previous account's visible data before reloading.
        _generation++;
        setState(() {
          _selected = null;
          _businesses = [];
          _branches = [];
        });
        if (event.session != null && !_account.recoveringPassword) {
          unawaited(_reload());
        }
      },
      onError: (_) {
        if (mounted) {
          setState(
            () => _message = 'Connection unavailable. Previously downloaded stores can be used within their offline access period.',
          );
        }
      },
    );
    if (widget.client.auth.currentSession != null &&
        !_account.recoveringPassword) {
      unawaited(_reload());
    }
  }

  void _accountChanged() {
    if (!mounted) return;
    final recovering = _account.recoveringPassword;
    if (recovering && !_wasRecovering) {
      _password.clear();
      _confirmPassword.clear();
    }
    _wasRecovering = recovering;
    setState(() {
      _message = null;
      if (recovering) {
        _generation++;
        _selected = null;
        _businesses = [];
        _branches = [];
      }
    });
  }

  @override
  void dispose() {
    _generation++;
    _auth?.cancel();
    _account.removeListener(_accountChanged);
    if (widget.account == null) _account.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    if (mounted) {
      setState(() {
        _selected = null;
        _branches = [];
        _businesses = [];
      });
    }
    try {
      final businesses = await _repository.businesses();
      if (!mounted ||
          generation != _generation ||
          _account.recoveringPassword) {
        return;
      }
      setState(() {
        _businesses = businesses;
        if (_repository.lastReadOffline) {
          _message = 'Offline · showing previously downloaded businesses.';
        }
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _message = 'Could not load businesses. Check your connection and workspace setup.',
        );
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on FormatException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } on AuthException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Could not complete this action. Check your connection, access, and details, then retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _select(BusinessWorkspace business) async {
    final generation = ++_generation;
    setState(() {
      _selected = business;
      _branches = [];
    });
    final branches = await _repository.branches(business.id);
    if (mounted && generation == _generation) {
      setState(() => _branches = branches);
    }
  }

  Future<void> _create() async {
    final name = TextEditingController();
    final branch = TextEditingController(text: 'Main branch');
    // One request ID survives failed submissions while this dialog remains open.
    final requestId = WorkspaceRepository.newRequestId();
    var saving = false;
    String? error;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => PopScope(
          canPop: !saving,
          child: AlertDialog(
            title: const Text('Create a business'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: 'Business name',
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: branch,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: 'First branch',
                    ),
                  ),
                  if (error != null) Text(error!),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (name.text.trim().isEmpty ||
                            branch.text.trim().isEmpty) {
                          update(
                            () => error = 'Enter a business and branch name.',
                          );
                          return;
                        }
                        update(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          await _repository.createBusiness(
                            requestId: requestId,
                            name: name.text,
                            branchName: branch.text,
                          );
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                          await _reload();
                        } catch (_) {
                          if (dialogContext.mounted) {
                            update(() {
                              saving = false;
                              error = 'Could not create your business. Verify your email and connection, then retry.';
                            });
                          }
                        }
                      },
                child: Text(saving ? 'Creating…' : 'Create'),
              ),
            ],
          ),
        ),
      ),
    );
    // A popped dialog may still animate with its controllers attached.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    name.dispose();
    branch.dispose();
  }

  Future<void> _accept() async {
    final input = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join a business'),
        content: TextField(
          controller: input,
          decoration: const InputDecoration(labelText: 'Invitation code'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: const Text('Join'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    input.dispose();
    if (code == null || code.trim().isEmpty || !mounted) return;
    await _run(() async {
      await _repository.acceptInvitation(code);
      await _reload();
    });
  }

  Future<void> _invite(WorkspaceBranch branch) async {
    final email = TextEditingController();
    var role = 'cashier';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('Invite staff · ${branch.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Staff email'),
                ),
                const SizedBox(height: 18),
                DropdownButton<String>(
                  value: role,
                  isExpanded: true,
                  items: const ['manager', 'cashier', 'employee']
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) update(() => role = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create invitation'),
            ),
          ],
        ),
      ),
    );
    final address = email.text;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    email.dispose();
    if (confirmed != true || !mounted) return;
    await _run(() async {
      final code = await _repository.inviteStaff(
        businessId: branch.businessId,
        branchId: branch.id,
        email: address,
        role: role,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Invitation ready'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Share this code with the invited employee. It expires in 7 days and requires their verified email.',
              ),
              const SizedBox(height: 12),
              SelectableText(code),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = widget.client.auth.currentSession != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('FastPas POS'),
        actions: [
          if (signedIn)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      await widget.client.auth.signOut(
                        scope: SignOutScope.local,
                      );
                      _password.clear();
                    }),
              child: const Text('Sign out'),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const FastPasBrand(size: 32),
                const SizedBox(height: 24),
                if (_account.recoveringPassword) ...[
                  Text(
                    'Choose a new password',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const Text(
                    'Use at least 8 characters. Your businesses and saved sales stay with your account.',
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: const InputDecoration(
                      labelText: 'New password',
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _confirmPassword,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm new password',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await _account.finishRecovery(
                              _password.text,
                              _confirmPassword.text,
                            );
                            _password.clear();
                            _confirmPassword.clear();
                            await _reload();
                          }),
                    child: const Text('Update password'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await _account.cancelRecovery();
                            _password.clear();
                            _confirmPassword.clear();
                          }),
                    child: const Text('Cancel recovery'),
                  ),
                ] else if (!signedIn) ...[
                  Text(
                    _register ? 'Create your account' : 'Welcome back',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            if (_register) {
                              await _account.signUp(
                                _email.text,
                                _password.text,
                              );
                              if (mounted) {
                                setState(
                                  () => _message = 'Check your email to verify your account before creating a business.',
                                );
                              }
                            } else {
                              await _account.signIn(
                                _email.text,
                                _password.text,
                              );
                            }
                            _password.clear();
                          }),
                    child: Text(_register ? 'Sign up' : 'Sign in'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _register = !_register),
                    child: Text(
                      _register
                          ? 'Already have an account? Sign in'
                          : 'Create an account',
                    ),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await _account.sendPasswordReset(_email.text);
                            if (mounted) {
                              setState(
                                () => _message = 'If the account exists, a reset email has been sent. Open it on this device.',
                              );
                            }
                          }),
                    child: const Text('Forgot password?'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await _account.resendVerification(_email.text);
                            if (mounted) {
                              setState(
                                () => _message = 'If verification is needed, a fresh email has been sent. Open it on this device.',
                              );
                            }
                          }),
                    child: const Text('Resend verification email'),
                  ),
                ] else ...[
                  Text(
                    'Your businesses',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const Text(
                    'Create your business or join one using an invitation from its owner.',
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: _busy ? null : _create,
                        child: const Text('Create a business'),
                      ),
                      OutlinedButton(
                        onPressed: _busy ? null : _accept,
                        child: const Text('Join a business'),
                      ),
                      IconButton(
                        tooltip: 'Refresh businesses',
                        onPressed: _busy ? null : () => _run(_reload),
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  for (final business in _businesses)
                    Card(
                      margin: const EdgeInsets.only(top: 12),
                      child: ListTile(
                        title: Text(business.name),
                        subtitle: Text(business.role),
                        selected: _selected?.id == business.id,
                        leading: const Icon(Icons.storefront_outlined),
                        onTap: _busy
                            ? null
                            : () => _run(() => _select(business)),
                      ),
                    ),
                  if (_selected != null) ...[
                    if (_selected!.role == 'owner')
                      OutlinedButton.icon(
                        icon: const Icon(Icons.settings_outlined),
                        label: const Text('Business settings'),
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                final business = _selected!;
                                final actor =
                                    widget.client.auth.currentUser?.id;
                                await Navigator.push<void>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => BusinessSettingsScreen(
                                      repository: _repository,
                                      business: business,
                                    ),
                                  ),
                                );
                                if (!mounted ||
                                    widget.client.auth.currentUser?.id !=
                                        actor) {
                                  return;
                                }
                                await _reload();
                                final updated = _businesses
                                    .where((b) => b.id == business.id)
                                    .firstOrNull;
                                if (updated != null && mounted) {
                                  await _select(updated);
                                }
                              }),
                      ),
                    if (_selected!.role == 'owner')
                      OutlinedButton.icon(
                        icon: const Icon(Icons.manage_accounts_outlined),
                        label: const Text('Manage staff access'),
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                final business = _selected!;
                                await Navigator.push<void>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => StaffAccessScreen(
                                      repository: _repository,
                                      business: business,
                                    ),
                                  ),
                                );
                              }),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      '${_selected!.name} · Branches',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    for (final branch in _branches)
                      ListTile(
                        title: Text(branch.name),
                        onTap: _busy
                            ? null
                            : () => _run(() async {
                                final business = _selected!;
                                await Navigator.push<void>(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => HybridPosScreen(
                                      client: widget.client,
                                      business: business,
                                      branch: branch,
                                    ),
                                  ),
                                );
                              }),
                        leading: const Icon(Icons.location_on_outlined),
                        trailing: _selected!.role == 'owner'
                            ? IconButton(
                                tooltip: 'Invite staff',
                                onPressed: _busy ? null : () => _invite(branch),
                                icon: const Icon(Icons.person_add_outlined),
                              )
                            : null,
                      ),
                    const Text(
                      'Choose a branch to open cash selling. Connect once to download its catalog and verify access.',
                    ),
                  ],
                ],
                if (_busy) const LinearProgressIndicator(),
                if (_message != null || _account.notice != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(_message ?? _account.notice!),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
