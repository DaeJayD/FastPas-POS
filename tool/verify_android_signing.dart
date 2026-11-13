import 'dart:convert';
import 'dart:io';

/// Reproduces the environment boundary used by Flutter when launching Gradle.
Future<void> main() async {
  final environment = Platform.environment;
  final supplied = environment.keys.map((key) => key.toUpperCase()).toSet();
  if (!supplied.contains('ORG_GRADLE_PROJECT_FASTPASSIGNINGPROPERTIES') ||
      !supplied.contains('ORG_GRADLE_PROJECT_FASTPASAPPLICATIONID')) {
    stderr.writeln(
      'Set the signing-properties path and application ID from docs/RELEASE.md.',
    );
    exitCode = 2;
    return;
  }
  final process = await Process.start(
    File(Platform.isWindows ? r'android\gradlew.bat' : 'android/gradlew')
        .absolute
        .path,
    [
      '-p',
      'android',
      ':app:validateSigningRelease',
      '--console=plain',
      '--no-configuration-cache',
    ],
    environment: environment,
    runInShell: Platform.isWindows,
  );
  Future<void> printSignals(Stream<List<int>> stream) async {
    await for (final line
        in stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.contains('validateSigningRelease') ||
          line.contains('validateFastpasRelease') ||
          line.contains('BUILD SUCCESSFUL') ||
          line.contains('Configure release signing') ||
          line.contains('Set the final Android ID') ||
          line.contains('not recognized')) {
        stdout.writeln(line);
      }
    }
  }

  await Future.wait([
    printSignals(process.stdout),
    printSignals(process.stderr),
  ]);
  exitCode = await process.exitCode;
  stdout.writeln(
    exitCode == 0
        ? 'Signing validation passed through the Dart launcher.'
        : 'Signing validation failed through the Dart launcher.',
  );
}
