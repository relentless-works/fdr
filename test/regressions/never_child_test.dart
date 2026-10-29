import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'routes.dart';

// a navigator without URLs, e.g. a help overlay flow
class Help extends StatefulNavigator<Never> {
  const Help();
  @override
  HelpState createState() => HelpState();
}

class HelpState extends StatefulNavigatorState<Help, Never> {
  @override
  List<NavEntry<Never>> build() => [NavPage(child: scaffold('help'))];
}

class Root extends StatefulNavigator<RR> {
  const Root();
  @override
  RootState createState() => RootState();
}

class RootState extends StatefulNavigatorState<Root, RR> {
  RR shown = const RA();
  bool help = true;

  @override
  void applyRoute(RR route) => shown = route;

  @override
  List<NavEntry<RR>> build() => [
    NavPage(route: const RA(), child: scaffold('A')),
    if (shown is RB) NavPage(route: const RB(), child: scaffold('B')),
    // "Items without a URL (DialogPage, navigators with route type Never)
    // fit into every list."
    if (help) const Help(),
  ];
}

void main() {
  testWidgets('a Never navigator placed directly survives an incoming route', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/';
    final router = FdrRouter<RR>(root: const Root(), fromUrl: RR.fromUrl);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
    await tester.pump();
    expect(find.text('help'), findsOneWidget);

    router.open(const RB());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(router.currentUrl, '/b');
  });
}
