import 'dart:async';

import 'package:fdr/fdr.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// History state is restored right after the route is applied. Below a
// FutureNavigator that is loading, the navigators it was written for do not
// exist yet: they get it when they are created, and the entry keeps it
// until then.

sealed class R extends NavRoute {
  const R();
  static R fromUrl(Url url) => switch (url.segments) {
    [] => const Home(),
    ['detail'] => const Detail(),
    _ => throw NotFound(url),
  };

  @override
  Url toUrl() => switch (this) {
    Home() => const Url([]),
    Detail() => const Url(['detail']),
  };
}

final class Home extends R {
  const Home();
}

final class Detail extends R {
  const Detail();
}

// what the loaded child shows below its own page
enum Below { nothing, loaded, tabs }

var detailLoad = Completer<String>();
var grandLoad = Completer<String>();

class GrandChild extends StatefulNavigator<Never> {
  const GrandChild();
  @override
  GrandChildState createState() => GrandChildState();
}

class GrandChildState extends StatefulNavigatorState<GrandChild, Never> {
  static GrandChildState? latest;
  int count = 0;

  @override
  void initState() {
    super.initState();
    latest = this;
  }

  @override
  Object? get historyState => count == 0 ? null : {'count': count};

  @override
  void restoreHistoryState(Object? state) {
    count = state is Map ? state['count'] as int : 0;
  }

  @override
  String get restorationType => 'GrandChild';

  @override
  List<NavEntry<Never>> build() => [NavPage(child: Text('count $count'))];
}

class Child extends StatefulNavigator<R> {
  const Child(this.below);
  final Below below;
  @override
  ChildState createState() => ChildState();
}

class ChildState extends StatefulNavigatorState<Child, R> {
  static ChildState? latest;
  int scroll = 0;
  // what the first build saw
  int? builtWith;

  @override
  void initState() {
    super.initState();
    latest = this;
  }

  @override
  void applyRoute(R route) {}

  @override
  Object? get historyState => scroll == 0 ? null : {'scroll': scroll};

  @override
  void restoreHistoryState(Object? state) {
    if (state is Map) scroll = state['scroll'] as int;
  }

  @override
  String get restorationType => 'Child';

  @override
  List<NavEntry<R>> build() {
    builtWith ??= scroll;
    return [
      NavPage(route: const Detail(), child: Text('scroll $scroll')),
      if (navigator.below == Below.loaded)
        FutureNavigator<String, Never>(
          key: const ValueKey('g'),
          load: () => grandLoad.future,
          loading: const Text('loading g'),
          error: (e, retry) => Text('$e'),
          builder: (data, reload) => const GrandChild(),
        ),
      if (navigator.below == Below.tabs)
        TabsPage(
          index: 0,
          tabs: const [GrandChild()],
          builder: (context, tabs) => tabs.single,
        ),
    ];
  }
}

class Root extends StatefulNavigator<R> {
  const Root({this.initialData, this.below = Below.nothing});
  final String? initialData;
  final Below below;
  @override
  RootState createState() => RootState();
}

class RootState extends StatefulNavigatorState<Root, R> {
  R? childRoute;

  @override
  void applyRoute(R route) => childRoute = route is Detail ? route : null;

  @override
  String get restorationType => 'Root';

  @override
  List<NavEntry<R>> build() => [
    const NavPage(route: Home(), child: Text('home')),
    if (childRoute != null)
      NestedNavigator<R, R>(
        route: childRoute,
        onPop: () => setState(() => childRoute = null),
        child: FutureNavigator<String, R>(
          key: const ValueKey('d'),
          load: () => detailLoad.future,
          initialData: navigator.initialData,
          loading: const Text('loading'),
          error: (e, retry) => Text('$e'),
          builder: (data, reload) => Child(navigator.below),
        ),
      ),
  ];
}

// the browser entry after a reload
class ReloadedEntry implements BrowserHistory {
  ReloadedEntry(this.currentState);

  @override
  final Object? currentState;

  @override
  bool get supportsTraversal => true;

  @override
  void go(int delta) {}
}

FdrRouter<R> router(Root root) {
  final router = FdrRouter<R>(root: root, fromUrl: R.fromUrl);
  addTearDown(router.dispose);
  return router;
}

Object? historyState(FdrRouter<R> router) =>
    router.delegate.currentConfiguration!.historyState;

// the history state of /detail with scroll 7 (and count 3 below it)
Future<Object?> save(WidgetTester tester, {Below below = Below.nothing}) async {
  grandLoad = Completer<String>()..complete('g');
  final saving = router(Root(initialData: 'x', below: below));
  await saving.delegate.setNewRoutePath(const RouteSnapshot(Detail()));
  await tester.pump();
  ChildState.latest!.setState(() => ChildState.latest!.scroll = 7);
  if (below != Below.nothing) {
    GrandChildState.latest!.setState(() => GrandChildState.latest!.count = 3);
  }
  final saved = historyState(saving);
  expect(saved, isNotNull);
  ChildState.latest = null;
  GrandChildState.latest = null;
  return saved;
}

