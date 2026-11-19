import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'routes.dart';

// A Router mounted again for the same FdrRouter (a lock screen shown in
// place of the app, a MaterialApp.router whose key changes): the delegate
// already shows a state, which the new Router only reports.

class Root extends StatefulNavigator<RR> {
  const Root();
  @override
  RootState createState() => RootState();
}

class RootState extends StatefulNavigatorState<Root, RR> {
  static late RootState latest;
  RR shown = const RA();
  int scroll = 0;

  @override
  void initState() {
    super.initState();
    latest = this;
  }

  @override
  void applyRoute(RR route) => shown = route;

  @override
  Object? get historyState => scroll == 0 ? null : {'scroll': scroll};

  @override
  void restoreHistoryState(Object? state) {
    scroll = state is Map ? state['scroll']! as int : 0;
  }

  @override
  List<NavEntry<RR>> build() => [
    NavPage(route: const RA(), child: Text('A $scroll')),
    if (shown is RB)
      NavPage(
        route: const RB(),
        onPop: () => setState(() => shown = const RA()),
        child: const Text('B'),
      ),
  ];
}

const tree = {
  '0': {
    't': 'RootState',
    's': {'scroll': 5},
  },
};

void main() {
  late List<Map<Object?, Object?>> sent;

  FdrRouter<RR> start(WidgetTester tester) {
    sent = [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.navigation,
      (call) async {
        if (call.method == 'routeInformationUpdated') {
          sent.add(call.arguments as Map);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.navigation,
        null,
      ),
    );
    final router = FdrRouter<RR>(
      root: const Root(),
      fromUrl: RR.fromUrl,
      initialRouteInformation: RouteInformation(uri: Uri.parse('/')),
      sessionId: 1,
    );
    addTearDown(router.dispose);
    return router;
  }

  testWidgets('a Router mounted again keeps the non-URL state', (tester) async {
    final router = start(tester);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
    await tester.pumpAndSettle();
    final state = RootState.latest;
    state.setState(() => state.scroll = 5);
    await tester.pumpAndSettle();
    expect(find.text('A 5'), findsOneWidget);
    expect((sent.last['state'] as Map)['h'], tree);

    for (var k = 0; k < 2; k++) {
      await tester.pumpWidget(const MaterialApp(home: Text('locked')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
      await tester.pumpAndSettle();

      expect(RootState.latest, same(state));
      expect(find.text('A 5'), findsOneWidget);
      expect(router.currentUrl, '/');
    }

    // the next entry holds the tree, not an earlier entry around it
    state.setState(() => state.shown = const RB());
    await tester.pumpAndSettle();
    expect(sent.last['uri'], '/b');
    expect((sent.last['state'] as Map)['h'], tree);
  });

  testWidgets('a MaterialApp.router with another key keeps it too', (
    tester,
  ) async {
    final router = start(tester);
    await tester.pumpWidget(
      MaterialApp.router(key: const ValueKey(1), routerConfig: router.config),
    );
    await tester.pumpAndSettle();
    RootState.latest.setState(() => RootState.latest.scroll = 5);
    await tester.pumpAndSettle();
    for (var k = 2; k <= 3; k++) {
      await tester.pumpWidget(
        MaterialApp.router(key: ValueKey(k), routerConfig: router.config),
      );
      await tester.pumpAndSettle();
    }
    expect(find.text('A 5'), findsOneWidget);
    expect((sent.last['state'] as Map)['h'], tree);
  });

  testWidgets('a route opened while no Router is mounted stays', (
    tester,
  ) async {
    final router = start(tester);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const MaterialApp(home: Text('locked')));
    await tester.pumpAndSettle();

    router.open(const RB());
    expect(router.currentUrl, '/b');

    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/b');
    expect(find.text('B'), findsOneWidget);
    // reported as it would have been with a Router: a new entry
    expect(sent.last['uri'], '/b');
    expect(sent.last['replace'], isFalse);
  });

  testWidgets('the provider\'s value holds the tree, not its own entry', (
    tester,
  ) async {
    final router = start(tester);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
    await tester.pumpAndSettle();
    RootState.latest.setState(() => RootState.latest.scroll = 5);
    await tester.pumpAndSettle();
    expect(router.provider.value.uri.toString(), '/');
    expect(router.provider.value.state, tree);
  });

  testWidgets('a tree with keys that are no indexes is not written again', (
    tester,
  ) async {
    final router = start(tester);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
    await tester.pumpAndSettle();
    router.delegate.setNewRoutePath(
      const RouteSnapshot(RA(), historyState: {...tree, 'fdr': 1, 'x': 2}),
    );
    await tester.pumpAndSettle();
    expect(find.text('A 5'), findsOneWidget);
    expect((sent.last['state'] as Map)['h'], tree);
  });
}
