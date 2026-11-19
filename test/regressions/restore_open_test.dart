import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../routing/example_app.dart';

/// Creates the router inside a State so `restartAndRestore` builds a fresh
/// one; [openOnStart] is opened right after construction, like `main()` does
/// for the notification that launched the app.
class App extends StatefulWidget {
  const App({super.key});

  static late FdrRouter<AppRoute> router;
  static AppRoute? openOnStart;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  @override
  void initState() {
    super.initState();
    App.router = FdrRouter<AppRoute>(
      root: const AppNavigator(loggedIn: true),
      fromUrl: AppRoute.fromUrl,
      notFound: (url) => NotFoundPage(url: url),
      sessionId: 1,
    );
    if (App.openOnStart case final route?) App.router.open(route);
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    routerConfig: App.router.config,
    restorationScopeId: 'app',
  );
}

const notificationTarget = HomeAt(SettingsAt(SettingsProfile()));

final navLog = <MethodCall>[];
List<(String, bool)> get reports => [
  for (final call in navLog)
    if (call.method == 'routeInformationUpdated')
      (
        (call.arguments as Map)['uri'] as String,
        (call.arguments as Map)['replace'] as bool,
      ),
];

void main() {
  setUp(() {
    navLog.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.navigation, (call) async {
          navLog.add(call);
          return null;
        });
  });
  tearDown(() {
    App.openOnStart = null;
    TestWidgetsFlutterBinding.instance.platformDispatcher
        .clearDefaultRouteNameTestValue();
  });

  testWidgets('a route opened before start wins over the restored route', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/orders/42';
    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();
    expect(App.router.currentUrl, '/orders/42');
    final oldRouter = App.router;

    // process death; the notification that relaunches the app opens a route
    // before runApp
    App.openOnStart = notificationTarget;
    navLog.clear();
    await tester.restartAndRestore();
    await tester.pumpAndSettle();
    expect(App.router, isNot(same(oldRouter)));
    expect(App.router.currentUrl, '/settings/profile');
    expect(reports, [('/settings/profile', true)]);

    // the restoration data follows: the next process death comes back there
    App.openOnStart = null;
    await tester.restartAndRestore();
    await tester.pumpAndSettle();
    expect(App.router.currentUrl, '/settings/profile');
  });
}
