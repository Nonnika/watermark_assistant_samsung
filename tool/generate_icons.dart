// ignore_for_file: avoid_print
import 'dart:io';

/// Run the Flutter renderer so every launcher asset uses the same vector artwork.
Future<void> main() async {
  final projectRoot = File.fromUri(Platform.script).parent.parent.path;
  final process = await Process.start(
    'flutter',
    ['test', 'test/generate_icons_test.dart'],
    workingDirectory: projectRoot,
    mode: ProcessStartMode.inheritStdio,
  );
  exitCode = await process.exitCode;
}
