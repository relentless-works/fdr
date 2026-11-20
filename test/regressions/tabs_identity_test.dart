import 'package:fdr/fdr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class Counter extends StatefulNavigator<Never> {
  const Counter({super.key});
  @override
  CounterState createState() => CounterState();
}

class CounterState extends StatefulNavigatorState<Counter, Never> {
  static int created = 0;
  static int disposed = 0;
  static late CounterState latest;
  int count = 0;

  @override
  void initState() {
    super.initState();
    created++;
    latest = this;
  }

  @override
  void dispose() {
    disposed++;
    super.dispose();
  }

  @override
  List<NavEntry<Never>> build() => [NavPage(child: Text('count $count'))];
}

class Root extends StatefulNavigator<Never> {
  const Root({this.tabsKey});
  final LocalKey? tabsKey;
  @override
  RootState createState() => RootState();
}

class RootState extends StatefulNavigatorState<Root, Never> {
  static late RootState latest;
  bool banner = false;
  LocalKey? keyOverride;

  @override
  void initState() {
    super.initState();
    latest = this;
  }

  @override
  List<NavEntry<Never>> build() => [
    const NavPage(child: Text('home')),
    if (banner) const NavPage(child: Text('banner')),
    TabsPage(
      key: keyOverride ?? navigator.tabsKey,
      index: 1,
      tabs: const [
        NavPage(child: Text('t0')),
        NestedNavigator(child: Counter()),
      ],
      builder: (context, tabs) =>
          Scaffold(body: IndexedStack(index: 1, children: tabs)),
    ),
  ];
}

Future<void> pumpCounted(WidgetTester tester, Root root) async {
  CounterState.created = 0;
  CounterState.disposed = 0;
  await tester.pumpWidget(
    MaterialApp(home: DeclarativeNavigator(navigator: root)),
  );
  await tester.pumpAndSettle();
  final counter = CounterState.latest;
  counter.setState(() => counter.count = 7);
  await tester.pumpAndSettle();
  expect(find.text('count 7'), findsOneWidget);
}

Future<void> movesWithItsTabs(WidgetTester tester, Root root) async {
  await pumpCounted(tester, root);
  final state = RootState.latest;
  state.setState(() => state.banner = true);
  await tester.pumpAndSettle();
  expect(CounterState.created, 1);
  expect(CounterState.disposed, 0);
  expect(find.text('count 7', skipOffstage: false), findsOneWidget);

  state.setState(() => state.banner = false);
  await tester.pumpAndSettle();
  expect(CounterState.created, 1);
  expect(CounterState.disposed, 0);
  expect(find.text('count 7'), findsOneWidget);
}

void main() {
  testWidgets(
    'a keyed TabsPage keeps its tabs when a page goes in below',
    (tester) => movesWithItsTabs(tester, const Root(tabsKey: ValueKey('tabs'))),
  );

  // its page key is the same, so the tabs stay the same too
  testWidgets(
    'an unkeyed TabsPage keeps its tabs when a page goes in below',
    (tester) => movesWithItsTabs(tester, const Root()),
  );

  testWidgets('a TabsPage with another key gets new tabs', (tester) async {
    await pumpCounted(tester, const Root(tabsKey: ValueKey('a')));
    final state = RootState.latest;
    state.setState(() => state.keyOverride = const ValueKey('b'));
    await tester.pumpAndSettle();
    expect(CounterState.created, 2);
    expect(CounterState.disposed, 1);
    expect(find.text('count 0'), findsOneWidget);
  });
}
