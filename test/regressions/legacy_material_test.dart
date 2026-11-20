// An app still on the deprecated package:flutter/material and cupertino
// libraries: their Theme, localizations and navigation bar are other classes
// than the material_ui and cupertino_ui ones fdr works with.
// ignore_for_file: deprecated_member_use

import 'package:cupertino_ui/cupertino_ui.dart' as cupertino_ui;
import 'package:fdr/fdr.dart';
import 'package:flutter/cupertino.dart' as legacy;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as legacy;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as material_ui;

class _Nav extends StatefulNavigator<Never> {
  const _Nav(this.builder);

  final List<NavEntry<Never>> Function(_NavState state) builder;

  @override
  _NavState createState() => _NavState();
}

class _NavState extends StatefulNavigatorState<_Nav, Never> {
  bool detail = true;

  @override
  List<NavEntry<Never>> build() => navigator.builder(this);
}

Widget _nav(List<NavEntry<Never>> Function(_NavState state) builder) =>
    DeclarativeNavigator(navigator: _Nav(builder));

ModalRoute<Object?> _routeOf(WidgetTester tester, String text) =>
    ModalRoute.of(tester.element(find.text(text)))!;

class _Delegate<T> extends LocalizationsDelegate<T> {
  const _Delegate(this.localizations);

  final T localizations;

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<T> load(Locale locale) => SynchronousFuture(localizations);

  @override
  bool shouldReload(_Delegate<T> old) => false;
}

class _LegacyGerman extends legacy.DefaultMaterialLocalizations {
  @override
  String get modalBarrierDismissLabel => 'Schließen';
}

class _German extends material_ui.DefaultMaterialLocalizations {
  @override
  String get modalBarrierDismissLabel => 'Schließen';
}

void main() {
  final material = isA<material_ui.MaterialRouteTransitionMixin<Object?>>();
  final cupertino = isA<cupertino_ui.CupertinoRouteTransitionMixin<Object?>>();

  Future<void> pump(WidgetTester tester, Widget app) async {
    // a fresh Navigator: an existing route keeps its type
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  }

  testWidgets('NavPage takes the platform, not the Theme of a legacy app', (
    tester,
  ) async {
    Future<Route<Object?>> routeWith(TargetPlatform themePlatform) async {
      await pump(
        tester,
        legacy.MaterialApp(
          theme: legacy.ThemeData(platform: themePlatform),
          home: _nav((_) => [const NavPage(child: Text('page'))]),
        ),
      );
      return _routeOf(tester, 'page');
    }

    // the tests run on Android
    expect(await routeWith(TargetPlatform.iOS), material);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      expect(await routeWith(TargetPlatform.android), cupertino);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('DialogPage labels its barrier in English in a legacy app', (
    tester,
  ) async {
    final home = _nav(
      (_) => [
        const NavPage(child: Text('home')),
        const DialogPage(child: Text('dialog')),
      ],
    );

    await pump(
      tester,
      legacy.MaterialApp(
        localizationsDelegates: [
          _Delegate<legacy.MaterialLocalizations>(_LegacyGerman()),
        ],
        home: home,
      ),
    );
    expect(_routeOf(tester, 'dialog').barrierLabel, 'Dismiss');

    await pump(
      tester,
      material_ui.MaterialApp(
        localizationsDelegates: [
          _Delegate<material_ui.MaterialLocalizations>(_German()),
        ],
        home: home,
      ),
    );
    expect(_routeOf(tester, 'dialog').barrierLabel, 'Schließen');
  });

  testWidgets('a legacy AppBar shows the back button only with onPop', (
    tester,
  ) async {
    Widget app({required bool poppable}) => legacy.MaterialApp(
      home: _nav(
        (s) => [
          const NavPage(child: Text('home')),
          if (s.detail)
            NavPage(
              onPop: poppable ? () => s.setState(() => s.detail = false) : null,
              child: legacy.Scaffold(appBar: legacy.AppBar()),
            ),
        ],
      ),
    );

    await pump(tester, app(poppable: false));
    expect(find.byType(legacy.BackButton), findsNothing);

    await pump(tester, app(poppable: true));
    await tester.tap(find.byType(legacy.BackButton));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('a legacy CupertinoNavigationBar shows no page titles', (
    tester,
  ) async {
    List<NavEntry<Never>> pages(_NavState s, Widget scaffold, bool poppable) =>
        [
          const NavPage.cupertino(title: 'Orders', child: SizedBox()),
          if (s.detail)
            NavPage.cupertino(
              title: 'Order 7',
              onPop: poppable ? () => s.setState(() => s.detail = false) : null,
              child: scaffold,
            ),
        ];

    await pump(
      tester,
      cupertino_ui.CupertinoApp(
        home: _nav(
          (s) => pages(
            s,
            const cupertino_ui.CupertinoPageScaffold(
              navigationBar: cupertino_ui.CupertinoNavigationBar(),
              child: SizedBox(),
            ),
            true,
          ),
        ),
      ),
    );
    expect(find.text('Order 7'), findsOneWidget);
    // the back label
    expect(find.text('Orders'), findsOneWidget);

    Widget legacyApp({required bool poppable}) => legacy.CupertinoApp(
      home: _nav(
        (s) => pages(
          s,
          const legacy.CupertinoPageScaffold(
            navigationBar: legacy.CupertinoNavigationBar(),
            child: SizedBox(),
          ),
          poppable,
        ),
      ),
    );

    await pump(tester, legacyApp(poppable: false));
    expect(find.byType(legacy.CupertinoNavigationBarBackButton), findsNothing);

    await pump(tester, legacyApp(poppable: true));
    expect(find.text('Order 7'), findsNothing);
    expect(find.text('Orders'), findsNothing);
    await tester.tap(find.byType(legacy.CupertinoNavigationBarBackButton));
    await tester.pumpAndSettle();
    expect(find.byType(legacy.CupertinoPageScaffold), findsNothing);
  });
}
