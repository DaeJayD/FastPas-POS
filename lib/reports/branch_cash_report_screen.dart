import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../hybrid/cash_rules.dart';
import '../workspaces/workspace_repository.dart';
import 'branch_cash_report.dart';

class BranchCashReportScreen extends StatefulWidget {
  const BranchCashReportScreen({
    super.key,
    required this.repository,
    required this.branches,
  }) : assert(branches.length > 0);

  final BranchCashReportRepository repository;
  final List<WorkspaceBranch> branches;

  @override
  State<BranchCashReportScreen> createState() => _BranchCashReportScreenState();
}

class _BranchCashReportScreenState extends State<BranchCashReportScreen> {
  final _timezone = TextEditingController(text: 'Asia/Manila');
  late WorkspaceBranch _branch = widget.branches.first;
  DateTimeRange? _range;
  BranchCashReport? _report;
  StreamSubscription<AuthState>? _auth;
  String? _error;
  int _request = 0;
  bool _loading = false, _exporting = false, _accountChanged = false;

  @override
  void initState() {
    super.initState();
    _auth = widget.repository.client.auth.onAuthStateChange.listen(
      (event) {
        if (!mounted || event.session?.user.id == widget.repository.actor) {
          return;
        }
        ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
        setState(() {
          _clearReport();
          _accountChanged = true;
          _error = 'Account changed. Return to your businesses.';
        });
      },
      onError: (_) {
        if (!mounted || _accountChanged) return;
        setState(() {
          _clearReport();
          _error = 'Could not refresh your session. Reconnect and run the report again.';
        });
      },
    );
    unawaited(_load());
  }

  @override
  void dispose() {
    _auth?.cancel();
    _timezone.dispose();
    super.dispose();
  }

  String _date(DateTime date) => date.toIso8601String().split('T').first;

  Future<void> _pickDates() async {
    final previous = _report;
    final now = DateTime.now().toUtc();
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year, now.month, now.day + 1),
      initialDateRange:
          _range ??
          (previous == null
              ? null
              : DateTimeRange(
                  start: DateTime.parse(previous.fromDay),
                  end: DateTime.parse(previous.throughDay),
                )),
    );
    if (result == null || !mounted || _accountChanged) return;
    _range = result;
    await _load();
  }

  void _clearReport() {
    _request++;
    _report = null;
    _error = null;
    _loading = false;
  }

  Future<void> _load() async {
    if (_accountChanged) return;
    final request = ++_request;
    final range = _range;
    setState(() {
      _loading = true;
      _report = null;
      _error = null;
    });
    try {
      final report = await widget.repository.load(
        branchId: _branch.id,
        timezone: _timezone.text.trim(),
        fromDay: range == null ? null : _date(range.start),
        throughDay: range == null ? null : _date(range.end),
      );
      if (mounted && _request == request) setState(() => _report = report);
    } catch (error) {
      if (mounted && _request == request) {
        setState(() => _error = _message(error));
      }
    } finally {
      if (mounted && _request == request) setState(() => _loading = false);
    }
  }

  String _message(Object error) {
    if (error is FormatException) return error.message;
    if (error is PostgrestException) {
      switch (error.code) {
        case '42501':
          return 'A branch owner or assigned manager can view this report.';
        case '22023':
          return error.message;
        case 'PGRST202':
          return 'Cash reports are not available on this server yet.';
      }
    }
    return 'Could not load the report. Check your connection and retry.';
  }

  Future<void> _export() async {
    final report = _report;
    if (report == null || _exporting || _accountChanged) return;
    final branchName = _branch.name;
    setState(() => _exporting = true);
    try {
      widget.repository.checkAccount();
      final directory = await getApplicationDocumentsDirectory();
      widget.repository.checkAccount();
      final filename =
          'fastpas-cash-report-${DateTime.now().millisecondsSinceEpoch}.csv';
      final file = File('${directory.path}/$filename');
      await file.writeAsString(report.csv(branchName), flush: true);
      widget.repository.checkAccount();
      if (!mounted || _accountChanged) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved $filename'),
          action: SnackBarAction(
            label: 'Open CSV',
            onPressed: () async {
              if (_accountChanged || !mounted) return;
              try {
                widget.repository.checkAccount();
                final result = await OpenFile.open(file.path, type: 'text/csv');
                if (result.type == ResultType.done) return;
              } catch (_) {
                // The report file is already saved.
              }
              if (mounted && !_accountChanged) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('No app could open the saved CSV.'),
                  ),
                );
              }
            },
          ),
        ),
      );
    } catch (_) {
      if (mounted && !_accountChanged) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the CSV. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _header(BranchCashReport? report) {
    final range = _range;
    final totals = report?.totals;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<WorkspaceBranch>(
          initialValue: _branch,
          decoration: const InputDecoration(labelText: 'Branch'),
          isExpanded: true,
          items: [
            for (final branch in widget.branches)
              DropdownMenuItem(
                value: branch,
                child: Text(branch.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (branch) {
            if (branch == null) return;
            _branch = branch;
            unawaited(_load());
          },
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _pickDates,
          icon: const Icon(Icons.date_range_outlined),
          label: Text(
            range == null
                ? 'Last 7 days'
                : '${_date(range.start)} to ${_date(range.end)}',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _timezone,
          decoration: const InputDecoration(
            labelText: 'Reporting time zone',
            hintText: 'Asia/Manila',
          ),
          onChanged: (_) => setState(_clearReport),
          onSubmitted: (_) => _load(),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _loading ? null : _load,
          child: const Text('Run report'),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (report != null && totals != null) ...[
          const SizedBox(height: 16),
          Text(
            '${report.fromDay} to ${report.throughDay} · ${report.timezone}',
          ),
          const Text('Synced cash transactions'),
          const SizedBox(height: 12),
          Text(
            'Net cash sales ${displayCents(totals.net)}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            'Gross sales ${displayCents(totals.gross)} · ${totals.saleCount} receipts',
          ),
          Text(
            'Refunds ${displayCents(totals.refunds)} · ${totals.refundCount} returns',
          ),
          const SizedBox(height: 8),
          Text('Closed drawers · ${totals.shiftCount}'),
          Text(
            'Expected ${displayCents(totals.expected)} · Counted ${displayCents(totals.counted)}',
          ),
          Text('Drawer variance ${displayCents(totals.variance)}'),
          OutlinedButton.icon(
            onPressed: _exporting ? null : _export,
            icon: const Icon(Icons.download_outlined),
            label: const Text('Save CSV'),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('Branch cash report')),
      body: SafeArea(
        child: _accountChanged
            ? Padding(padding: const EdgeInsets.all(20), child: Text(_error!))
            : ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: 1 + (report?.days.length ?? 0),
                itemBuilder: (context, index) {
                  if (index == 0) return _header(report);
                  final day = report!.days[index - 1];
                  return Card(
                    child: ListTile(
                      title: Text(day.date),
                      subtitle: Text(
                        '${day.totals.saleCount} sales · ${day.totals.refundCount} returns'
                        '\nGross ${displayCents(day.totals.gross)} · Refunds ${displayCents(day.totals.refunds)}'
                        '\nNet ${displayCents(day.totals.net)} · Drawer variance ${displayCents(day.totals.variance)}',
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
