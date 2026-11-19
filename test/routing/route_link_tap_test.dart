import 'package:fdr/src/core/core.dart' show LinkTap, linkTap;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

// What a tap on a RouteLink does on the web, by the modifier keys held. The
// widget only takes this branch on the web, which VM tests do not run.
void main() {
  test('a tap without modifiers (or with alt) opens in the app', () {
    for (final platform in TargetPlatform.values) {
      expect(linkTap(platform), LinkTap.open, reason: '$platform');
    }
  });

  test('shift-click opens a new window everywhere', () {
    for (final platform in TargetPlatform.values) {
      expect(
        linkTap(platform, shift: true),
        LinkTap.newTab,
        reason: '$platform',
      );
    }
  });

  test('on macOS, cmd-click is a new tab, ctrl-click a right click', () {
    const macOS = TargetPlatform.macOS;
    expect(linkTap(macOS, meta: true), LinkTap.newTab);
    expect(linkTap(macOS, meta: true, shift: true), LinkTap.newTab);
    expect(linkTap(macOS, control: true), LinkTap.contextMenu);
    expect(linkTap(macOS, control: true, meta: true), LinkTap.contextMenu);
  });

  test('elsewhere, ctrl-click opens a new tab', () {
    for (final platform in [
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.android,
      TargetPlatform.fuchsia,
    ]) {
      expect(
        linkTap(platform, control: true),
        LinkTap.newTab,
        reason: '$platform',
      );
      expect(
        linkTap(platform, control: true, shift: true),
        LinkTap.newTab,
        reason: '$platform',
      );
    }
  });

  test('on iOS, cmd-click opens a new tab', () {
    expect(linkTap(TargetPlatform.iOS, meta: true), LinkTap.newTab);
  });
}
