// ignore_for_file: unused_element

import 'package:fdr/fdr.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';

void main() {
  const size = Size(375, 600);

  group('Dynamic back button', () {
    testGoldens('Android', (tester) async {
      // TODO: Would be better to use `TestVariant` once https://github.com/eBay/flutter_glove_box/issues/179 is fixed
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      await tester.pumpWidgetBuilder(
        DeclarativeNavigator.managing(
          navigatorFactory: () => _Navigator(),
        ),
        surfaceSize: size,
      );

      final backButtonFinder = find.byType(BackButtonIcon);

      await screenMatchesGolden(tester, 'dynamic_back_button/android/01_off');

      expect(backButtonFinder, findsNothing);

      await tester.tap(find.byType(Switch));

      await screenMatchesGolden(tester, 'dynamic_back_button/android/02_on');

      expect(backButtonFinder, findsOneWidget);

      await tester.tap(backButtonFinder);

      await screenMatchesGolden(
        tester,
        'dynamic_back_button/android/03_transitioning_out',
        customPump: (tester) async {
          await tester.pump();

          await tester.pump(const Duration(milliseconds: 50));
        },
      );

      await tester.pumpAndSettle();

      debugDefaultTargetPlatformOverride = null;
    });

    testGoldens('iOS', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      await tester.pumpWidgetBuilder(
        DeclarativeNavigator.managing(
          navigatorFactory: () => _Navigator(),
        ),
        surfaceSize: size,
        wrapper: (child) => CupertinoApp(
          home: child,
          debugShowCheckedModeBanner: false,
        ),
      );

      final backButtonFinder =
          find.text(String.fromCharCode(CupertinoIcons.back.codePoint));

      await screenMatchesGolden(tester, 'dynamic_back_button/ios/01_off');

      expect(backButtonFinder, findsNothing);

      await tester.tap(find.byType(CupertinoSwitch));

      await screenMatchesGolden(tester, 'dynamic_back_button/ios/02_on');

      expect(backButtonFinder, findsOneWidget);

      await tester.tap(backButtonFinder);

      await screenMatchesGolden(
          tester, 'dynamic_back_button/ios/03_transitioning_out',
          customPump: (tester) async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
      });

      await tester.pumpAndSettle();

      debugDefaultTargetPlatformOverride = null;
    });
  });
}

class _PlatformScaffold extends StatelessWidget {
  const _PlatformScaffold({
    super.key,
    required this.title,
    required this.child,
  });

  final Widget title;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return Scaffold(
        appBar: AppBar(
          title: title,
        ),
        body: child,
      );
    }

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: title,
      ),
      child: SafeArea(child: child),
    );
  }
}

class _Navigator extends MappedNavigatableSource<
    (
      bool /* show child */,
      bool
      /* can pop */
    )> {
  _Navigator() : super(initialState: (true, false));

  @override
  List<DeclarativeNavigatable> build((bool, bool) state) {
    return [
      const _PlatformScaffold(
        title: Text('Home'),
        child: ColoredBox(color: Colors.blue),
      ).page(onPop: null),
      if (state.$1)
        _SwitchPage(
          canPop: state.$2,
          onCanPopChanged: (v) => this.state = (true, v),
        ).page(onPop: state.$2 ? () => this.state = (false, false) : null),
    ];
  }
}

class _SwitchPage extends StatelessWidget {
  const _SwitchPage({
    super.key,
    required this.canPop,
    required this.onCanPopChanged,
  });

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
          : CupertinoSwitch(
              value: canPop,
              onChanged: onCanPopChanged,
            ),
    );
  }
}
