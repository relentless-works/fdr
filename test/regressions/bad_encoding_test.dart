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

  test('percent-encoding that is not UTF-8 is kept as typed', () {
    final url = Url.parse(Uri.parse('/b/caf%E9?q=%E9'));
    expect(url.segments, ['b', 'caf%E9']);
    expect(url['q'], '%E9');
  });

  testWidgets('a deep link with Latin-1 percent-encoding', (tester) async {
    await start(tester, '/b/caf%E9');
    expect(tester.takeException(), isNull);
    // the nearest page that exists, with the not-found page on top
    expect(find.text('B', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('No page'), findsOneWidget);
    expect(missing.segments, ['b', 'caf%E9']);
  });

  testWidgets(
    'the address bar keeps a deep link with Latin-1 percent-encoding',
    (tester) async {
      final router = await start(tester, '/b/caf%E9');
      expect(router.currentUrl, '/b/caf%E9');
      expect(router.provider.value.uri.toString(), '/b/caf%E9');
    },
    // Known bug: the URL that did not parse is printed again from its
    // segments, which encodes the % that was kept: the address bar shows
    // /b/caf%25E9, not the URL as typed (doc section 6).
    skip: true,
  );
}
