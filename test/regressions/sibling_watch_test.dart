import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'routes.dart';

// selection view model shared by two sibling navigators
final selection = ValueNotifier<RR>(const RA());

class Badge extends StatefulNavigator<RR> {
  const Badge();
  @override
  BadgeState createState() => BadgeState();
}

class BadgeState extends StatefulNavigatorState<Badge, RR> {
  @override
  void initState() {
    super.initState();
    watch(selection);
  }

  @override
  void applyRoute(RR route) {}

  @override
  List<NavEntry<RR>> build() => [
    NavPage(route: const RA(), child: scaffold('badge ${selection.value}')),
  ];
}

class Detail extends StatefulNavigator<RR> {
  const Detail();
  @override
  DetailState createState() => DetailState();
}

class DetailState extends StatefulNavigatorState<Detail, RR> {
  @override
  void applyRoute(RR route) => selection.value = route;

  @override
  List<NavEntry<RR>> build() => [
    if (selection.value case final RC route)
      NavPage(route: route, child: scaffold('C')),
  ];
}

class Root extends StatelessNavigator<RR> {
  const Root();
  @override
  List<NavEntry<RR>> build() => const [Badge(), Detail()];
}

void main() {
  testWidgets('a sibling notified during an incoming pass', (tester) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/';
    final router = FdrRouter<RR>(root: const Root(), fromUrl: RR.fromUrl);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
    await tester.pump();
    router.open(const RC());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(router.currentUrl, '/c');
  });
}
