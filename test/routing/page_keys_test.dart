import 'package:fdr/fdr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// A routed page is keyed by its printed path without the query: a query
// change updates the page in place, another path is a new page, and a
// repeated path gets `#n`. A page without a route belongs to the routed page
// below it (doc section 11).

sealed class KeyRoute extends NavRoute {
  const KeyRoute();

  static KeyRoute fromUrl(Url url) => switch (url.segments) {
    [] => ListRoute(url['sort'] ?? 'date'),
    [final int id] => ItemRoute(id),
    _ => throw NotFound(url),
  };

  @override
  Url toUrl() => switch (this) {
    ListRoute(:final sort) => Url(
      [],
      query: {
        if (sort != 'date') 'sort': [sort],
      },
    ),
    ItemRoute(:final id) => Url([id]),
  };
}

final class ListRoute extends KeyRoute {
  const ListRoute([this.sort = 'date']);
  final String sort;
}

final class ItemRoute extends KeyRoute {
  const ItemRoute(this.id);
  final int id;
}

class Pages extends StatefulNavigator<KeyRoute> {
  const Pages();
  @override
  PagesState createState() => PagesState();
}

class PagesState extends StatefulNavigatorState<Pages, KeyRoute> {
  static late PagesState latest;
  String sort = 'date';
  int? item;
  bool twice = false;
  bool help = false;

  @override
  void initState() {
    super.initState();
    latest = this;
  }

  @override
  void applyRoute(KeyRoute route) {
    switch (route) {
      case ListRoute(:final sort):
        this.sort = sort;
        item = null;
      case ItemRoute(:final id):
        item = id;
    }
  }

  @override
  List<NavEntry<KeyRoute>> build() => [
    NavPage(route: ListRoute(sort), child: Probe('list $sort')),
    if (item case final id?) ...[
      NavPage(
        route: ItemRoute(id),
        onPop: () => setState(() => item = null),
        child: Probe('item $id'),
      ),
      if (twice)
        NavPage(
          route: ItemRoute(id),
          onPop: () => setState(() => twice = false),
          child: Probe('again $id'),
        ),
    ],
    if (help)
      DialogPage(
        onPop: () => setState(() => help = false),
        child: const Probe('help'),
      ),
  ];
}

class Probe extends StatefulWidget {
  const Probe(this.label, {super.key});
  final String label;
  @override
  State<Probe> createState() => _ProbeState();
}

class _ProbeState extends State<Probe> {
  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: Text(widget.label)));
}

