import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// the plugins flutter registers for this app; it has none of its own, so
// these are the ones every app gets from fdr
void main() {
  test('fdr brings no native plugins, and url_launcher_web on the web', () {
    final file = File('.flutter-plugins-dependencies');
    final plugins = (jsonDecode(file.readAsStringSync()) as Map)['plugins'];
    List<Object?> names(String platform) => [
      for (final plugin in plugins[platform] as List) (plugin as Map)['name'],
    ];
    for (final platform in ['android', 'ios', 'linux', 'macos', 'windows']) {
      expect(names(platform), isEmpty, reason: platform);
    }
    expect(names('web'), ['url_launcher_web']);
  });
}
