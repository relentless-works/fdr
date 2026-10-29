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
    NavPage(
      route: const RA(),
      child: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => RouteLink(
                route: const RB(),
                builder: (context, open) =>
                    TextButton(onPressed: open, child: const Text('to B')),
              ),
            ),
            child: const Text('sheet'),
          ),
        ),
      ),
    ),
    if (shown is RB) NavPage(route: const RB(), child: scaffold('B')),
  ];
}

void main() {
  testWidgets('a link in a modal bottom sheet', (tester) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/';
    final router = FdrRouter<RR>(root: const Root(), fromUrl: RR.fromUrl);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
    await tester.pump();
    await tester.tap(find.text('sheet'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('to B'), findsOneWidget);
  });
}
