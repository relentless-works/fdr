import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../routes.dart';

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
  // before any binding exists: creating the router must not install one,
  // or the test binding (like integration_test's, or an app's own) cannot
  // be installed after it
  final router = FdrRouter<RR>(root: const Root(), fromUrl: RR.fromUrl);

  testWidgets('a router created before the test binding', (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
    await tester.pumpAndSettle();
    expect(find.text('A'), findsOneWidget);
    expect(router.currentUrl, '/');

    router.open(const RB());
    await tester.pumpAndSettle();
    expect(find.text('B'), findsOneWidget);
  });
}
