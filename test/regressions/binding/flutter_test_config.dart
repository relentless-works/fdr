import 'dart:async';

// Unlike test/flutter_test_config.dart, this creates no binding before a
// test file's main() runs: the tests here create a router before there is
// one, as an app's main() does.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await testMain();
}
