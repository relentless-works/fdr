import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class SegRoute extends NavRoute {
  const SegRoute(this.seg);
  final String seg;

  static SegRoute fromUrl(Url url) => switch (url.segments) {
    [] => const SegRoute('a'),
    [final String s] => SegRoute(s),
    _ => throw NotFound(url),
  };

  @override
  Url toUrl() => Url([seg]);
}

final pops = <String>[];

class Nav extends StatefulNavigator<SegRoute> {
  const Nav();
  @override
  NavState createState() => NavState();
}

class NavState extends StatefulNavigatorState<Nav, SegRoute> {
  bool showMid = true;
  bool showTop = true;

  @override
  void applyRoute(SegRoute route) {}

  @override
  List<NavEntry<SegRoute>> build() => [
    const NavPage(route: SegRoute('a'), child: Text('bottom')),
    if (showMid)
      NavPage(
        onPop: () {
          pops.add('mid');
          setState(() => showMid = false);
        },
        child: const Text('mid'),
      ),
    if (showTop)
      NavPage(
        // prints /a~1
        route: const SegRoute('a~1'),
        onPop: () {
          pops.add('top');
          setState(() => showTop = false);
        },
        child: const Text('top'),
      ),
  ];
}

void main() {
  testWidgets('a page without a route and a path ending in ~1 get own keys', (
    tester,
  ) async {
    pops.clear();
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/';
    final router = FdrRouter<SegRoute>(
      root: const Nav(),
      fromUrl: SegRoute.fromUrl,
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
    await tester.pumpAndSettle();

    final navigator = tester.widget<Navigator>(find.byType(Navigator).first);
    final keys = navigator.pages.map((page) => page.key).toList();
    expect(keys.toSet(), hasLength(3), reason: 'page keys $keys');

    router.delegate.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(pops, ['top']);
    expect(find.text('top'), findsNothing);
    expect(find.text('mid'), findsOneWidget);
  });
}
