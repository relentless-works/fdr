import 'package:fdr/fdr.dart';
import 'package:flutter/services.dart';
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

  group('a rewriteUri that throws is reported, like a fromUrl', () {
    // an app bug that only some links hit: there is no path segment in
    // myapp://shop.example
    Uri hook(Uri uri) =>
        uri.hasScheme ? Uri(path: '/${uri.pathSegments.first}') : uri;

    testWidgets('for the link that starts the app', (tester) async {
      final router = await start(
        tester,
        initial: 'myapp://shop.example?x=1',
        rewriteUri: hook,
      );
      expect(tester.takeException(), isStateError);
      expect(find.byType(ErrorWidget), findsNothing);
      // the not-found page, on the page the app starts with
      expect(find.text('missing /?x=1'), findsOneWidget);
      expect(router.currentUrl, '/?x=1');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('A'), findsOneWidget);
      expect(router.currentUrl, '/');
    });

    testWidgets('for a link while the app runs', (tester) async {
      final router = await start(tester, rewriteUri: hook);
      await linkTo(tester, 'myapp://shop.example/b');
      expect(router.currentUrl, '/b');

      final errors = <FlutterErrorDetails>[];
      final onError = FlutterError.onError;
      FlutterError.onError = errors.add;
      await linkTo(tester, 'myapp://shop.example');
      FlutterError.onError = onError;

      expect(errors.single.exception, isStateError);
      expect(errors.single.library, 'fdr');
      expect(
        '${errors.single.context}',
        'while rewriting myapp://shop.example',
      );
      // on the page shown, and the address bar follows
      expect(find.text('missing /'), findsOneWidget);
      expect(router.currentUrl, '/');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(router.currentUrl, '/b');
    });
  });

  testWidgets('a hash link whose fragment is no URI is routed by its path', (
    tester,
  ) async {
    // "a:b" is no host with a port
    expect(Uri.tryParse('//a:b'), isNull);
    final router = await start(tester, initial: 'https://shop.example/#//a:b');
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('A'), findsOneWidget);
    expect(router.currentUrl, '/');
    await linkTo(tester, 'https://shop.example/b');
    await linkTo(tester, 'https://shop.example/#//a:b');
    expect(router.currentUrl, '/');
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
