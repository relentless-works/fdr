import 'dart:async';

import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'example_app.dart';

class FakeBrowserHistory implements BrowserHistory {
  final deltas = <int>[];
  int get backs => deltas.length;

  @override
  bool get supportsTraversal => true;

  @override
  void go(int delta) => deltas.add(delta);
}

typedef Report = ({String uri, bool replace, Object? state});

final navLog = <MethodCall>[];
final platformLog = <MethodCall>[];

List<Report> get reports => [
  for (final call in navLog)
    if (call.method == 'routeInformationUpdated')
      (
        uri: (call.arguments as Map)['uri'] as String,
        replace: (call.arguments as Map)['replace'] as bool,
        state: (call.arguments as Map)['state'],
      ),
];

/// Creates the router inside a State so `restartAndRestore` builds a fresh one.
class App extends StatefulWidget {
  const App({super.key, required this.loggedIn, required this.browserHistory});
  final bool loggedIn;
  final BrowserHistory browserHistory;

  static late FdrRouter<AppRoute> router;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  @override
  void initState() {
    super.initState();
    App.router = FdrRouter<AppRoute>(
      root: AppNavigator(loggedIn: widget.loggedIn),
      codec: appCodec,
      notFound: NotFoundRoute.new,
      browserHistory: widget.browserHistory,
      sessionId: 1,
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    routerConfig: App.router.config,
    restorationScopeId: 'app',
  );
}

Future<FdrRouter<AppRoute>> pumpApp(
  WidgetTester tester, {
  required String initialUrl,
  bool loggedIn = true,
  BrowserHistory browserHistory = const NoBrowserHistory(),
}) async {
  tester.binding.platformDispatcher.defaultRouteNameTestValue = initialUrl;
  await tester.pumpWidget(
    App(loggedIn: loggedIn, browserHistory: browserHistory),
  );
  await tester.pump(); // post-frame route information report
  return App.router;
}

Future<void> browserNavigatesTo(
  WidgetTester tester,
  String location, {
  Object? state,
}) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMethodCodec().encodeMethodCall(
      MethodCall('pushRouteInformation', {
        'location': location,
        'state': state,
      }),
    ),
    (_) {},
  );
  await tester.pumpAndSettle();
}

Map<String, Object?> envelope(int serial, [Object? h]) => {
  'fdr': 1,
  's': 1,
  'i': serial,
  'h': h,
};

String url(FdrRouter<AppRoute> router) => router.delegate.currentUrl!;

