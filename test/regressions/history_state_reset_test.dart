import 'dart:convert';

import 'package:fdr/fdr.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'routes.dart';

// Navigators whose historyState is null in their default state, the
// pattern of the docs (`scroll == 0 ? null : {...}`), and which take a
// restored null as that default.

class Root extends StatefulNavigator<RR> {
  const Root();
  @override
  RootState createState() => RootState();
}

class RootState extends StatefulNavigatorState<Root, RR> {
  static late RootState latest;
  RR shown = const RA();
  int scroll = 0;

  @override
  void initState() {
    super.initState();
    latest = this;
  }

  @override
  void applyRoute(RR route) => shown = route;

  @override
  Object? get historyState => scroll == 0 ? null : {'scroll': scroll};

  @override
  void restoreHistoryState(Object? state) {
    scroll = state is Map ? state['scroll']! as int : 0;
  }

  @override
  List<NavEntry<RR>> build() => [
    NavPage(route: const RA(), child: scaffold('A')),
    const Counter(),
    TabsPage(
      index: 0,
      tabs: const [Counter(inTab: true)],
      builder: (context, tabs) => tabs.single,
    ),
    if (shown is RB)
      NavPage(
        route: const RB(),
        onPop: () => setState(() => shown = const RA()),
        child: scaffold('B'),
      ),
  ];
}

class Counter extends StatefulNavigator<Never> {
  const Counter({this.inTab = false});
  final bool inTab;
  @override
  CounterState createState() => CounterState();
}

class CounterState extends StatefulNavigatorState<Counter, Never> {
  static final latest = <bool, CounterState>{};
  int count = 0;

  @override
  void initState() {
    super.initState();
    latest[navigator.inTab] = this;
  }

  @override
  Object? get historyState => count == 0 ? null : {'count': count};

  @override
  void restoreHistoryState(Object? state) {
    count = state is Map ? state['count']! as int : 0;
  }

  @override
  List<NavEntry<Never>> build() => [NavPage(child: Text('count $count'))];
}

CounterState get counter => CounterState.latest[false]!;
CounterState get tabCounter => CounterState.latest[true]!;

final sent = <Map<Object?, Object?>>[];

// what the browser holds for an entry: the last report with its serial
Map<Object?, Object?> stored(int serial) => sent
    .map((report) => report['state']! as Map<Object?, Object?>)
    .lastWhere((state) => state['i'] == serial);

Future<void> deliver(WidgetTester tester, String location, Object? state) {
  return tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMethodCodec().encodeMethodCall(
      MethodCall('pushRouteInformation', {
        'location': location,
        'state': state,
      }),
    ),
    (_) {},
  );
}

Future<FdrRouter<RR>> start(WidgetTester tester) async {
  sent.clear();
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.navigation,
    (call) async {
      if (call.method == 'routeInformationUpdated') {
        sent.add(call.arguments as Map);
      }
      return null;
    },
  );
  final router = FdrRouter<RR>(
    root: const Root(),
    fromUrl: RR.fromUrl,
    initialRouteInformation: RouteInformation(uri: Uri.parse('/')),
    sessionId: 1,
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('back to an entry without history state resets it', (
    tester,
  ) async {
    final router = await start(tester);
    router.open(const RB());
    await tester.pumpAndSettle();
    expect(router.provider.shadowHistory, ['/', '/b']);

    // states that survive the URL change change while B is on top
    RootState.latest.setState(() => RootState.latest.scroll = 5);
    counter.setState(() => counter.count = 3);
    tabCounter.setState(() => tabCounter.count = 4);
    await tester.pumpAndSettle();
    expect(stored(1)['h'], isNull);

    await deliver(tester, '/', stored(1));
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/');
    expect(RootState.latest.scroll, 0);
    expect(counter.count, 0);
    expect(tabCounter.count, 0);
    expect(find.text('count 0', skipOffstage: false), findsNWidgets(2));
  });

  testWidgets('a navigator without state in an entry whose children have '
      'some is reset', (tester) async {
    final router = await start(tester);
    counter.setState(() => counter.count = 3);
    await tester.pumpAndSettle();
    router.open(const RB());
    await tester.pumpAndSettle();
    RootState.latest.setState(() => RootState.latest.scroll = 5);
    await tester.pumpAndSettle();

    await deliver(tester, '/', stored(1));
    await tester.pumpAndSettle();
    expect(RootState.latest.scroll, 0);
    expect(counter.count, 3);
    // the pages are rebuilt with the restored state (below the tabs page)
    expect(find.text('count 3', skipOffstage: false), findsOneWidget);
  });

  testWidgets('an entry the app did not write keeps the state', (tester) async {
    final router = await start(tester);
    RootState.latest.setState(() => RootState.latest.scroll = 5);
    await tester.pumpAndSettle();

    // e.g. a typed URL: there is no history state to apply
    await deliver(tester, '/b', null);
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/b');
    expect(RootState.latest.scroll, 5);
  });

  testWidgets('a navigator that cannot read its state does not keep the '
      'others from theirs', (tester) async {
    final router = await start(tester);
    RootState.latest.setState(() => RootState.latest.scroll = 5);
    counter.setState(() => counter.count = 3);
    await tester.pumpAndSettle();
    router.open(const RB());
    await tester.pumpAndSettle();
    counter.setState(() => counter.count = 9);
    await tester.pumpAndSettle();

    // the entry as an earlier build of the app wrote it
    final entry = jsonDecode(
      jsonEncode(stored(1)).replaceFirst('"scroll":5', '"scroll":"x"'),
    );
    await deliver(tester, '/', entry);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isA<TypeError>());
    expect(router.currentUrl, '/');
    expect(RootState.latest.scroll, 5);
    expect(counter.count, 3);
    expect(find.text('count 3', skipOffstage: false), findsOneWidget);
  });
}
