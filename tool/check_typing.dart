// Checks that the mistakes in tool/typing/mistakes.dart.fixture fail to
// compile, each line with the diagnostic it is marked with, and that nothing
// else fails. Run from the repository root: `dart run tool/check_typing.dart`.
import 'dart:io';

void main() {
  final fixture = File('tool/typing/mistakes.dart.fixture');
  // inside the example package, so the fixture can use its demo types
  final target = File('example/lib/typing_mistakes.dart');
  fixture.copySync(target.path);
  final ProcessResult result;
  try {
    result = Process.runSync('dart', [
      'analyze',
      '--format=machine',
      'lib/typing_mistakes.dart',
    ], workingDirectory: 'example');
  } finally {
    target.deleteSync();
  }

  final expected = <int, Set<String>>{};
  for (final (index, line) in fixture.readAsLinesSync().indexed) {
    final marker = RegExp(r'// error: ([a-z_]+(?:, [a-z_]+)*)$')
        .firstMatch(line);
    if (marker == null) continue;
    expected[index + 1] = {
      for (final code in marker.group(1)!.split(',')) code.trim(),
    };
  }

  final actual = <int, Set<String>>{};
  for (final line in '${result.stdout}${result.stderr}'.split('\n')) {
    final fields = line.split('|');
    if (fields.length < 8 || fields[0] != 'ERROR') continue;
    actual
        .putIfAbsent(int.parse(fields[4]), () => {})
        .add(fields[2].toLowerCase());
  }

  var failed = false;
  for (final MapEntry(key: line, value: codes) in expected.entries) {
    final missing = codes.difference(actual[line] ?? const {});
    stdout.writeln(
      '${missing.isEmpty ? 'ok  ' : 'FAIL'} line $line: ${codes.join(', ')}',
    );
    failed |= missing.isNotEmpty;
  }
  for (final MapEntry(key: line, value: codes) in actual.entries) {
    if (expected.containsKey(line)) continue;
    stdout.writeln('FAIL unexpected error on line $line: ${codes.join(', ')}');
    failed = true;
  }
  if (failed) exitCode = 1;
}