Future<FdrRouter<R>> restore(Object? saved, {Below below = Below.nothing}) {
  detailLoad = Completer<String>();
  grandLoad = Completer<String>();
  final restoring = router(Root(below: below));
  return restoring.delegate
      .setNewRoutePath(RouteSnapshot(const Detail(), historyState: saved))
      .then((_) => restoring);
}

void main() {
  testWidgets('state below an already loaded FutureNavigator is restored', (
    tester,
  ) async {
    final saved = await save(tester);
    final restoring = router(const Root(initialData: 'x'));
    await restoring.delegate.setNewRoutePath(
      RouteSnapshot(const Detail(), historyState: saved),
    );
    expect(ChildState.latest!.scroll, 7);
    expect(historyState(restoring), saved);
  });

  testWidgets('state below a loading FutureNavigator survives the load', (
    tester,
  ) async {
    final saved = await save(tester);
    final restoring = await restore(saved);
    expect(ChildState.latest, isNull);
    expect(historyState(restoring), saved, reason: 'the entry keeps it');

    detailLoad.complete('x');
    await tester.pump();
    expect(ChildState.latest!.scroll, 7);
    expect(ChildState.latest!.builtWith, 7, reason: 'before the first build');
    expect(historyState(restoring), saved);
  });

  testWidgets('state two loaded levels down survives both loads', (
    tester,
  ) async {
    final saved = await save(tester, below: Below.loaded);
    final restoring = await restore(saved, below: Below.loaded);
    expect(historyState(restoring), saved);

    detailLoad.complete('x');
    await tester.pump();
    expect(ChildState.latest!.scroll, 7);
    expect(GrandChildState.latest, isNull);
    expect(historyState(restoring), saved);

    grandLoad.complete('g');
    await tester.pump();
    expect(GrandChildState.latest!.count, 3);
    expect(historyState(restoring), saved);
  });

  testWidgets('state of tabs below a loading FutureNavigator survives the '
      'load', (tester) async {
    final saved = await save(tester, below: Below.tabs);
    final restoring = await restore(saved, below: Below.tabs);
    expect(historyState(restoring), saved);

    detailLoad.complete('x');
    await tester.pump();
    expect(ChildState.latest!.scroll, 7);
    expect(GrandChildState.latest!.count, 3);
    expect(historyState(restoring), saved);
  });

  testWidgets('the browser entry keeps the state while the child loads', (
    tester,
  ) async {
    final sent = <Map<Object?, Object?>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.navigation,
      (call) async {
        if (call.method == 'routeInformationUpdated') {
          sent.add(call.arguments as Map);
        }
        return null;
      },
    );
    // what the browser holds for the current entry: the last report
    Map<Object?, Object?> stored() =>
        sent.last['state']! as Map<Object?, Object?>;

    Future<void> start(BrowserHistory history) async {
      final app = FdrRouter<R>(
        root: const Root(),
        fromUrl: R.fromUrl,
        initialRouteInformation: RouteInformation(uri: Uri.parse('/detail')),
        browserHistory: history,
        sessionId: 1,
      );
      addTearDown(app.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: app.config));
      await tester.pumpAndSettle();
    }

    detailLoad = Completer<String>()..complete('x');
    await start(const NoBrowserHistory());
    ChildState.latest!.setState(() => ChildState.latest!.scroll = 7);
    await tester.pumpAndSettle();
    final entry = stored();
    expect(entry['h'], isNotNull);

    // reload: the engine passes only the path, the entry still has its state
    await tester.pumpWidget(const SizedBox());
    ChildState.latest = null;
    detailLoad = Completer<String>();
    await start(ReloadedEntry(entry));
    expect(find.text('loading'), findsOneWidget);
    expect(stored()['h'], entry['h'], reason: 'overwritten while loading');

    detailLoad.complete('x');
    await tester.pumpAndSettle();
    expect(find.text('scroll 7'), findsOneWidget);
    expect(stored()['h'], entry['h']);
  });

  testWidgets('a navigator opened after the restore does not get state of '
      'the restored entry', (tester) async {
    final saved = await save(tester);
    // an entry whose tree does not fit what its URL shows (e.g. written by
    // an earlier build of the app): the detail is not there to restore
    detailLoad = Completer<String>();
    final restoring = router(const Root());
    await restoring.delegate.setNewRoutePath(
      RouteSnapshot(const Home(), historyState: saved),
    );
    expect(ChildState.latest, isNull);

    restoring.open(const Detail());
    detailLoad.complete('x');
    await tester.pump();
    expect(ChildState.latest!.scroll, 0);
    expect(historyState(restoring), isNull);
  });
}
