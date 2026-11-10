import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'business_settings.dart';
import 'workspace_repository.dart';

class BranchDevicesDialog extends StatefulWidget {
  const BranchDevicesDialog({
    super.key,
    required this.repository,
    required this.branch,
    required this.ownerId,
  });

  final WorkspaceRepository repository;
  final BranchDetails branch;
  final String ownerId;

  @override
  State<BranchDevicesDialog> createState() => _BranchDevicesDialogState();
}

class _BranchDevicesDialogState extends State<BranchDevicesDialog> {
  static const _pageSize = 50;
  final _devices = <SellingDevice>[];
  bool _loading = false;
  bool _hasMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.repository.branchSellingDevices(
        widget.branch,
        ownerId: widget.ownerId,
        after: _devices.lastOrNull?.id,
      );
      if (mounted) {
        setState(() {
          _devices.addAll(rows.take(_pageSize));
          _hasMore = rows.length > _pageSize;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          if (error is PostgrestException && error.code == '42501') {
            _devices.clear();
            _hasMore = false;
            _error = 'Owner access to this branch is required.';
          } else if (error is PostgrestException && error.code == 'PGRST202') {
            _error =
                'Selling devices will appear after the workspace is updated.';
          } else {
            _error = 'Could not load selling devices. Check your connection and try again.';
          }
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dates = MaterialLocalizations.of(context);
    return AlertDialog(
      title: Text('Selling devices · ${widget.branch.name}'),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) Text(_error!),
            if (!_loading && _error == null && _devices.isEmpty)
              const Text('No selling devices have checked in for this branch.'),
            for (final device in _devices)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Device ${device.deviceId.split('-').first.toUpperCase()}',
                    ),
                    Text(
                      'Last seen ${dates.formatShortDate(device.lastSeen.toLocal())} · '
                      '${dates.formatTimeOfDay(TimeOfDay.fromDateTime(device.lastSeen.toLocal()))}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            if (!_loading && (_hasMore || _error != null))
              TextButton(
                onPressed: _load,
                child: Text(_error != null ? 'Retry' : 'Load more'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
