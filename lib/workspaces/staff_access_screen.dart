import 'package:flutter/material.dart';

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'workspace_repository.dart';

class StaffAccessScreen extends StatefulWidget {
  const StaffAccessScreen({
    super.key,
    required this.repository,
    required this.business,
  });
  final WorkspaceRepository repository;
  final BusinessWorkspace business;

  @override
  State<StaffAccessScreen> createState() => _StaffAccessScreenState();
}

class _StaffAccessScreenState extends State<StaffAccessScreen> {
  Map<String, dynamic>? _data;
  bool _busy = false;
  String? _error;
  StreamSubscription<AuthState>? _auth;
  late final String? _actor;

  @override
  void initState() {
    super.initState();
    _actor = widget.repository.client.auth.currentUser?.id;
    _auth = widget.repository.client.auth.onAuthStateChange.listen(
      (event) {
        if (mounted && event.session?.user.id != _actor) {
          setState(() {
            _data = null;
            _error = 'Account changed. Return to your businesses.';
          });
        }
      },
      onError: (_) {
        if (mounted) {
          setState(() {
            _data = null;
            _error = 'Connect to manage staff access.';
          });
        }
      },
    );
    _refresh();
  }

  @override
  void dispose() {
    _auth?.cancel();
    super.dispose();
  }

  void _checkIdentity() {
    if (_actor == null ||
        widget.repository.client.auth.currentUser?.id != _actor) {
      throw StateError('Account changed');
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _checkIdentity();
      await action();
    } catch (_) {
      if (mounted) {
        setState(() {
          _data = null;
          _error = 'Could not update staff access. Check your connection and Owner access, then refresh.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() async {
    _checkIdentity();
    final data = await widget.repository.staffAccess(widget.business.id);
    _checkIdentity();
    if (mounted) setState(() => _data = data);
  }

  Future<void> _refresh() => _run(_load);

  Future<void> _remove(Map member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove staff access?'),
        content: Text(
          '${member['email']} will lose access to this business. Their saved sales remain. Offline devices learn the change when they reconnect.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep access'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove access'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      await widget.repository.changeStaffAccess(
        widget.business.id,
        member['user_id'] as String,
        null,
      );
      await _load();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${widget.business.name} · Staff'),
      actions: [
        IconButton(
          tooltip: 'Refresh staff',
          onPressed: _busy ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Role changes apply online immediately. Offline devices learn changes when they reconnect; pending receipts are retained.',
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Text(_error!),
          for (final member in (_data?['members'] as List? ?? []))
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member['email'] as String? ?? member['user_id'] as String,
                    ),
                    if (member['role'] == 'owner')
                      const Text('Owner')
                    else ...[
                      DropdownButton<String>(
                        isExpanded: true,
                        value: member['role'] as String,
                        items: const ['manager', 'cashier', 'employee']
                            .map(
                              (role) => DropdownMenuItem(
                                value: role,
                                child: Text(role),
                              ),
                            )
                            .toList(),
                        onChanged: _busy
                            ? null
                            : (role) {
                                if (role == null) return;
                                _run(() async {
                                  await widget.repository.changeStaffAccess(
                                    widget.business.id,
                                    member['user_id'] as String,
                                    role,
                                  );
                                  await _load();
                                });
                              },
                      ),
                      TextButton(
                        onPressed: _busy ? null : () => _remove(member as Map),
                        child: const Text('Remove access'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'Pending invitations',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          for (final invite in (_data?['invitations'] as List? ?? []))
            ListTile(
              title: Text(invite['email'] as String),
              subtitle: Text(
                '${invite['role']} · expires ${invite['expires_at']}',
              ),
              trailing: IconButton(
                tooltip: 'Cancel invitation',
                icon: const Icon(Icons.close),
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        await widget.repository.cancelInvitation(
                          invite['code'] as String,
                        );
                        await _load();
                      }),
              ),
            ),
        ],
      ),
    ),
  );
}
