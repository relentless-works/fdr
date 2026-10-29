import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
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
    if (shown is RB) NavPage(route: const RB(), child: scaffold('B')),
  ];
}

void main() {
  testWidgets('a deep link with Latin-1 percent-encoding', (tester) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/b/caf%E9';
    final router = FdrRouter<RR>(root: const Root(), fromUrl: RR.fromUrl);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
    await tester.pump();
    final error = tester.takeException();
    expect(error, isNull);
    expect(find.textContaining('No page'), findsOneWidget);
  });
}
