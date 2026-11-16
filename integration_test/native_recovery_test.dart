import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';

import '../test/support/legacy_upgrade_scenario.dart';
import '../test/support/ambiguous_upload_scenario.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final version in [1, 2]) {
    testWidgets(
      'Android upgrades SQLite v$version without losing pending cash sales',
      (tester) async => verifyLegacyUpgrade(databaseFactory, version),
    );
  }

  testWidgets(
    'Android retries a committed sale across reopen without double deduction',
    (tester) async => verifyAmbiguousUpload(databaseFactory),
  );
}
