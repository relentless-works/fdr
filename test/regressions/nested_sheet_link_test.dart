import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Links in sheets, dialogs and menus opened from a page of a child navigator
// resolve like links in that page, also those of the child's route type.

final class HomeAt extends NavRoute {
  const HomeAt(this.child, {this.tab = 0});
  final CR child;
  final int tab;
  static HomeAt fromUrl(Url url) => switch (url.segments) {
    ['t1', ...] => HomeAt(CR.fromUrl(url.rest(1)), tab: 1),
    _ => HomeAt(CR.fromUrl(url)),
  };
  @override
  Url toUrl() => (tab == 1 ? const Url(['t1']) : const Url([])) + child.toUrl();
}

sealed class CR extends NavRoute {
  const CR();
  static CR fromUrl(Url url) => switch (url.segments) {
    [] => const C0(),
    ['x'] => const CX(),
    _ => throw NotFound(url),
  };
  @override
  Url toUrl() => switch (this) {
    C0() => const Url([]),
    CX() => const Url(['x']),
  };
}

final class C0 extends CR {
  const C0();
}

final class CX extends CR {
  const CX();
}

class Root extends StatefulNavigator<HomeAt> {
  const Root({this.tabs = false});
  final bool tabs;
  @override
  RootState createState() => RootState();
}

class RootState extends StatefulNavigatorState<Root, HomeAt> {
  int tab = 0;
  final children = <CR?>[null, null];
  @override
  void applyRoute(HomeAt route) {
    tab = route.tab;
    children[tab] = route.child;
  }

  @override
  List<NavEntry<HomeAt>> build() => [
    if (!navigator.tabs)
      NestedNavigator(at: HomeAt.new, route: children[0], child: const Child())
    else
      TabsPage(
        index: tab,
        tabs: [
          for (final i in [0, 1])
            NestedNavigator(
              at: (route) => HomeAt(route, tab: i),
              route: children[i],
              child: const Child(),
            ),
        ],
        builder: (context, tabs) => IndexedStack(index: tab, children: tabs),
      ),
  ];
}

class Child extends StatefulNavigator<CR> {
  const Child();
  @override
  ChildState createState() => ChildState();
}

class ChildState extends StatefulNavigatorState<Child, CR> {
  bool x = false;
  @override
  void applyRoute(CR route) => x = route is CX;
  @override
  List<NavEntry<CR>> build() => [
    const NavPage(
      route: C0(),
      child: Scaffold(body: Openers()),
    ),
    if (x)
      NavPage(
        route: const CX(),
        onPop: () => setState(() => x = false),
        child: Scaffold(appBar: AppBar(), body: const Text('X')),
      ),
  ];
}

Widget link(String label, [NavRoute route = const CX()]) => RouteLink(
  route: route,
  builder: (context, open) => TextButton(onPressed: open, child: Text(label)),
);

class Openers extends StatelessWidget {
  const Openers({super.key});
  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextButton(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          builder: (_) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              link('sheet go'),
              link('sheet root', const HomeAt(CX())),
            ],
          ),
        ),
        child: const Text('sheet'),
      ),
      TextButton(
        onPressed: () =>
            showDialog<void>(context: context, builder: (_) => link('dlg go')),
        child: const Text('dialog'),
      ),
      PopupMenuButton<void>(
        itemBuilder: (_) => [PopupMenuItem(child: link('menu go'))],
        child: const Text('menu'),
      ),
    ],
  );
}

Future<FdrRouter<HomeAt>> start(
  WidgetTester tester, {
  String url = '/',
  bool tabs = false,
}) async {
  tester.binding.platformDispatcher.defaultRouteNameTestValue = url;
  addTearDown(tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
  final router = FdrRouter<HomeAt>(
    root: Root(tabs: tabs),
    fromUrl: HomeAt.fromUrl,
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
  await tester.pump();
  return router;
}

Future<void> openAndTap(WidgetTester tester, String opener, String go) async {
  await tester.tap(find.text(opener));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  await tester.tap(find.text(go));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets("a link of the child's type in a bottom sheet", (tester) async {
    final router = await start(tester);
    await openAndTap(tester, 'sheet', 'sheet go');
    expect(router.currentUrl, '/x');
    expect(find.text('X'), findsOneWidget);
  });

  testWidgets("a link of the root's type in the same sheet", (tester) async {
    final router = await start(tester);
    await openAndTap(tester, 'sheet', 'sheet root');
    expect(router.currentUrl, '/x');
  });

  testWidgets("a link of the child's type in a dialog", (tester) async {
    final router = await start(tester);
    await openAndTap(tester, 'dialog', 'dlg go');
    expect(router.currentUrl, '/x');
  });

  testWidgets("a link of the child's type in a popup menu", (tester) async {
    final router = await start(tester);
    await openAndTap(tester, 'menu', 'menu go');
    expect(router.currentUrl, '/x');
  });

  testWidgets("a link in a sheet on a tab's Navigator", (tester) async {
    final router = await start(tester, url: '/t1', tabs: true);
    await openAndTap(tester, 'sheet', 'sheet go');
    expect(router.currentUrl, '/t1/x');
  });

  testWidgets('a link in a dialog opened in a tab', (tester) async {
    final router = await start(tester, url: '/t1', tabs: true);
    // on the root Navigator, above the tabs
    await openAndTap(tester, 'dialog', 'dlg go');
    expect(router.currentUrl, '/t1/x');
  });
}
