import 'package:fdr/fdr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'routes.dart';

class _Root extends StatefulNavigator<RR> {
  const _Root({required this.overrides, required this.callsSuper});
  final bool overrides;
  final bool callsSuper;

  static late StatefulNavigatorState<_Root, RR> latest;

  @override
  StatefulNavigatorState<_Root, RR> createState() =>
      latest = overrides ? _RootState() : _NoApplyRouteState();
}

class _RootState extends StatefulNavigatorState<_Root, RR> {
  RR shown = const RA();

  @override
  void applyRoute(RR route) {
    if (navigator.callsSuper) super.applyRoute(route);
    shown = route;
  }

  @override
  List<NavEntry<RR>> build() => [NavPage(route: shown, child: Text('$shown'))];
}

class _NoApplyRouteState extends StatefulNavigatorState<_Root, RR> {
  @override
  List<NavEntry<RR>> build() => [
    const NavPage(route: RA(), child: Text('page')),
  ];
}

// open() applies the route to the root at once, like an incoming URL
Future<void Function()> _openB(
  WidgetTester tester, {
  required bool overrides,
  required bool callsSuper,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: DeclarativeNavigator(
        navigator: _Root(overrides: overrides, callsSuper: callsSuper),
      ),
    ),
  );
  final state = _Root.latest;
  return () => state.open(const RB());
}

Matcher _assertion(String message) => throwsA(
  isA<AssertionError>().having(
    (e) => '${e.message}',
    'message',
    contains(message),
  ),
);

void main() {
  testWidgets('an applyRoute that calls super is told not to', (tester) async {
    final open = await _openB(tester, overrides: true, callsSuper: true);
    expect(open, _assertion('calls super.applyRoute'));
  });

  testWidgets('a navigator without applyRoute is told to override it', (
    tester,
  ) async {
    final open = await _openB(tester, overrides: false, callsSuper: false);
    expect(open, _assertion('does not override applyRoute'));
  });

  testWidgets('an applyRoute without super gets the route', (tester) async {
    final open = await _openB(tester, overrides: true, callsSuper: false);
    open();
    await tester.pump();
    expect(find.text('${const RB()}'), findsOneWidget);
  });
}