Future<FdrRouter<KeyRoute>> start(WidgetTester tester) async {
  final router = FdrRouter<KeyRoute>(
    root: const Pages(),
    fromUrl: KeyRoute.fromUrl,
    initialRouteInformation: RouteInformation(uri: Uri.parse('/')),
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
  await tester.pumpAndSettle();
  return router;
}

List<Key?> pageKeys(WidgetTester tester) => [
  for (final page
      in tester.widget<Navigator>(find.bySubtype<Navigator>()).pages)
    page.key,
];

State probe(WidgetTester tester, String label) => tester.state(
  find.ancestor(of: find.text(label), matching: find.byType(Probe)),
);

ModalRoute<Object?> routeOf(WidgetTester tester, String label) =>
    ModalRoute.of(tester.element(find.text(label)))!;

void change(void Function(PagesState state) fn) {
  final state = PagesState.latest;
  state.setState(() => fn(state));
}

void main() {
  testWidgets('a query change updates the page in place', (tester) async {
    final router = await start(tester);
    final before = probe(tester, 'list date');
    final route = routeOf(tester, 'list date');
    expect(pageKeys(tester), [const ValueKey('fdr:/')]);

    change((s) => s.sort = 'name');
    await tester.pump();
    expect(router.currentUrl, '/?sort=name');
    expect(pageKeys(tester), [const ValueKey('fdr:/')]);
    expect(probe(tester, 'list name'), same(before));
    expect(routeOf(tester, 'list name'), same(route));
    expect(route.animation!.status, AnimationStatus.completed);
  });

  testWidgets('another path is a new page, with a transition', (tester) async {
    final router = await start(tester);
    change((s) => s.item = 1);
    await tester.pumpAndSettle();
    final first = probe(tester, 'item 1');
    final firstRoute = routeOf(tester, 'item 1');

    change((s) => s.item = 2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(router.currentUrl, '/2');
    expect(pageKeys(tester), [
      const ValueKey('fdr:/'),
      const ValueKey('fdr:/2'),
    ]);
    final second = routeOf(tester, 'item 2');
    expect(second, isNot(same(firstRoute)));
    expect(second.animation!.status, AnimationStatus.forward);

    await tester.pumpAndSettle();
    expect(find.text('item 1'), findsNothing);
    expect(probe(tester, 'item 2'), isNot(same(first)));
  });

  testWidgets('a repeated path gets a key of its own', (tester) async {
    final router = await start(tester);
    change((s) {
      s.item = 1;
      s.twice = true;
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(pageKeys(tester), [
      const ValueKey('fdr:/'),
      const ValueKey('fdr:/1'),
      const ValueKey('fdr:/1#1'),
    ]);
    expect(find.text('again 1'), findsOneWidget);
    expect(router.currentUrl, '/1');

    // back pops the repeat, through its own onPop
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('again 1'), findsNothing);
    expect(find.text('item 1'), findsOneWidget);
    expect(PagesState.latest.item, 1);
    expect(pageKeys(tester), [
      const ValueKey('fdr:/'),
      const ValueKey('fdr:/1'),
    ]);
  });

  testWidgets('a page without a route stays while the query below changes', (
    tester,
  ) async {
    final router = await start(tester);
    change((s) => s.help = true);
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/');
    final keys = pageKeys(tester);
    expect(keys.first, const ValueKey('fdr:/'));
    // readable in an error message
    expect('${keys.last}', contains('DialogPage'));
    expect('${keys.last}', contains('fdr:/'));
    final help = probe(tester, 'help');
    final route = routeOf(tester, 'help');

    change((s) => s.sort = 'name');
    await tester.pump();
    expect(router.currentUrl, '/?sort=name');
    expect(pageKeys(tester), keys);
    expect(probe(tester, 'help'), same(help));
    expect(routeOf(tester, 'help'), same(route));
    expect(route.animation!.status, AnimationStatus.completed);
  });

  testWidgets('a page without a route is new above another routed page', (
    tester,
  ) async {
    final router = await start(tester);
    change((s) {
      s.item = 1;
      s.help = true;
    });
    await tester.pumpAndSettle();
    final keys = pageKeys(tester);
    final help = probe(tester, 'help');
    final route = routeOf(tester, 'help');

    change((s) => s.item = 2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(router.currentUrl, '/2');
    expect(pageKeys(tester).last, isNot(keys.last));
    expect(route.isActive, isFalse);
    await tester.pumpAndSettle();
    expect(routeOf(tester, 'help'), isNot(same(route)));
    expect(probe(tester, 'help'), isNot(same(help)));
  });

  testWidgets(
    'a routed page that comes in below a page without a route renews it',
    (tester) async {
      await start(tester);
      change((s) {
        s.item = 1;
        s.help = true;
      });
      await tester.pumpAndSettle();
      final keys = pageKeys(tester);
      final help = probe(tester, 'help');

      // the repeat of /1 comes in below the dialog, which is then above it
      change((s) => s.twice = true);
      await tester.pumpAndSettle();
      expect(pageKeys(tester).sublist(0, 2), keys.sublist(0, 2));
      expect(pageKeys(tester)[2], const ValueKey('fdr:/1#1'));
      expect(pageKeys(tester).toSet(), hasLength(4));
      expect(probe(tester, 'help'), isNot(same(help)));
      expect(tester.takeException(), isNull);
    },
  );
}
