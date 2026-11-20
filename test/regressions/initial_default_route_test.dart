import 'package:fdr/fdr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'routes.dart';

// stands for a hydrated store read when the navigator state is created
class Restored {
  Restored(this.shown);
  final RR shown;
}

class Root extends StatefulNavigator<RR> {
  const Root(this.restored);
  final Restored restored;

  @override
  RootState createState() => RootState();
}

class RootState extends StatefulNavigatorState<Root, RR> {
  late RR shown;

  @override
  void initState() {
    super.initState();
    shown = navigator.restored.shown;
  }

  @override
  void applyRoute(RR route) => shown = route;

  @override
  List<NavEntry<RR>> build() => [
    NavPage(route: const RA(), child: scaffold('A')),
    if (shown is RB)
      NavPage(
        route: const RB(),
        onPop: () => setState(() => shown = const RA()),
        child: scaffold('B'),
      ),
    if (shown is RC)
      NavPage(
        route: const RC(),
        onPop: () => setState(() => shown = const RA()),
        child: scaffold('C'),
      ),
  ];
}

Future<FdrRouter<RR>> start(
  WidgetTester tester, {
  required bool keepState,
  RouteInformation? initialRouteInformation,
}) async {
  final router = FdrRouter<RR>(
    root: Root(Restored(const RB())),
    fromUrl: RR.fromUrl,
    initialRouteInformation: initialRouteInformation,
    keepStateWithoutDeepLink: keepState,
  );
  addTearDown(router.dispose);
  expect(router.currentUrl, '/b');
  await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher
        .clearDefaultRouteNameTestValue();
  });

  testWidgets('a start without a deep link keeps the state, if asked to', (
    tester,
  ) async {
    // the platform's initial route is "/" when no route was requested
    expect(tester.binding.platformDispatcher.defaultRouteName, '/');
    final router = await start(tester, keepState: true);
    expect(router.currentUrl, '/b');
    expect(find.text('B'), findsOneWidget);
    expect(router.provider.shadowHistory, ['/b']);
  });

  testWidgets('by default, the initial "/" is applied', (tester) async {
    final router = await start(tester, keepState: false);
    expect(router.currentUrl, '/');
  });

  testWidgets('a deep link is applied', (tester) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/c';
    final router = await start(tester, keepState: true);
    expect(router.currentUrl, '/c');
  });

  testWidgets('an initial "/" the app passes is applied', (tester) async {
    final router = await start(
      tester,
      keepState: true,
      initialRouteInformation: RouteInformation(uri: Uri.parse('/')),
    );
    expect(router.currentUrl, '/');
  });
}
