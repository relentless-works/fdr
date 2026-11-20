// ignore_for_file: unused_element

import 'dart:io';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fdr/fdr.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const size = Size(375, 600);

  final android = (
    platform: TargetPlatform.android,
    backButton: find.byType(BackButtonIcon),
    toggle: find.byType(Switch),
  );
  final iOS = (
    platform: TargetPlatform.iOS,
    backButton: find.text(String.fromCharCode(CupertinoIcons.back.codePoint)),
    toggle: find.byType(CupertinoSwitch),
  );

  // TODO: Would be better to use `TestVariant` once https://github.com/eBay/flutter_glove_box/issues/179 is fixed
  Future<void> Function(WidgetTester) onPlatform(
    TargetPlatform platform,
    Future<void> Function(WidgetTester) body,
  ) => (tester) async {
    debugDefaultTargetPlatformOverride = platform;
    // reset also when the test fails, which would otherwise fail on it too
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await body(tester);
  };

  Future<void> pumpNavigator(
    WidgetTester tester,
    TargetPlatform platform,
  ) async {
    await tester.pumpWidgetBuilder(
      DeclarativeNavigator(navigator: _Navigator()),
      surfaceSize: size,
      // golden_toolkit's default wrapper is a MaterialApp of the deprecated
      // package:flutter/material, whose localizations material_ui's AppBar
      // does not see; this is the same app from material_ui
      wrapper: platform == TargetPlatform.iOS
          ? (child) =>
                CupertinoApp(home: child, debugShowCheckedModeBanner: false)
          : (child) => MaterialApp(
              home: Material(child: child),
              debugShowCheckedModeBanner: false,
            ),
    );
  }

  group('Dynamic back button', () {
    for (final (:platform, :backButton, :toggle) in [android, iOS]) {
      testWidgets(
        '${platform.name}: shown once the page has onPop, and pops '
        'the page',
        onPlatform(platform, (tester) async {
          await pumpNavigator(tester, platform);
          expect(backButton, findsNothing);

          await tester.tap(toggle);
          await tester.pumpAndSettle();
          expect(backButton, findsOneWidget);

          await tester.tap(backButton);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          final page = ModalRoute.of(tester.element(find.byType(_SwitchPage)))!;
          expect(page.animation!.status, AnimationStatus.reverse);

          await tester.pumpAndSettle();
          expect(find.byType(_SwitchPage), findsNothing);
          expect(find.text('Home'), findsOneWidget);
        }),
      );
    }

    // The goldens were rendered on macOS, where CI runs: text renders
    // differently on other hosts. A frame in the middle of a page
    // transition is not compared, as it shows the SDK's transition more
    // than fdr (the test above checks that the page animates out).
    final skipGoldens = !Platform.isMacOS;

    testGoldens(
      'Android',
      onPlatform(TargetPlatform.android, (tester) async {
        await pumpNavigator(tester, TargetPlatform.android);
        await screenMatchesGolden(tester, 'dynamic_back_button/android/01_off');
        await tester.tap(android.toggle);
        await screenMatchesGolden(tester, 'dynamic_back_button/android/02_on');
      }),
      skip: skipGoldens,
    );

    testGoldens(
      'iOS',
      onPlatform(TargetPlatform.iOS, (tester) async {
        await pumpNavigator(tester, TargetPlatform.iOS);
        await screenMatchesGolden(tester, 'dynamic_back_button/ios/01_off');
        await tester.tap(iOS.toggle);
        await screenMatchesGolden(tester, 'dynamic_back_button/ios/02_on');
      }),
      skip: skipGoldens,
    );
  });
}

class _PlatformScaffold extends StatelessWidget {
  const _PlatformScaffold({required this.title, required this.child});

  final Widget title;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return Scaffold(
        appBar: AppBar(title: title),
        body: child,
      );
    }

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: title),
      child: SafeArea(child: child),
    );
  }
}

class _Navigator extends StatefulNavigator<Never> {
  @override
  StatefulNavigatorState<_Navigator, Never> createState() => _NavigatorState();
}

class _NavigatorState extends StatefulNavigatorState<_Navigator, Never> {
  bool showChild = true;
  bool canPop = false;

  @override
  List<NavEntry<Never>> build() {
    return [
      const NavPage(
        child: _PlatformScaffold(
          title: Text('Home'),
          child: ColoredBox(color: Colors.blue),
        ),
      ),
      if (showChild)
        NavPage(
          onPop: canPop ? () => setState(() => showChild = false) : null,
          child: _SwitchPage(
            canPop: canPop,
            onCanPopChanged: (v) => setState(() => canPop = v),
          ),
        ),
    ];
  }
}

class _SwitchPage extends StatelessWidget {
  const _SwitchPage({required this.canPop, required this.onCanPopChanged});

  final bool canPop;
  final ValueSetter<bool> onCanPopChanged;

  @override
  Widget build(BuildContext context) {
    return _PlatformScaffold(
      title: const Text('Can pop test'),
      child: defaultTargetPlatform == TargetPlatform.android
          ? Switch.adaptive(
              // as this crashed in pure Cupertino setup
              value: canPop,
              onChanged: onCanPopChanged,
            )
          : CupertinoSwitch(value: canPop, onChanged: onCanPopChanged),
    );
  }
}
