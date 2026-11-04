class SavedReceipt {
  SavedReceipt(Map<String, Object?> row)
    : sequence = row['sequence'] as int,
      id = row['id'] as String,
      totalCents = row['total_cents'] as int,
      status = row['status'] as String,
      error = row['error'] as String?;
  final int sequence, totalCents;
  final String id, status;
  final String? error;
}

class ReceiptPage {
  ReceiptPage(List<SavedReceipt> entries, this.nextBefore)
    : entries = List.unmodifiable(entries);
  final List<SavedReceipt> entries;
  final int? nextBefore;
}

class ReceiptCounts {
  const ReceiptCounts({this.pending = 0, this.synced = 0, this.blocked = 0});
  final int pending, synced, blocked;
  int get total => pending + synced + blocked;
}

String receiptStatusLabel(String status) => switch (status) {
  'pending' => 'Pending upload',
  'synced' => 'Synced',
  'blocked' => 'Needs review',
  _ => status,
};
