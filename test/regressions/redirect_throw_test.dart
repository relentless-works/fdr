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
  bool failNextBuild = false;

  @override
  void applyRoute(RR route) {
    if (route is RB) {
      // a redirect, in an update that then fails
      open(const RC(), history: HistoryAction.replace);
      failNextBuild = true;
      return;
    }
    shown = route;
  }

  @override
  List<NavEntry<RR>> build() {
    if (failNextBuild) {
      failNextBuild = false;
      throw StateError('build boom');
    }
    return [
      NavPage(route: const RA(), child: scaffold('A')),
      if (shown is RC) NavPage(route: const RC(), child: scaffold('C')),
    ];
  }
}

void main() {
  testWidgets('a redirect queued in a pass that throws does not fire later', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final router = FdrRouter<RR>(root: const Root(), fromUrl: RR.fromUrl);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
    await tester.pump();
    expect(router.currentUrl, '/');

    Object? thrown;
    try {
      router.open(const RB());
    } catch (e) {
      thrown = e;
    }
    await tester.pumpAndSettle();
    expect(thrown, isStateError);
    expect(router.currentUrl, '/');

    // an unrelated navigation, long after the failed one
    router.open(const RA());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(router.currentUrl, '/', reason: 'stale queued redirect to /c ran');
    expect(find.text('C'), findsNothing);
  });
}
