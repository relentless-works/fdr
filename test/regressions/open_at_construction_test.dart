import 'package:fdr/fdr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'routes.dart';

// the root redirects to /c once, in initState or in build: both run while
// the router (or a DeclarativeNavigator) builds its tree the first time
class Root extends StatefulNavigator<RR> {
  const Root({required this.inBuild});
  final bool inBuild;

  @override
  RootState createState() => RootState();
}

class RootState extends StatefulNavigatorState<Root, RR> {
  RR current = const RA();
  bool redirected = false;

  @override
  void initState() {
    super.initState();
    if (!navigator.inBuild) open(const RC());
  }

  @override
  void applyRoute(RR route) => current = route;

  @override
  Iterable<NavEntry<RR>> build() {
    if (navigator.inBuild && !redirected) {
      redirected = true;
      open(const RC());
    }
    return [
      NavPage(route: const RA(), child: scaffold('A')),
      if (current is RB) NavPage(route: const RB(), child: scaffold('B')),
      if (current is RC) NavPage(route: const RC(), child: scaffold('C')),
    ];
  }
}

void main() {
  for (final inBuild in [false, true]) {
    final where = inBuild ? 'build' : 'initState';

    testWidgets('open() in the root\'s $where keeps the initial deep link', (
      tester,
    ) async {
      final router = FdrRouter<RR>(
        root: Root(inBuild: inBuild),
        fromUrl: RR.fromUrl,
        initialRouteInformation: RouteInformation(uri: Uri.parse('/b')),
      );
      expect(router.currentUrl, '/c');
      await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
      await tester.pumpAndSettle();
      // a redirect is not a route the app opened before start: the deep
      // link is applied after it
      expect(router.currentUrl, '/b');
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('open() in the root\'s $where, then the initial "/"', (
      tester,
    ) async {
      final router = FdrRouter<RR>(
        root: Root(inBuild: inBuild),
        fromUrl: RR.fromUrl,
        initialRouteInformation: RouteInformation(uri: Uri.parse('/')),
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // like any state set before start, the initial route is applied over
      // it
      expect(router.currentUrl, '/');
    });

    testWidgets('open() in the $where of a DeclarativeNavigator\'s root', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DeclarativeNavigator(navigator: Root(inBuild: inBuild)),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('C'), findsOneWidget);
    });
  }
}
