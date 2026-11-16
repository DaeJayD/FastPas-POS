import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/ambiguous_upload_scenario.dart';

void main() {
  sqfliteFfiInit();
  test(
    'A committed cash sale recovers across reopen and concurrent connections',
    () => verifyAmbiguousUpload(databaseFactoryFfi),
  );
}
