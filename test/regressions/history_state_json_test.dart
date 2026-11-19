import 'package:fdr/fdr.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'routes.dart';

// historyState has to be JSON. A value that is not used to fail in the
// report after the frame, in the codec of the navigation channel: without
// a hint at the navigator, and with the URL no longer following the app.

class Shelf extends StatefulNavigator<RR> {
  const Shelf();
  @override
  ShelfState createState() => ShelfState();
}

class ShelfState extends StatefulNavigatorState<Shelf, RR> {
  static late ShelfState latest;
  RR shown = const RA();
  Object? kept;

  @override
  void initState() {
    super.initState();
    latest = this;
  }

  @override
  void applyRoute(RR route) => shown = route;

  @override
  Object? get historyState => kept;

  @override
  List<NavEntry<RR>> build() => [
    const NavPage(route: RA(), child: Text('A')),
    if (shown is RB)
      NavPage(
        route: const RB(),
        onPop: () => setState(() => shown = const RA()),
        child: const Text('B'),
      ),
  ];
}

void main() {
  final sent = <Map<Object?, Object?>>[];

  Future<FdrRouter<RR>> start(WidgetTester tester) async {
    sent.clear();
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.navigation, (call) async {
      if (call.method == 'routeInformationUpdated') {
        sent.add(call.arguments as Map);
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.navigation, null),
    );
    final router = FdrRouter<RR>(
      root: const Shelf(),
      fromUrl: RR.fromUrl,
      initialRouteInformation: RouteInformation(uri: Uri.parse('/')),
      sessionId: 1,
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      WidgetsApp.router(
        color: const Color(0xFF000000),
        routerConfig: router.config,
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  for (final (name, value) in [
    ('NaN', {'scroll': double.nan}),
    ('a DateTime', {'since': DateTime(2026)}),
    ('a key that is no String', {1: 'one'}),
  ]) {
    testWidgets('a history state with $name names the navigator and does '
        'not stop the URL', (tester) async {
      final router = await start(tester);
      final shelf = ShelfState.latest;
      shelf.kept = value;
      router.open(const RB());
      await tester.pumpAndSettle();

      final error = tester.takeException();
      expect(error, isFlutterError);
      expect('$error', contains('ShelfState'));
      expect(tester.takeException(), isNull);
      // the entries are written without the state
      expect(
        [for (final report in sent) (report['uri'], report['replace'])],
        [('/', true), ('/', true), ('/b', false)],
      );
      expect((sent.last['state']! as Map)['h'], isNull);

      // and with it again once it is JSON
      shelf.setState(() => shelf.kept = {'scroll': 2.5});
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(sent.last['uri'], '/b');
      expect('${(sent.last['state']! as Map)['h']}', contains('scroll: 2.5'));
    });
  }

  testWidgets('a JSON history state is written as it is', (tester) async {
    final router = await start(tester);
    final shelf = ShelfState.latest;
    const state = {
      'scroll': 1.5,
      'open': true,
      'ids': [1, 'two', null],
    };
    shelf.kept = state;
    router.open(const RB());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final written = (sent.last['state']! as Map)['h'];
    expect(((written as Map)['0'] as Map)['s'], state);
  });
}
