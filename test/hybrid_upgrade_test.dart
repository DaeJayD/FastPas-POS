import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/legacy_upgrade_scenario.dart';

void main() {
  sqfliteFfiInit();
  for (final version in [1, 2]) {
    test(
      'Version $version upgrades offline without losing receipts, device identity or deductions',
      () => verifyLegacyUpgrade(databaseFactoryFfi, version),
    );
  }
}
