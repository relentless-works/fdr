import 'package:fdr/fdr.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'routes.dart';

// A navigator's history state is stored under its restorationType, and
// restored only into a navigator with the same one: a stable tag survives
// a rename of the state class (or minification), another tag is not read.

class Root extends StatefulNavigator<RR> {
  const Root();
  @override
  RootState createState() => RootState();
}

class RootState extends StatefulNavigatorState<Root, RR> {
  static late RootState latest;
  int n = 0;

  @override
  void initState() {
    super.initState();
    latest = this;
  }

  @override
  void applyRoute(RR route) {}

  @override
  String get restorationType => 'Stable';

  @override
  Object? get historyState => n == 0 ? null : {'n': n};

  @override
  void restoreHistoryState(Object? state) =>
      n = state is Map ? state['n']! as int : 0;

  @override
  List<NavEntry<RR>> build() => [
    NavPage(route: const RA(), child: scaffold('n $n')),
  ];
}

void main() {
  late FdrRouter<RR> router;
  late List<Object?> written;

  setUp(() => written = []);

  Future<void> start(WidgetTester tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.navigation,
      (call) async {
        if (call.method == 'routeInformationUpdated') {
          written.add((call.arguments as Map)['state']);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.navigation,
        null,
      ),
    );
    router = FdrRouter<RR>(
      root: const Root(),
      fromUrl: RR.fromUrl,
      initialRouteInformation: RouteInformation(uri: Uri.parse('/')),
      sessionId: 1,
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
    await tester.pumpAndSettle();
  }

  // browser back or forward to an entry of this session at /
  Future<void> traverseTo(WidgetTester tester, Object? tree) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(
        MethodCall('pushRouteInformation', {
          'location': '/',
          'state': {'fdr': 1, 's': 1, 'i': 9, 'h': tree},
        }),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the history state is written under restorationType', (
    tester,
  ) async {
    await start(tester);
    RootState.latest.setState(() => RootState.latest.n = 3);
    await tester.pumpAndSettle();
    expect((written.last! as Map)['h'], {
      '0': {
        't': 'Stable',
        's': {'n': 3},
      },
    });
  });

  testWidgets('it is restored into a state with that restorationType', (
    tester,
  ) async {
    await start(tester);
    await traverseTo(tester, {
      '0': {
        't': 'Stable',
        's': {'n': 7},
      },
    });
    expect(RootState.latest.n, 7);
    expect(find.text('n 7'), findsOneWidget);
  });

  testWidgets('a state with another restorationType is not read', (
    tester,
  ) async {
    await start(tester);
    RootState.latest.setState(() => RootState.latest.n = 3);
    await tester.pumpAndSettle();
    // written by a build that did not override restorationType
    await traverseTo(tester, {
      '0': {
        't': 'RootState',
        's': {'n': 7},
      },
    });
    // the entry holds nothing for this navigator: it had no state then
    expect(RootState.latest.n, 0);
    expect(find.text('n 0'), findsOneWidget);
  });
}
