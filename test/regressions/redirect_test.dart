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
  static int created = 0;
  static int disposed = 0;
  RR shown = const RA();

  @override
  void initState() {
    super.initState();
    created++;
  }

  @override
  void dispose() {
    disposed++;
    super.dispose();
  }

  @override
  void applyRoute(RR route) {
    // /b moved to /c
    if (route is RB) {
      open(const RC(), history: HistoryAction.replace);
      return;
    }
    shown = route;
  }

  @override
  List<NavEntry<RR>> build() => [
    NavPage(route: const RA(), child: scaffold('A')),
    if (shown is RC)
      NavPage(
        route: const RC(),
        onPop: () => setState(() => shown = const RA()),
        child: scaffold('C'),
      ),
  ];
}

void main() {
  testWidgets('open() from applyRoute (a redirect) lands on the target', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/';
    final router = FdrRouter<RR>(root: const Root(), fromUrl: RR.fromUrl);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
    await tester.pump();
    expect(RootState.created, 1);

    router.open(const RB());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('C'), findsOneWidget);
    expect(router.currentUrl, '/c');
    expect((RootState.created, RootState.disposed), (1, 0));
  });
}