void main() {
  setUp(() {
    navLog.clear();
    platformLog.clear();
    AppNavigatorState.applied = 0;
    HomeNavigatorState.created = 0;
    OrdersNavigatorState.created = 0;
    OrdersNavigatorState.applied = 0;
    OrdersNavigatorState.builds = 0;
    OrdersNavigatorState.detailPops = 0;
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.navigation, (call) async {
      navLog.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      platformLog.add(call);
      return null;
    });
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher
        .clearDefaultRouteNameTestValue();
  });

  test('C10 golden URL table and round trips', () {
    const table = <(AppRoute, String)>[
      (LoginRoute(), '/login'),
      (
        LoginRoute(next: OrdersAt(OrderDetail(42))),
        '/login?next=%2Forders%2F42',
      ),
      (HomeAt(OrdersAt(OrderList())), '/orders'),
      (HomeAt(OrdersAt(OrderDetail(42))), '/orders/42'),
      (HomeAt(OrdersAt(OrderItem(42, 3))), '/orders/42/items/3'),
      (HomeAt(SettingsAt(SettingsRoot())), '/settings'),
      (HomeAt(SettingsAt(SettingsProfile())), '/settings/profile'),
    ];
    for (final (route, expected) in table) {
      expect(appCodec.encode(route).toString(), expected, reason: '$route');
      final parsed = appCodec.decode(Uri.parse(expected));
      expect(parsed, isNotNull, reason: expected);
      expect(appCodec.encode(parsed!).toString(), expected, reason: expected);
    }
    // aliases parse to canonical routes
    expect(
      appCodec.encode(appCodec.decode(Uri.parse('/'))!).toString(),
      '/orders',
    );
    expect(
      appCodec.encode(appCodec.decode(Uri.parse('/order/42'))!).toString(),
      '/orders/42',
    );
    expect(
      appCodec.encode(appCodec.decode(Uri.parse('/orders/42/'))!).toString(),
      '/orders/42',
    );
    for (final bad in [
      '/orders/abc',
      '/nope',
      '/orders/1/x',
      '/login/x',
      '/login?next=%2Fnope',
    ]) {
      expect(appCodec.decode(Uri.parse(bad)), isNull, reason: bad);
    }
    // not-found routes print the typed-in URL back
    expect(
      appCodec.encode(NotFoundRoute(Uri.parse('/nope?x=1'))).toString(),
      '/nope?x=1',
    );
  });

  testWidgets('C2 cold start on a deep URL builds the stack top-down', (
    tester,
  ) async {
    final router = await pumpApp(tester, initialUrl: '/orders/42');
    expect(find.text('Order 42'), findsOneWidget);
    expect(url(router), '/orders/42');
    expect(HomeNavigatorState.created, 1);
    expect(OrdersNavigatorState.created, 1);
    // the orders navigator saw the route exactly once, before its first build
    expect(OrdersNavigatorState.applied, 1);
    // the initial report replaces the engine's initial entry
    expect(reports.map((r) => (r.uri, r.replace)), [('/orders/42', true)]);
    expect(navLog.first.method, 'selectMultiEntryHistory');
  });

  testWidgets('C3 in-app navigation pushes, in-app pop becomes history.back', (
    tester,
  ) async {
    final history = FakeBrowserHistory();
    final router = await pumpApp(
      tester,
      initialUrl: '/orders',
      browserHistory: history,
    );
    await tester.tap(find.byKey(const Key('open-42')));
    await tester.pumpAndSettle();
    expect(url(router), '/orders/42');
    // the entry being left is refreshed (replace), then the new one pushed
    expect(reports.map((r) => (r.uri, r.replace)).skip(1).toList(), [
      ('/orders', true),
      ('/orders/42', false),
    ]);
    expect(router.provider.shadowHistory, ['/orders', '/orders/42']);
    expect(router.provider.shadowIndex, 1);
    final reportsBeforePop = reports.length;

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Order 42'), findsNothing);
    expect(url(router), '/orders');
    // no new entry: a real browser back was requested instead
    expect(history.backs, 1);
    expect(reports.length, reportsBeforePop);
    expect(router.provider.shadowIndex, 0);

    // the engine delivers the previous entry; the app already shows it, so
    // the delivery is absorbed: nothing applied, nothing reported
    final appliedBefore = OrdersNavigatorState.applied;
    expect(router.provider.pendingBacks, 1);
    await browserNavigatesTo(tester, '/orders', state: envelope(1));
    expect(router.provider.pendingBacks, 0);
    expect(OrdersNavigatorState.applied, appliedBefore);
    expect(url(router), '/orders');
    expect(reports.length, reportsBeforePop);

    // browser forward re-opens the popped page from its real entry
    await browserNavigatesTo(tester, '/orders/42', state: envelope(2));
    expect(find.text('Order 42'), findsOneWidget);
    expect(router.provider.shadowIndex, 1);
  });

  testWidgets(
    'C3 in-app pop without browser history pushes (Flutter default)',
    (tester) async {
      final router = await pumpApp(tester, initialUrl: '/orders');
      await tester.tap(find.byKey(const Key('open-42')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(url(router), '/orders');
      expect((reports.last.uri, reports.last.replace), ('/orders', false));
      expect(router.provider.shadowHistory, [
        '/orders',
        '/orders/42',
        '/orders',
      ]);
    },
  );

  testWidgets('C3 a state-only change (popup) and a wizard-style replace', (
    tester,
  ) async {
    final router = await pumpApp(tester, initialUrl: '/orders/42');
    await tester.tap(find.byKey(const Key('popup')));
    await tester.pumpAndSettle();
    expect(find.text('Popup content'), findsOneWidget);
    // C4: the popup has no URL, the URL stays at the page below
    expect(url(router), '/orders/42');
    expect(reports.every((r) => r.uri == '/orders/42' && r.replace), isTrue);
    expect(router.provider.shadowHistory, ['/orders/42']);

    // C11/C4: system back dismisses the popup through its onPop
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Popup content'), findsNothing);
    expect(find.text('Order 42'), findsOneWidget);
    expect(url(router), '/orders/42');
  });

  testWidgets('C8 re-applying the current URL touches no state', (
    tester,
  ) async {
    final router = await pumpApp(tester, initialUrl: '/orders/42');
    final applied = (AppNavigatorState.applied, OrdersNavigatorState.applied);
    final builds = OrdersNavigatorState.builds;
    await browserNavigatesTo(tester, '/orders/42');
    expect((AppNavigatorState.applied, OrdersNavigatorState.applied), applied);
    expect(OrdersNavigatorState.builds, builds);
    expect(OrdersNavigatorState.created, 1);
    expect(url(router), '/orders/42');
  });

  testWidgets('C2 an incoming URL change reuses the retained state', (
    tester,
  ) async {
    final router = await pumpApp(tester, initialUrl: '/orders/42');
    await tester.tap(find.byKey(const Key('bump')));
    await tester.pumpAndSettle();
    expect(find.text('counter 1'), findsWidgets);

    await browserNavigatesTo(tester, '/orders/7');
    expect(find.text('Order 7'), findsOneWidget);
    expect(find.text('Order 42'), findsNothing);
    // same state object: non-URL state survives, nothing was recreated
    expect(OrdersNavigatorState.created, 1);
    expect(HomeNavigatorState.created, 1);
    expect(find.text('counter 1'), findsWidgets);
    expect(url(router), '/orders/7');
  });

  testWidgets('C5 logged-out deep link: login, then land on the target', (
    tester,
  ) async {
    final router = await pumpApp(
      tester,
      initialUrl: '/orders/42',
      loggedIn: false,
    );
    expect(find.text('Log in'), findsOneWidget);
    expect(url(router), '/login?next=%2Forders%2F42');
    expect(reports.map((r) => (r.uri, r.replace)), [
      ('/login?next=%2Forders%2F42', true),
    ]);
    expect(HomeNavigatorState.created, 0);

    await tester.tap(find.byKey(const Key('login')));
    await tester.pumpAndSettle();
    expect(find.text('Order 42'), findsOneWidget);
    expect(url(router), '/orders/42');
    expect(reports.last.uri, '/orders/42');
    expect(reports.last.replace, isTrue);

    // logout from anywhere
    await tester.tap(find.byKey(const Key('logout')));
    await tester.pumpAndSettle();
    expect(find.text('Log in'), findsOneWidget);
    expect(url(router), '/login');
    expect(reports.last.uri, '/login');
    expect(reports.last.replace, isFalse);
    // opening /login while logged in redirects home
    await tester.tap(find.byKey(const Key('login')));
    await tester.pumpAndSettle();
    await browserNavigatesTo(tester, '/login');
    expect(find.text('Orders'), findsOneWidget);
    expect(url(router), '/orders');
  });

  testWidgets('C6 unknown URL: not-found page keeps the typed URL', (
    tester,
  ) async {
    final router = await pumpApp(tester, initialUrl: '/nope?x=1');
    expect(find.text('No page at /nope?x=1'), findsOneWidget);
    expect(url(router), '/nope?x=1');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Orders'), findsOneWidget);
    expect(url(router), '/orders');
  });

  testWidgets('C6 legacy and non-canonical URLs are corrected in place', (
    tester,
  ) async {
    final router = await pumpApp(tester, initialUrl: '/order/42');
    expect(find.text('Order 42'), findsOneWidget);
    expect(url(router), '/orders/42');
    expect(reports.map((r) => (r.uri, r.replace)), [('/orders/42', true)]);

    await browserNavigatesTo(tester, '/orders/42/');
    expect(url(router), '/orders/42');
    await browserNavigatesTo(tester, '/');
    expect(find.text('Orders'), findsOneWidget);
    expect(url(router), '/orders');
    expect(reports.last.replace, isTrue);
  });

  testWidgets('C11 Android back pops through the state, exits at the root', (
    tester,
  ) async {
    final router = await pumpApp(tester, initialUrl: '/orders/42');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Order 42'), findsNothing);
    expect(url(router), '/orders');
    expect(
      platformLog.where((c) => c.method == 'SystemNavigator.pop'),
      isEmpty,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      platformLog.map((c) => c.method).where((m) => m == 'SystemNavigator.pop'),
      ['SystemNavigator.pop'],
    );
  });

  testWidgets('C7 tab stacks survive switching, URL follows the active one', (
    tester,
  ) async {
    final router = await pumpApp(tester, initialUrl: '/orders');
    await tester.tap(find.byKey(const Key('open-42')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tab-settings')));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(url(router), '/settings');
    expect(reports.last.replace, isFalse);
    await tester.tap(find.byKey(const Key('profile')));
    await tester.pumpAndSettle();
    expect(url(router), '/settings/profile');

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tab-orders')));
    await tester.pumpAndSettle();
    expect(find.text('Order 42'), findsOneWidget);
    expect(url(router), '/orders/42');
    expect(OrdersNavigatorState.created, 1);
  });

  testWidgets('C7 history state travels with the browser entry', (
    tester,
  ) async {
    final router = await pumpApp(tester, initialUrl: '/orders');
    await tester.tap(find.byKey(const Key('scroll')));
    await tester.tap(find.byKey(const Key('tab-settings')));
    await tester.pumpAndSettle();
    // the entry being left was refreshed with the scroll offset
    final refreshed = reports.firstWhere(
      (r) =>
          r.uri == '/orders' &&
          r.state != null &&
          (r.state! as Map)['h'] != null,
    );
    final h = (refreshed.state! as Map)['h'] as Map;
    expect(h.toString(), contains('scroll: 120'));

    // back arrives with that state; the orders page shows the offset
    await browserNavigatesTo(tester, '/orders', state: envelope(1, h));
    expect(find.text('scroll 120.0'), findsOneWidget);
    expect(url(router), '/orders');
  });

  testWidgets('C11 process-death restoration rebuilds the stack', (
    tester,
  ) async {
    await pumpApp(tester, initialUrl: '/orders');
    await tester.tap(find.byKey(const Key('scroll')));
    await tester.tap(find.byKey(const Key('open-42')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bump')));
    await tester.pumpAndSettle();
    expect(find.text('counter 1'), findsWidgets);
    final oldRouter = App.router;

    await tester.restartAndRestore();
    await tester.pumpAndSettle();
    expect(App.router, isNot(same(oldRouter)));
    expect(find.text('Order 42'), findsOneWidget);
    expect(url(App.router), '/orders/42');
    expect(OrdersNavigatorState.created, 2);
    // counter is not part of the history state, scroll is
    expect(find.text('counter 0'), findsWidgets);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('scroll 120.0'), findsOneWidget);
  });

  testWidgets('C9 hot reload rebuilds every navigator', (tester) async {
    final router = await pumpApp(tester, initialUrl: '/orders/42');
    final builds = OrdersNavigatorState.builds;
    final reportsBefore = reports.length;
    // performReassemble awaits endOfFrame, which the automated binding only
    // completes on the next pump; so do not await it before pumping
    unawaited(tester.binding.reassembleApplication());
    await tester.pump();
    await tester.pump();
    expect(OrdersNavigatorState.builds, greaterThan(builds));
    expect(find.text('Order 42'), findsOneWidget);
    // the URL is re-reported in place, never as a new entry
    expect(url(router), '/orders/42');
    expect(reports.skip(reportsBefore).every((r) => r.replace), isTrue);
    expect(router.provider.shadowHistory, ['/orders/42']);
  });

  testWidgets('C3/C8 a declarative removal does not run onPop again', (
    tester,
  ) async {
    final router = await pumpApp(tester, initialUrl: '/orders/42');
    // the Navigator calls Page.onPopInvoked(true) for the page it animates
    // out after the pages list changed; the callback must not fire then
    await browserNavigatesTo(tester, '/orders');
    expect(find.text('Order 42'), findsNothing);
    expect(OrdersNavigatorState.detailPops, 0);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('open-42')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(OrdersNavigatorState.detailPops, 1);
    expect(url(router), '/orders');
  });

  testWidgets('imperative Navigator.pop of a non-poppable page is an error', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/';
    final router = FdrRouter<FixedRoute>(
      root: const FixedNavigator(),
      codec: fixedCodec,
      notFound: (_) => const FixedTop(),
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
    await tester.pump();
    expect(find.text('top'), findsOneWidget);
    // system back is vetoed by Page.canPop == false: nothing happens
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('top'), findsOneWidget);
    expect(
      platformLog.where((c) => c.method == 'SystemNavigator.pop'),
      isEmpty,
    );
    // Navigator.pop bypasses canPop; the library reports it instead of
    // crashing on a null callback (fdr 0.0.5); the route stays gone until the
    // next build, where the unchanged state re-pushes the page
    router.delegate.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(
      tester.takeException(),
      isA<FlutterError>().having(
        (e) => e.message,
        'message',
        contains('popped imperatively'),
      ),
    );
    expect(find.text('top'), findsNothing);
    expect(find.text('bottom'), findsOneWidget);
  });

  testWidgets('a state-driven removal (Done button) is a pop, not a push', (
    tester,
  ) async {
    final history = FakeBrowserHistory();
    await pumpApp(tester, initialUrl: '/orders', browserHistory: history);
    await tester.tap(find.byKey(const Key('open-42')));
    await tester.pumpAndSettle();
    final reportsBefore = reports.length;
    await tester.tap(find.byKey(const Key('done')));
    await tester.pumpAndSettle();
    expect(find.text('Order 42'), findsNothing);
    // onPop is not involved, yet the history goes back instead of [A, B, A]
    expect(OrdersNavigatorState.detailPops, 0);
    expect(history.backs, 1);
    expect(reports.length, reportsBefore);
  });

  testWidgets('two quick pops traverse twice; forward re-opens both levels', (
    tester,
  ) async {
    final history = FakeBrowserHistory();
    final router = await pumpApp(
      tester,
      initialUrl: '/orders',
      browserHistory: history,
    );
    await tester.tap(find.byKey(const Key('open-42')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item-3')));
    await tester.pumpAndSettle();
    expect(url(router), '/orders/42/items/3');
    expect(router.provider.shadowHistory, [
      '/orders',
      '/orders/42',
      '/orders/42/items/3',
    ]);
    final reportsBefore = reports.length;

    // item -> detail -> list, both before the browser delivered anything
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(url(router), '/orders');
    expect(history.backs, 2);
    expect(router.provider.pendingBacks, 2);

    // the intermediate entry is absorbed, the detail page never flashes
    await browserNavigatesTo(tester, '/orders/42', state: envelope(2));
    expect(find.text('Order 42'), findsNothing);
    await browserNavigatesTo(tester, '/orders', state: envelope(1));
    expect(router.provider.pendingBacks, 0);
    expect(reports.length, reportsBefore);
    expect(router.provider.shadowIndex, 0);

    // no popped page resurrects on back; forward walks the real entries
    await browserNavigatesTo(tester, '/orders/42', state: envelope(2));
    expect(find.text('Order 42'), findsOneWidget);
    await browserNavigatesTo(tester, '/orders/42/items/3', state: envelope(3));
    expect(find.text('Item 3 of 42'), findsOneWidget);
    expect(OrdersNavigatorState.created, 1);
  });

  testWidgets('navigation while a back is in flight is reported after it', (
    tester,
  ) async {
    final history = FakeBrowserHistory();
    final router = await pumpApp(
      tester,
      initialUrl: '/orders',
      browserHistory: history,
    );
    await tester.tap(find.byKey(const Key('open-42')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(router.provider.pendingBacks, 1);
    final reportsBefore = reports.length;

    // the user switches tabs before the browser delivered the back
    await tester.tap(find.byKey(const Key('tab-settings')));
    await tester.pumpAndSettle();
    expect(url(router), '/settings');
    expect(reports.length, reportsBefore);

    // the stale entry is absorbed and the tab switch is pushed on top of it
    await browserNavigatesTo(tester, '/orders', state: envelope(1));
    expect(find.text('Settings'), findsOneWidget);
    expect((reports.last.uri, reports.last.replace), ('/settings', false));
    expect(router.provider.shadowHistory, ['/orders', '/settings']);
  });

  testWidgets('a pop racing an unrelated rebuild is not swallowed', (
    tester,
  ) async {
    final router = await pumpApp(tester, initialUrl: '/orders/42');
    final orders = OrdersNavigatorState.latest!;
    // same event: an unrelated state change, then an imperative pop that
    // still targets the route built before that change
    orders.setState(() => orders.counter++);
    router.delegate.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Order 42'), findsNothing);
    expect(OrdersNavigatorState.detailPops, 1);
    expect(url(router), '/orders');
    expect(tester.takeException(), isNull);
  });

  for (final guarded in [true, false]) {
    testWidgets('Android back on the root page (guarded: $guarded)', (
      tester,
    ) async {
      GuardedNavigatorState.vetoes = 0;
      tester.binding.platformDispatcher.defaultRouteNameTestValue = '/';
      final router = FdrRouter<FixedRoute>(
        root: GuardedNavigator(guarded: guarded),
        codec: fixedCodec,
        notFound: (_) => const FixedTop(),
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      final exits = platformLog.where((c) => c.method == 'SystemNavigator.pop');
      // a PopScope on the root page vetoes; without one the app is left
      expect(exits, guarded ? isEmpty : hasLength(1));
      expect(GuardedNavigatorState.vetoes, guarded ? 1 : 0);
      // the bottom page shows no back button although Page.canPop is true
      expect(find.byType(BackButton), findsNothing);
    });
  }

  testWidgets('OS deep links: custom scheme and https', (tester) async {
    final router = await pumpApp(tester, initialUrl: '/orders');
    await browserNavigatesTo(tester, 'myapp://orders/42');
    expect(url(router), '/orders/42');
    await browserNavigatesTo(tester, 'https://shop.example/orders/7');
    expect(url(router), '/orders/7');
    expect(OrdersNavigatorState.created, 1);
  });

  test('parsing backtracks: a prefix match does not hide a full match', () {
    final a = Case<String, String>(
      lit('a').iso(to: (_) => 'a', from: (_) => ()),
    );
    final ab = Case<String, String>(
      lit('a').then(lit('b')).iso(to: (_) => 'ab', from: (_) => ()),
    );
    final codec = SumCodec<String>(
      cases: [a, ab],
      select: (v) => v == 'a' ? a.bind(v) : ab.bind(v),
    );
    expect(codec.decode(Uri.parse('/a')), 'a');
    expect(codec.decode(Uri.parse('/a/b')), 'ab');
    // also through nesting: the orders sum is tried inside the app sum
    expect(
      appCodec.encode(appCodec.decode(Uri.parse('/orders/42/items/3'))!).path,
      '/orders/42/items/3',
    );
  });

  testWidgets('closing two levels at once goes back two entries', (
    tester,
  ) async {
    final history = FakeBrowserHistory();
    final router = await pumpApp(
      tester,
      initialUrl: '/orders',
      browserHistory: history,
    );
    await tester.tap(find.byKey(const Key('open-42')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item-3')));
    await tester.pumpAndSettle();
    final orders = OrdersNavigatorState.latest!;
    orders.setState(() => orders.selectedId = null);
    await tester.pumpAndSettle();
    expect(url(router), '/orders');
    expect(history.deltas, [-2]);
    await browserNavigatesTo(tester, '/orders', state: envelope(1));
    expect(router.provider.pendingBacks, 0);
    expect(router.provider.shadowIndex, 0);
  });
}
