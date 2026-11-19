import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'routes.dart';

class Root extends StatefulNavigator<RR> {
  const Root();
  @override
  RootState createState() => RootState();
}

class RootState extends StatefulNavigatorState<Root, RR> {
  static int created = 0;
  static int disposed = 0;
  RR shown = const RA();

  @override
  void initState() {
    super.initState();
    created++;
  }

  @override
  void dispose() {
    disposed++;
    super.dispose();
  }

  @override
  void applyRoute(RR route) {
    // /b moved to /c
    if (route is RB) {
      open(const RC(), history: HistoryAction.replace);
      return;
    }
    shown = route;
  }

  @override
  List<NavEntry<RR>> build() => [
    NavPage(route: const RA(), child: scaffold('A')),
    if (shown is RC)
      NavPage(
        route: const RC(),
        onPop: () => setState(() => shown = const RA()),
        child: scaffold('C'),
      ),
  ];
}

void main() {
  tearDown(
    () => TestWidgetsFlutterBinding.instance.platformDispatcher
        .clearDefaultRouteNameTestValue(),
  );

  testWidgets('open() from applyRoute (a redirect) lands on the target', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/';
    final router = FdrRouter<RR>(root: const Root(), fromUrl: RR.fromUrl);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
    await tester.pump();
    expect(RootState.created, 1);

    router.open(const RB());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('C'), findsOneWidget);
    expect(router.currentUrl, '/c');
    expect((RootState.created, RootState.disposed), (1, 0));
  });

  testWidgets('a redirect with replace keeps the entry the user came from', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/';
    final router = FdrRouter<RR>(root: const Root(), fromUrl: RR.fromUrl);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
    await tester.pump();
    expect(router.provider.shadowHistory, ['/']);

    // the replace is for /b, which was never reported; the open of /b
    // itself adds an entry
    router.open(const RB());
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/c');
    expect(router.provider.shadowHistory, ['/', '/c']);
  });

  testWidgets('an explicit history action of the open still wins', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/';
    final router = FdrRouter<RR>(root: const Root(), fromUrl: RR.fromUrl);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
    await tester.pump();

    router.open(const RB(), history: HistoryAction.replace);
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/c');
    expect(router.provider.shadowHistory, ['/c']);
  });

  testWidgets('a redirect of a platform route replaces its entry', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/';
    final router = FdrRouter<RR>(root: const Root(), fromUrl: RR.fromUrl);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
    await tester.pump();

    await router.provider.didPushRouteInformation(
      RouteInformation(uri: Uri.parse('/b')),
    );
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/c');
    // a typed URL starts a new shadow history, corrected in place
    expect(router.provider.shadowHistory, ['/c']);
  });

  testWidgets('a redirect of the nearest page keeps the not-found page', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/';
    final router = FdrRouter<RR>(
      root: const Root(),
      fromUrl: RR.fromUrl,
      notFound: (url) => scaffold('missing $url'),
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
    await tester.pump();

    // /b is the longest prefix that parses, and it redirects to /c
    await router.provider.didPushRouteInformation(
      RouteInformation(uri: Uri.parse('/b/nope')),
    );
    await tester.pumpAndSettle();
    expect(find.text('missing /b/nope'), findsOneWidget);
    expect(router.currentUrl, '/b/nope');

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('C'), findsOneWidget);
    expect(router.currentUrl, '/c');
  });
}
