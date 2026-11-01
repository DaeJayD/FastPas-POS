import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/pos_form_dialog.dart';
import 'business_settings.dart';
import 'workspace_repository.dart';

class BusinessSettingsScreen extends StatefulWidget {
  const BusinessSettingsScreen({
    super.key,
    required this.repository,
    required this.business,
  });
  final WorkspaceRepository repository;
  final BusinessWorkspace business;

  @override
  State<BusinessSettingsScreen> createState() => _BusinessSettingsScreenState();
}

class _BusinessSettingsScreenState extends State<BusinessSettingsScreen> {
  BusinessSettings? _settings;
  String? _error;
  bool _loading = false;
  int _generation = 0;
  late final String? _actor;
  StreamSubscription<AuthState>? _auth;
  BuildContext? _dialog;

  @override
  void initState() {
    super.initState();
    _actor = widget.repository.client.auth.currentUser?.id;
    _auth = widget.repository.client.auth.onAuthStateChange.listen(
      (event) {
        if (mounted && event.session?.user.id != _actor) {
          _generation++;
          final dialog = _dialog;
          _dialog = null;
          if (dialog != null && dialog.mounted) Navigator.pop(dialog);
          setState(() {
            _settings = null;
            _loading = false;
            _error = 'Account changed. Return to your businesses.';
          });
        }
      },
      onError: (_) {
        if (mounted) {
          setState(() {
            _settings = null;
            _error = 'Connect to manage business settings.';
          });
        }
      },
    );
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _generation++;
    _auth?.cancel();
    super.dispose();
  }

  void _checkIdentity() {
    if (_actor == null ||
        widget.repository.client.auth.currentUser?.id != _actor ||
        widget.business.role != 'owner') {
      throw StateError('Owner account changed');
    }
  }

  static String _message(Object error) {
    if (error is PostgrestException) {
      if (error.code == '40001') {
        return 'Settings changed on another device. Cancel and refresh before saving again.';
      }
      if (error.code == 'PGRST202') {
        return 'Business settings are not available yet. Refresh after your workspace is updated.';
      }
      if (error.code == '42501') {
        return 'Owner access is required. Return to your businesses and check your access.';
      }
      if (error.code == '22023') {
        return 'Check the details. If a branch request changed after a retry, cancel and refresh branches.';
      }
    }
    return 'Could not complete this action. Check your connection and Owner access, then retry.';
  }

  Future<void> _refresh() async {
    if (_loading) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _checkIdentity();
      final settings = await widget.repository.businessSettings(
        widget.business.id,
      );
      _checkIdentity();
      if (mounted && generation == _generation) {
        setState(() => _settings = settings);
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _settings = null;
          _error = _message(error);
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  String? _name(String? value) =>
      value == null || value.trim().isEmpty || value.trim().length > 120
      ? 'Use a name between 1 and 120 characters.'
      : null;
  String? _length(String? value, int limit) =>
      (value ?? '').trim().length > limit
      ? 'Use at most $limit characters.'
      : null;

  Future<void> _edit(
    String title,
    List<PosFormField> fields,
    Future<void> Function(Map<String, String>) save,
  ) async {
    if (_loading || _settings == null) return;
    final result = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        _dialog = context;
        return PosFormDialog(
          title: title,
          fields: fields,
          errorMessage: _message,
          onSave: (values) async {
            _checkIdentity();
            await save(values);
            _checkIdentity();
          },
        );
      },
    );
    _dialog = null;
    if (result != null &&
        mounted &&
        widget.repository.client.auth.currentUser?.id == _actor) {
      await _refresh();
    }
  }

  Future<void> _editBusiness() async {
    final business = _settings!.business;
    await _edit(
      'Business details',
      [
        PosFormField(
          label: 'Business name',
          initialValue: business.name,
          validator: _name,
        ),
        PosFormField(
          label: 'Business address',
          initialValue: business.address,
          maxLines: 2,
          validator: (v) => _length(v, 300),
        ),
        PosFormField(
          label: 'Contact phone',
          initialValue: business.phone,
          keyboardType: TextInputType.phone,
          validator: (v) => _length(v, 40),
        ),
        PosFormField(
          label: 'Contact email',
          initialValue: business.email,
          keyboardType: TextInputType.emailAddress,
          validator: (v) => (v ?? '').trim().isEmpty
              ? null
              : _length(v, 254) ??
                    (RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v!.trim())
                        ? null
                        : 'Enter a valid email address.'),
        ),
        PosFormField(
          label: 'Receipt footer',
          initialValue: business.footer,
          maxLines: 3,
          validator: (v) => _length(v, 300),
        ),
      ],
      (values) => widget.repository.updateBusiness(
        business,
        name: values['Business name']!,
        address: values['Business address']!,
        phone: values['Contact phone']!,
        email: values['Contact email']!,
        footer: values['Receipt footer']!,
      ),
    );
  }

  Future<void> _editBranch([BranchDetails? branch]) async {
    final businessId = _settings!.business.id;
    // Retain this ID while the same dialog retries a lost response.
    final requestId = WorkspaceRepository.newRequestId();
    await _edit(
      branch == null ? 'Add branch' : 'Edit branch',
      [
        PosFormField(
          label: 'Branch name',
          initialValue: branch?.name ?? '',
          validator: _name,
        ),
        PosFormField(
          label: 'Branch address',
          initialValue: branch?.address ?? '',
          maxLines: 2,
          validator: (v) => _length(v, 300),
        ),
      ],
      (values) => branch == null
          ? widget.repository.createBranch(
              businessId: businessId,
              requestId: requestId,
              name: values['Branch name']!,
              address: values['Branch address']!,
            )
          : widget.repository.updateBranch(
              branch,
              name: values['Branch name']!,
              address: values['Branch address']!,
            ),
    );
  }

  Future<void> _preview(BranchDetails branch) async {
    final details = _settings!.business.receiptFor(branch);
    await showDialog<void>(
      context: context,
      builder: (context) {
        _dialog = context;
        return AlertDialog(
          title: const Text('Receipt preview'),
          scrollable: true,
          content: SelectableText(
            '${details.heading.join('\n')}\n\nSAMPLE · ${branch.name}\n1 × Sample item · ₱25.00\nTotal ₱25.00\nCash ₱30.00\nChange ₱5.00\n\n${details.footer}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
    _dialog = null;
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Business settings'),
        actions: [
          IconButton(
            tooltip: 'Refresh settings',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_loading) const LinearProgressIndicator(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(_error!),
                  ),
                if (settings != null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            settings.business.name,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 12),
                          for (final text in [
                            settings.business.address,
                            settings.business.phone,
                            settings.business.email,
                          ])
                            if (text.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(text),
                              ),
                          const Text('Currency · PHP'),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _loading ? null : _editBusiness,
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Edit business details'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Branches',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      FilledButton.icon(
                        onPressed: _loading ? null : _editBranch,
                        icon: const Icon(Icons.add),
                        label: const Text('Add branch'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  for (final branch in settings.branches)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                branch.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              if (branch.address.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(branch.address),
                                ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton(
                                    onPressed: _loading
                                        ? null
                                        : () => _editBranch(branch),
                                    child: const Text('Edit branch'),
                                  ),
                                  TextButton(
                                    onPressed: _loading
                                        ? null
                                        : () => _preview(branch),
                                    child: const Text('Receipt preview'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Text(
                    'Settings changes require internet. Existing saved receipts keep the details recorded when the sale was made. Assign staff to new branches under Manage staff access.',
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
