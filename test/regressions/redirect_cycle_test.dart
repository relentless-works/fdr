import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'routes.dart';

int applied = 0;

class Root extends StatefulNavigator<RR> {
  const Root({required this.cycle});

  /// Whether /c redirects back to /b (a wrong condition), or on to /.
  final bool cycle;

  @override
  RootState createState() => RootState();
}

class RootState extends StatefulNavigatorState<Root, RR> {
  RR shown = const RA();

  @override
  void applyRoute(RR route) {
    applied++;
    shown = route;
    if (route is RB) open(const RC(), history: HistoryAction.replace);
    if (route is RC) {
      open(
        navigator.cycle ? const RB() : const RA(),
        history: HistoryAction.replace,
      );
    }
  }

  @override
  List<NavEntry<RR>> build() => [
    NavPage(route: const RA(), child: scaffold('A')),
    if (shown is RB) NavPage(route: const RB(), child: scaffold('B')),
    if (shown is RC) NavPage(route: const RC(), child: scaffold('C')),
  ];
}

// the same cycle without a router
class Plain extends StatefulNavigator<String> {
  const Plain();
  @override
  PlainState createState() => PlainState();
}

class PlainState extends StatefulNavigatorState<Plain, String> {
  static late PlainState latest;
  String shown = 'a';

  @override
  void initState() {
    super.initState();
    latest = this;
  }

  @override
  void applyRoute(String route) {
    applied++;
    shown = route;
    if (route == 'b') open('c');
    if (route == 'c') open('b');
  }

  @override
  List<NavEntry<String>> build() => [NavPage(child: Text('plain $shown'))];
}

Future<FdrRouter<RR>> pumpRouter(
  WidgetTester tester, {
  required bool cycle,
}) async {
  tester.binding.platformDispatcher.defaultRouteNameTestValue = '/';
  addTearDown(tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
  final router = FdrRouter<RR>(
    root: Root(cycle: cycle),
    fromUrl: RR.fromUrl,
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
  await tester.pump();
  applied = 0;
  return router;
}

void expectCycleError(Object? error, List<String> routes) {
  expect(error, isFlutterError);
  final message = (error! as FlutterError).message;
  expect(message, contains('open() was called during an update'));
  expect(message, contains(routes.join(' -> ')));
}

void main() {
  testWidgets('a redirect cycle is reported and stops', (tester) async {
    final router = await pumpRouter(tester, cycle: true);
    router.open(const RB());
    expectCycleError(tester.takeException(), ['/c', '/b', '/c', '/b']);
    // the open itself and a bounded number of redirects
    expect(applied, 6);
    await tester.pumpAndSettle();
    expect(router.currentUrl, anyOf('/b', '/c'));
    expect(tester.takeException(), isNull);

    // the next navigation starts a new chain
    applied = 0;
    router.open(const RA());
    await tester.pumpAndSettle();
    expect(applied, 1);
    expect(router.currentUrl, '/');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a redirect cycle entered from a platform URL', (tester) async {
    final router = await pumpRouter(tester, cycle: true);
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(
        const MethodCall('pushRouteInformation', {'location': '/b'}),
      ),
      (_) {},
    );
    expectCycleError(tester.takeException(), ['/c', '/b', '/c', '/b']);
    expect(applied, 6);
    await tester.pumpAndSettle();
    expect(router.currentUrl, anyOf('/b', '/c'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a chain of redirects lands on the last route', (tester) async {
    final router = await pumpRouter(tester, cycle: false);
    router.open(const RB());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(applied, 3);
    expect(router.currentUrl, '/');
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('a redirect cycle without a router', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DeclarativeNavigator(navigator: Plain())),
    );
    applied = 0;
    PlainState.latest.open('b');
    expectCycleError(tester.takeException(), ['c', 'b', 'c', 'b']);
    expect(applied, 6);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
