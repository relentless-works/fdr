import 'package:fdr/fdr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'routes.dart';

BuildContext? linkContext;

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
    NavPage(
      route: const RA(),
      child: Scaffold(
        body: RouteLink(
          route: const RB(),
          builder: (context, open) {
            linkContext = context;
            return TextButton(onPressed: open, child: const Text('to B'));
          },
        ),
      ),
    ),
    if (shown is RB) NavPage(route: const RB(), child: scaffold('B')),
  ];
}

// stands in for url_launcher_web, whose delegate builds an anchor around the
// link
final class WebLinks extends UrlLauncherPlatform {
  final links = <LinkInfo>[];
  var followed = 0;

  @override
  LinkDelegate get linkDelegate => (link) {
    links.add(link);
    return Builder(
      builder: (context) => link.builder(context, () async => followed++),
    );
  };
}

Future<FdrRouter<RR>> pumpRouter(WidgetTester tester) async {
  tester.binding.platformDispatcher.defaultRouteNameTestValue = '/';
  addTearDown(tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
  final router = FdrRouter<RR>(root: const Root(), fromUrl: RR.fromUrl);
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
  await tester.pump();
  return router;
}

void main() {
  setUp(() => linkContext = null);

  testWidgets('without url_launcher_web, a link is its builder alone', (
    tester,
  ) async {
    expect(UrlLauncherPlatform.instance.linkDelegate, isNull);
    final router = await pumpRouter(tester);
    // nothing of url_launcher between the link and its builder
    expect(linkContext!.widget, isA<RouteLink>());

    await tester.tap(find.text('to B'));
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/b');
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('url_launcher_web builds the anchor, a tap opens in the app', (
    tester,
  ) async {
    final platform = UrlLauncherPlatform.instance;
    final web = WebLinks();
    UrlLauncherPlatform.instance = web;
    addTearDown(() => UrlLauncherPlatform.instance = platform);
    final router = await pumpRouter(tester);

    final link = web.links.last;
    expect(link.uri, Uri.parse('/b'));
    expect(link.target, LinkTarget.defaultTarget);
    expect(link.isDisabled, isFalse);

    // off the web a tap never follows the link, it opens the route
    await tester.tap(find.text('to B'));
    await tester.pumpAndSettle();
    expect(web.followed, 0);
    expect(router.currentUrl, '/b');
    expect(router.provider.shadowHistory, ['/', '/b']);
  });
}
