import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'routes.dart';

// a guard in build: C is not allowed and redirects to B
class Root extends StatefulNavigator<RR> {
  const Root({this.loop = false});
  final bool loop;
  @override
  RootState createState() => RootState();
}

class RootState extends StatefulNavigatorState<Root, RR> {
  static late RootState latest;
  static final builds = <String>[];
  RR shown = const RA();
  // opened by the next build, which shows what the one before did
  RR? kick;

  @override
  void initState() {
    super.initState();
    latest = this;
  }

  @override
  void applyRoute(RR route) => shown = route;

  @override
  List<NavEntry<RR>> build() {
    final shown = this.shown;
    builds.add('${shown.runtimeType}');
    if (kick case final to?) {
      kick = null;
      open(to, history: HistoryAction.replace);
    }
    if (shown is RC) open(const RB(), history: HistoryAction.replace);
    if (shown is RB && navigator.loop) {
      open(const RC(), history: HistoryAction.replace);
    }
    return [
      NavPage(route: const RA(), child: scaffold('A')),
      if (shown is RB) NavPage(route: const RB(), child: scaffold('B')),
      if (shown is RC) NavPage(route: const RC(), child: scaffold('C')),
      const Side(),
    ];
  }
}

// rebuilds with the root's state, to start a deferred rebuild of the root
class Side extends StatefulNavigator<Never> {
  const Side();
  @override
  SideState createState() => SideState();
}

class SideState extends StatefulNavigatorState<Side, Never> {
  static late SideState latest;
  bool poke = false;

  @override
  void initState() {
    super.initState();
    latest = this;
  }

  @override
  List<NavEntry<Never>> build() {
    if (poke) {
      poke = false;
      final root = RootState.latest;
      root.setState(() => root.shown = const RC());
    }
    return const [];
  }
}

// a child whose build redirects to a route that removes it
class Outer extends StatefulNavigator<RR> {
  const Outer();
  @override
  OuterState createState() => OuterState();
}

class OuterState extends StatefulNavigatorState<Outer, RR> {
  RR shown = const RA();

  @override
  void applyRoute(RR route) => shown = route;

  @override
  List<NavEntry<RR>> build() => [
    NavPage(route: const RA(), child: scaffold('A')),
    if (shown is RB)
      NavPage(route: const RB(), child: scaffold('B'))
    else
      const Inner(),
  ];
}

class Inner extends StatefulNavigator<RR> {
  const Inner();
  @override
  InnerState createState() => InnerState();
}

class InnerState extends StatefulNavigatorState<Inner, RR> {
  static late InnerState latest;
  bool go = false;

  @override
  void initState() {
    super.initState();
    latest = this;
  }

  @override
  void applyRoute(RR route) {}

  @override
  List<NavEntry<RR>> build() {
    if (go) open(const RB());
    return [NavPage(child: scaffold('inner'))];
  }
}

Future<FdrRouter<RR>> start(
  WidgetTester tester,
  StatefulNavigator<RR> root,
) async {
  tester.binding.platformDispatcher.defaultRouteNameTestValue = '/';
  addTearDown(tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
  final router = FdrRouter<RR>(root: root, fromUrl: RR.fromUrl);
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
  await tester.pump();
  expect(router.currentUrl, '/');
  RootState.builds.clear();
  return router;
}

void expectRedirectedToB(WidgetTester tester, FdrRouter<RR> router) {
  expect(tester.takeException(), isNull);
  // the build for C, then the one of the redirect, which is the last word
  expect(RootState.builds, ['RC', 'RB']);
  expect(RootState.latest.shown, isA<RB>());
  expect(router.currentUrl, '/b');
  expect(find.text('B'), findsOneWidget);
  expect(find.text('C'), findsNothing);
  // the replace is for C, which was never reported: A keeps its entry
  expect(router.provider.shadowHistory, ['/', '/b']);
}

void main() {
  testWidgets('an open() in a build started by router.open redirects', (
    tester,
  ) async {
    final router = await start(tester, const Root());
    router.open(const RC());
    await tester.pumpAndSettle();
    expectRedirectedToB(tester, router);
  });

  testWidgets('an open() in a build started by setState redirects', (
    tester,
  ) async {
    final router = await start(tester, const Root());
    final root = RootState.latest;
    root.setState(() => root.shown = const RC());
    await tester.pumpAndSettle();
    expectRedirectedToB(tester, router);
  });

  testWidgets('an open() in a build started by a deferred rebuild redirects', (
    tester,
  ) async {
    final router = await start(tester, const Root());
    final side = SideState.latest;
    // the root's setState in Side's build waits for Side's update
    side.setState(() => side.poke = true);
    await tester.pumpAndSettle();
    expectRedirectedToB(tester, router);
  });

  testWidgets('a redirect with replace in a build that shows nothing new '
      'replaces the current entry', (tester) async {
    final router = await start(tester, const Root());
    router.open(const RB());
    await tester.pumpAndSettle();
    expect(router.provider.shadowHistory, ['/', '/b']);

    // B is the reported entry, and the build that redirects still shows it
    final root = RootState.latest;
    root.setState(() => root.kick = const RA());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(router.currentUrl, '/');
    expect(router.provider.shadowHistory, ['/', '/']);
  });

  testWidgets('a navigator can redirect in its build to a route that '
      'removes it', (tester) async {
    final router = await start(tester, const Outer());
    expect(find.text('inner'), findsOneWidget);

    final inner = InnerState.latest;
    inner.setState(() => inner.go = true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(inner.mounted, isFalse);
    expect(router.currentUrl, '/b');
    expect(find.text('B'), findsOneWidget);
    expect(find.text('inner'), findsNothing);
  });

  testWidgets('redirects in builds started by setState count towards the '
      'redirect limit', (tester) async {
    final router = await start(tester, const Root(loop: true));
    final root = RootState.latest;
    root.setState(() => root.shown = const RC());
    await tester.pumpAndSettle();
    final error = tester.takeException();
    expect(error, isFlutterError);
    expect(
      '$error',
      contains(
        'open() was called during an update 6 times in a row: '
        '/b -> /c -> /b -> /c -> /b -> /c',
      ),
    );
    // the app stays on the last route applied
    expect(root.shown, isA<RB>());
    expect(router.currentUrl, '/b');
  });
}
