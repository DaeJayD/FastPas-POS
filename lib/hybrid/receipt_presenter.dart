import '../core/receipt_details.dart';
import 'cash_rules.dart';

String receiptText(Map<String, dynamic> sale, int totalCents) {
  final recorded = sale['receipt_details'];
  final details = recorded is Map
      ? ReceiptDetails.fromJson(Map<String, dynamic>.from(recorded))
      : null;
  details?.checkScope(
    sale['business_id'] as String,
    sale['branch_id'] as String,
  );
  final cash = sale['cash_cents'] as int;
  return [
    if (details != null) ...details.heading,
    'Receipt ${sale['id']}',
    '${sale['occurred_at']}',
    '',
    for (final line in sale['items'] as List)
      '${line['quantity']} × ${line['name']} · ${displayCents(line['unit_cents'] as int)}',
    '',
    'Total ${displayCents(totalCents)}',
    'Cash ${displayCents(cash)}',
    'Change ${displayCents(cash - totalCents)}',
    if (details != null && details.footer.isNotEmpty) ...['', details.footer],
  ].join('\n');
}
