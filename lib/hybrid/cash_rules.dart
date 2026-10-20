int parseCents(String text) {
  final value = text.trim();
  if (!RegExp(r'^\d{1,11}(\.\d{1,2})?$').hasMatch(value)) {
    throw const FormatException(
      'Enter an amount with at most two decimal places.',
    );
  }
  final parts = value.split('.');
  return int.parse(parts.first) * 100 +
      (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
}

String displayCents(int value) =>
    '₱${value < 0 ? '-' : ''}'
    '${value.abs() ~/ 100}.${(value.abs() % 100).toString().padLeft(2, '0')}';
