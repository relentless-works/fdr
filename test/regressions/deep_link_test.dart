import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    if (shown is! RA)
      NavPage(
        route: shown,
        onPop: () => setState(() => shown = const RA()),
        child: scaffold('$shown'),
      ),
  ];
}

// an OS deep link while the app runs
Future<void> linkTo(WidgetTester tester, String location) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMethodCodec().encodeMethodCall(
      MethodCall('pushRouteInformation', {'location': location, 'state': null}),
    ),
    (_) {},
  );
  await tester.pumpAndSettle();
}

Future<FdrRouter<RR>> start(
  WidgetTester tester, {
  String initial = '/',
  Uri Function(Uri uri)? rewriteUri,
}) async {
  final router = FdrRouter<RR>(
    root: const Root(),
    fromUrl: RR.fromUrl,
    notFound: (url) => scaffold('missing $url'),
    initialRouteInformation: RouteInformation(uri: Uri.parse(initial)),
    rewriteUri: rewriteUri,
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('a link to a web build with the hash URL strategy', (
    tester,
  ) async {
    final router = await start(tester);
    // shared from the web app, opened as an App Link or Universal Link
    await linkTo(tester, 'https://shop.example/#/b');
    expect(router.currentUrl, '/b');
    await linkTo(tester, 'https://shop.example#/c?from=mail');
    expect(router.currentUrl, '/c');
    // a fragment that is no route stays a fragment
    await linkTo(tester, 'https://shop.example/b#top');
    expect(router.currentUrl, '/b');
  });

  testWidgets('a path that starts with two slashes keeps its first segment', (
    tester,
  ) async {
    // read as a host by Uri.parse; the web engine sends it for a typed
    // https://shop.example//b or #//b
    final router = await start(tester, initial: '//b');
    expect(router.currentUrl, '/b');
    await linkTo(tester, '//c');
    expect(router.currentUrl, '/c');
    await linkTo(tester, 'https://shop.example/#//b');
    expect(router.currentUrl, '/b');
    // a protocol-relative link to another host is no page of the app
    await linkTo(tester, '//other.example/c');
    expect(router.currentUrl, '/other.example/c');
    expect(find.text('missing /other.example/c'), findsOneWidget);
  });

  testWidgets('rewriteUri maps links before they are routed', (tester) async {
    final router = await start(
      tester,
      // a custom scheme with a real host, and universal links under /app
      rewriteUri: (uri) => switch (uri) {
        Uri(host: 'shop.example', scheme: 'myapp') => Uri(path: uri.path),
        Uri(pathSegments: ['app', ...final rest]) => uri.replace(
          pathSegments: rest,
        ),
        _ => uri,
      },
    );
    await linkTo(tester, 'myapp://shop.example/c');
    expect(router.currentUrl, '/c');
    await linkTo(tester, 'https://shop.example/app/b');
    expect(router.currentUrl, '/b');
    // the default rules still apply to what it returns
    await linkTo(tester, 'myapp://c');
    expect(router.currentUrl, '/c');
  });
}
