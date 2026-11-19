import 'dart:async';

import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'routes.dart';

bool throwOnC = true;
late RootState rootState;

class Root extends StatefulNavigator<RR> {
  const Root();
  @override
  RootState createState() => rootState = RootState();
}

class RootState extends StatefulNavigatorState<Root, RR> {
  RR current = const RA();

  @override
  void applyRoute(RR route) => current = route;

  void show(RR route) => setState(() => current = route);

  @override
  List<NavEntry<RR>> build() {
    if (current is RC && throwOnC) throw StateError('build failed for /c');
    return [
      const NavPage(route: RA(), child: Text('page A')),
      if (current is RB)
        NavPage(route: const RB(), onPop: () {}, child: const Text('page B')),
      if (current is RC)
        NavPage(route: const RC(), onPop: () {}, child: const Text('page C')),
    ];
  }
}

final navLog = <MethodCall>[];
List<(String, bool)> get reports => [
  for (final call in navLog)
    if (call.method == 'routeInformationUpdated')
      (
        (call.arguments as Map)['uri'] as String,
        (call.arguments as Map)['replace'] as bool,
      ),
];

Future<void> browserNavigatesTo(WidgetTester tester, String location) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMethodCodec().encodeMethodCall(
      MethodCall('pushRouteInformation', {'location': location, 'state': null}),
    ),
    (_) {},
  );
  await tester.pump();
}

void main() {
  setUp(() {
    navLog.clear();
    throwOnC = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.navigation, (call) async {
          navLog.add(call);
          return null;
        });
  });
  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher
        .clearDefaultRouteNameTestValue();
  });

  testWidgets('a platform route whose build throws: the URL is corrected', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/';
    final router = FdrRouter<RR>(root: const Root(), fromUrl: RR.fromUrl);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
    await tester.pump();
    expect(reports, [('/', true)]);

    await browserNavigatesTo(tester, '/c');
    expect(tester.takeException(), isStateError);
    expect(find.text('page A'), findsOneWidget);
    expect(router.currentUrl, '/');
    // the browser entry is /c: it is replaced with the URL of what is shown
    expect(reports, [('/', true), ('/', true)]);

    // the root navigator still drives the pages
    throwOnC = false;
    rootState.show(const RB());
    await tester.pumpAndSettle();
    expect(find.text('page B'), findsOneWidget);
    expect(router.currentUrl, '/b');
  });

  testWidgets('a failed apply keeps the not-found page that was shown', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/nope';
    final router = FdrRouter<RR>(
      root: const Root(),
      fromUrl: RR.fromUrl,
      notFound: (url) => Text('missing $url'),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
    await tester.pump();
    expect(router.currentUrl, '/nope');

    await browserNavigatesTo(tester, '/c/x');
    expect(tester.takeException(), isStateError);
    expect(find.text('missing /nope'), findsOneWidget);
    expect(router.currentUrl, '/nope');
    expect(reports.last, ('/nope', true));

    // an update from the router (hot reload) keeps it too; applyRoute had
    // set C before build threw, so C is below it now
    throwOnC = false;
    unawaited(tester.binding.reassembleApplication());
    await tester.pump();
    await tester.pump();
    expect(find.text('missing /nope'), findsOneWidget);
    expect(router.currentUrl, '/nope');
  });

  testWidgets('a cold start on a route whose build throws', (tester) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/c';
    final router = FdrRouter<RR>(root: const Root(), fromUrl: RR.fromUrl);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
    expect(tester.takeException(), isStateError);
    await tester.pump();
    expect(find.text('page A'), findsOneWidget);
    expect(router.currentUrl, '/');
    expect(reports, [('/', true)]);
  });
}
