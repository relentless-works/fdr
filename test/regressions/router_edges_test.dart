import 'dart:async';

import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'routes.dart';

class Root extends StatefulNavigator<RR> {
  const Root({this.inner = false});
  final bool inner;

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
      child: Scaffold(
        body: navigator.inner
            // a nested tree without URLs, linking out to the router's routes
            ? const DeclarativeNavigator(navigator: Inner())
            : const Text('A'),
      ),
    ),
    if (shown is RB)
      NavPage(
        route: const RB(),
        onPop: () => setState(() => shown = const RA()),
        child: scaffold('B'),
      ),
  ];
}

class Inner extends StatelessNavigator<Never> {
  const Inner();

  @override
  List<NavEntry<Never>> build() => [
    NavPage(
      child: RouteLink(
        route: const RB(),
        builder: (context, open) =>
            TextButton(onPressed: open, child: const Text('to B')),
      ),
    ),
  ];
}

// a bloc-like store: synchronous state, asynchronous stream
class Store {
  final _controller = StreamController<bool>.broadcast();
  bool detail = true;

  Stream<bool> get stream => _controller.stream;

  void back() {
    detail = false;
    _controller.add(detail);
  }
}

class StoreNavigator extends StatefulNavigator<Never> {
  const StoreNavigator(this.store);
  final Store store;

  @override
  StoreNavigatorState createState() => StoreNavigatorState();
}

class StoreNavigatorState
    extends StatefulNavigatorState<StoreNavigator, Never> {
  @override
  void initState() {
    super.initState();
    listen(navigator.store.stream);
  }

  @override
  List<NavEntry<Never>> build() => [
    const NavPage(child: Text('list')),
    if (navigator.store.detail)
      NavPage(
        onPop: navigator.store.back,
        child: Scaffold(appBar: AppBar(title: const Text('detail'))),
      ),
  ];
}

void main() {
  testWidgets('a route opened before the first frame wins over "/"', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final router = FdrRouter<RR>(root: const Root(), fromUrl: RR.fromUrl);
    // e.g. the notification that launched the app, handled in main()
    router.open(const RB());
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/b');
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('a DeclarativeNavigator in a page links to the router', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final router = FdrRouter<RR>(
      root: const Root(inner: true),
      fromUrl: RR.fromUrl,
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
    await tester.pump();
    await tester.tap(find.text('to B'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(router.currentUrl, '/b');
  });

  testWidgets('onPop may update a store that rebuilds asynchronously', (
    tester,
  ) async {
    final store = Store();
    await tester.pumpWidget(
      MaterialApp(home: DeclarativeNavigator(navigator: StoreNavigator(store))),
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
    // the page is gone once the stream delivered: no misuse is reported
    expect(tester.takeException(), isNull);
  });
}
