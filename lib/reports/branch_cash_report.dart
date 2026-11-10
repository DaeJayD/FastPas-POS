import 'package:supabase_flutter/supabase_flutter.dart';

class CashReportTotals {
  const CashReportTotals({
    this.saleCount = 0,
    this.gross = 0,
    this.refundCount = 0,
    this.refunds = 0,
    this.shiftCount = 0,
    this.expected = 0,
    this.counted = 0,
  });

  CashReportTotals.fromJson(Map<String, dynamic> row)
    : saleCount = row['sale_count'] as int,
      gross = row['gross_cents'] as int,
      refundCount = row['refund_count'] as int,
      refunds = row['refund_cents'] as int,
      shiftCount = row['shift_count'] as int,
      expected = row['expected_cents'] as int,
      counted = row['counted_cents'] as int;

  final int saleCount,
      gross,
      refundCount,
      refunds,
      shiftCount,
      expected,
      counted;
  int get net => gross - refunds;
  int get variance => counted - expected;

  CashReportTotals operator +(CashReportTotals other) => CashReportTotals(
    saleCount: saleCount + other.saleCount,
    gross: gross + other.gross,
    refundCount: refundCount + other.refundCount,
    refunds: refunds + other.refunds,
    shiftCount: shiftCount + other.shiftCount,
    expected: expected + other.expected,
    counted: counted + other.counted,
  );
}

class CashReportDay {
  CashReportDay(Map<String, dynamic> row)
    : date = row['day'] as String,
      totals = CashReportTotals.fromJson(row);
  final String date;
  final CashReportTotals totals;
}

class BranchCashReport {
  BranchCashReport(Map<String, dynamic> row)
    : businessId = row['business_id'] as String,
      branchId = row['branch_id'] as String,
      timezone = row['timezone'] as String,
      fromDay = row['from_day'] as String,
      throughDay = row['through_day'] as String,
      days = List.unmodifiable(
        (row['days'] as List).map(
          (day) => CashReportDay(day as Map<String, dynamic>),
        ),
      );

  final String businessId, branchId, timezone, fromDay, throughDay;
  final List<CashReportDay> days;
  CashReportTotals get totals =>
      days.fold(const CashReportTotals(), (sum, day) => sum + day.totals);

  String csv(String branchName) {
    final rows = [
      'date,branch,timezone,currency,sale_count,gross_sales,refund_count,refunds,net_sales,closed_shifts,expected_drawer_cash,counted_drawer_cash,drawer_variance',
      for (final day in days)
        [
          day.date,
          _textCell(branchName),
          _textCell(timezone),
          'PHP',
          day.totals.saleCount,
          _amount(day.totals.gross),
          day.totals.refundCount,
          _amount(day.totals.refunds),
          _amount(day.totals.net),
          day.totals.shiftCount,
          _amount(day.totals.expected),
          _amount(day.totals.counted),
          _amount(day.totals.variance),
        ].join(','),
    ];
    return '${rows.join('\r\n')}\r\n';
  }

  static String _textCell(String value) {
    // Keep spreadsheet applications from interpreting a business label as a formula.
    final safe = RegExp(r'^[\s\uFEFF]*[=+@-]').hasMatch(value)
        ? "'$value"
        : value;
    return '"${safe.replaceAll('"', '""')}"';
  }

  static String _amount(int cents) {
    final magnitude = cents.abs();
    return '${cents < 0 ? '-' : ''}${magnitude ~/ 100}.${(magnitude % 100).toString().padLeft(2, '0')}';
  }
}

class BranchCashReportRepository {
  BranchCashReportRepository(this.client, this.businessId, this.actor);
  final SupabaseClient client;
  final String businessId, actor;

  void checkAccount() {
    if (client.auth.currentUser?.id != actor) {
      throw const FormatException(
        'Account changed. Return to your businesses.',
      );
    }
  }

  Future<BranchCashReport> load({
    required String branchId,
    required String timezone,
    required String? fromDay,
    required String? throughDay,
  }) async {
    checkAccount();
    final data = await client
        .rpc(
          'pos_branch_cash_report',
          params: {
            'p_business': businessId,
            'p_branch': branchId,
            'p_timezone': timezone,
            'p_from': fromDay,
            'p_through': throughDay,
          },
        )
        .timeout(const Duration(seconds: 12));
    checkAccount();
    final report = BranchCashReport(data as Map<String, dynamic>);
    if (report.businessId != businessId ||
        report.branchId != branchId ||
        report.timezone != timezone ||
        (fromDay != null && report.fromDay != fromDay) ||
        (throughDay != null && report.throughDay != throughDay)) {
      throw const FormatException(
        'The report did not match the selected branch and dates.',
      );
    }
    return report;
  }
}
