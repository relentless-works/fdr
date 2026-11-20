import 'package:fdr/fdr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'routes.dart';

class Root extends StatefulNavigator<RR> {
  const Root();
  @override
  RootState createState() => RootState();
}

class RootState extends StatefulNavigatorState<Root, RR> {
  RR shown = const RA();
  @override
  void applyRoute(RR route) => shown = route;
  @override
  List<NavEntry<RR>> build() => [
    NavPage(route: const RA(), child: scaffold('A')),
    if (shown is RB) NavPage(route: const RB(), child: scaffold('B')),
  ];
}

void main() {
  late Url missing;

  Future<FdrRouter<RR>> start(WidgetTester tester, String url) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = url;
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final router = FdrRouter<RR>(
      root: const Root(),
      fromUrl: RR.fromUrl,
      notFound: (url) {
        missing = url;
        return scaffold('No page at $url');
      },
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
    await tester.pump();
    return router;
  }

  test('percent-encoding that is not UTF-8 is read as Latin-1', () {
    final url = Url.parse(Uri.parse('/b/caf%E9?q=%E9'));
    expect(url.segments, ['b', 'café']);
    expect(url['q'], 'é');
  });

  testWidgets('a deep link with Latin-1 percent-encoding', (tester) async {
    await start(tester, '/b/caf%E9');
    expect(tester.takeException(), isNull);
    // the nearest page that exists, with the not-found page on top
    expect(find.text('B', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('No page'), findsOneWidget);
    expect(missing.segments, ['b', 'café']);
  });

  testWidgets('the address bar shows a Latin-1 deep link re-encoded as UTF-8', (
    tester,
  ) async {
    final router = await start(tester, '/b/caf%E9');
    // the same text, not /b/caf%25E9
    expect(router.currentUrl, '/b/caf%C3%A9');
    expect(router.provider.value.uri.toString(), '/b/caf%C3%A9');
  });

  // the URL that did not parse stays in the address bar, not the prefix's,
  // as Url.parse read it and printed the canonical way (NotFound's dartdoc)
  for (final (typed, shown) in [
    ('/b/nope', '/b/nope'),
    ('/b/./nope/', '/b/nope'),
    ('/b/x/../nope', '/b/nope'),
    ('/b/nope?q=a%20b', '/b/nope?q=a+b'),
  ]) {
    testWidgets('$typed shows the not-found page at $shown', (tester) async {
      final router = await start(tester, typed);
      expect(find.text('B', skipOffstage: false), findsOneWidget);
      expect(find.textContaining('No page'), findsOneWidget);
      expect(router.currentUrl, shown);
      expect(router.provider.value.uri.toString(), shown);
    });
  }
}
