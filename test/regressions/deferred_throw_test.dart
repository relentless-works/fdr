import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'routes.dart';

bool failRoot = true;

class Leaf extends StatefulNavigator<Never> {
  const Leaf();
  @override
  LeafState createState() => LeafState();
}

class LeafState extends StatefulNavigatorState<Leaf, Never> {
  @override
  void initState() {
    super.initState();
    final root = RootState.latest;
    // deferred: the update of another navigator (Mid) is running
    root.setState(() => root.fail = failRoot);
    // queued: a redirect asked for during that update
    root.open(const RC());
  }

  @override
  List<NavEntry<Never>> build() => [NavPage(child: scaffold('leaf'))];
}

class Mid extends StatefulNavigator<Never> {
  const Mid();
  @override
  MidState createState() => MidState();
}

class MidState extends StatefulNavigatorState<Mid, Never> {
  static late MidState latest;
  bool leaf = false;

  @override
  void initState() {
    super.initState();
    latest = this;
  }

  @override
  List<NavEntry<Never>> build() => [if (leaf) const Leaf()];
}

class Root extends StatefulNavigator<RR> {
  const Root();
  @override
  RootState createState() => RootState();
}

class RootState extends StatefulNavigatorState<Root, RR> {
  static late RootState latest;
  RR shown = const RA();
  bool fail = false;
  int n = 0;

  @override
  void initState() {
    super.initState();
    latest = this;
  }

  @override
  void applyRoute(RR route) => shown = route;

  @override
  List<NavEntry<RR>> build() {
    if (fail) {
      fail = false;
      throw StateError('deferred build boom');
    }
    return [
      NavPage(route: const RA(), child: scaffold('A $n')),
      const Mid(),
      if (shown is RC) NavPage(route: const RC(), child: scaffold('C')),
    ];
  }
}

Future<FdrRouter<RR>> start(WidgetTester tester) async {
  tester.binding.platformDispatcher.defaultRouteNameTestValue = '/';
  addTearDown(tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
  final router = FdrRouter<RR>(root: const Root(), fromUrl: RR.fromUrl);
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
  await tester.pump();
  expect(router.currentUrl, '/');
  return router;
}

void main() {
  testWidgets('an open() queued next to a deferred rebuild redirects', (
    tester,
  ) async {
    failRoot = false;
    final router = await start(tester);
    MidState.latest.setState(() => MidState.latest.leaf = true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(router.currentUrl, '/c');
  });

  testWidgets('a redirect queued before a deferred rebuild throws does not '
      'fire later', (tester) async {
    failRoot = true;
    final router = await start(tester);

    Object? thrown;
    try {
      MidState.latest.setState(() => MidState.latest.leaf = true);
    } catch (e) {
      thrown = e;
    }
    await tester.pumpAndSettle();
    expect(thrown, isStateError);
    expect(router.currentUrl, '/');

    // an unrelated update, long after the failed one
    final root = RootState.latest;
    root.setState(() => root.n = 1);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(router.currentUrl, '/', reason: 'stale queued redirect to /c ran');
    expect(find.text('C'), findsNothing);
    expect(find.text('A 1', skipOffstage: false), findsOneWidget);
  });
}
