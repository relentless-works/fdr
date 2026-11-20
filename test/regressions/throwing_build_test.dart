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
  static final all = <CounterState>[];
  int count = 0;

  @override
  void initState() {
    super.initState();
    created++;
    all.add(this);
  }

  @override
  List<NavEntry<Never>> build() => [NavPage(child: Text('count $count'))];
}

class Thrower extends StatefulNavigator<Never> {
  const Thrower(this.fail);
  final bool fail;
  @override
  ThrowerState createState() => ThrowerState();
}

class ThrowerState extends StatefulNavigatorState<Thrower, Never> {
  static int created = 0;
  static final all = <ThrowerState>[];
  int count = 0;

  @override
  void initState() {
    super.initState();
    created++;
    all.add(this);
  }

  @override
  List<NavEntry<Never>> build() {
    if (navigator.fail) throw StateError('boom');
    return [NavPage(child: Text('thrower $count'))];
  }
}

class Root extends StatefulNavigator<Never> {
  const Root(this.entries);
  final List<NavEntry<Never>> Function(int step) entries;
  @override
  RootState createState() => RootState();
}

class RootState extends StatefulNavigatorState<Root, Never> {
  static late RootState instance;
  int step = 0;
  @override
  void initState() {
    super.initState();
    instance = this;
  }

  @override
  List<NavEntry<Never>> build() => navigator.entries(step);
}

// a child whose initState asks the parent to rebuild
class Poker extends StatefulNavigator<Never> {
  const Poker(this.poke);
  final VoidCallback poke;
  @override
  PokerState createState() => PokerState();
}

class PokerState extends StatefulNavigatorState<Poker, Never> {
  @override
  void initState() {
    super.initState();
    navigator.poke();
  }

  @override
  List<NavEntry<Never>> build() => [const NavPage(child: Text('poker'))];
}

class Root2 extends StatefulNavigator<Never> {
  const Root2();
  @override
  Root2State createState() => Root2State();
}

class Root2State extends StatefulNavigatorState<Root2, Never> {
  static late Root2State instance;
  int step = 0;
  String label = 'a';
  @override
  void initState() {
    super.initState();
    instance = this;
  }

  @override
  List<NavEntry<Never>> build() => [
    NavPage(child: Text('label $label')),
    if (step == 1) ...[
      Poker(() => setState(() => label = 'stale')),
      const Thrower(true),
    ],
  ];
}

Future<RootState> pumpRoot(
  WidgetTester tester,
  List<NavEntry<Never>> Function(int step) entries,
) async {
  await tester.pumpWidget(
    MaterialApp(home: DeclarativeNavigator(navigator: Root(entries))),
  );
  return RootState.instance;
}

void failingStep(RootState root, int step) {
  Object? thrown;
  try {
    root.setState(() => root.step = step);
  } catch (e) {
    thrown = e;
  }
  expect(thrown, isStateError);
}

// counted from the states of this test: the previous test's tree is only
// disposed after setUp
int get liveCounters => CounterState.all.where((s) => s.mounted).length;
int get liveThrowers => ThrowerState.all.where((s) => s.mounted).length;

void main() {
  setUp(() {
    CounterState.created = 0;
    CounterState.all.clear();
    ThrowerState.created = 0;
    ThrowerState.all.clear();
  });

  testWidgets('a sibling whose build throws does not orphan visited states', (
    tester,
  ) async {
    final root = await pumpRoot(
      tester,
      (step) => [const Counter(), Thrower(step == 1)],
    );
    final first = CounterState.all.single;
    final thrower = ThrowerState.all.single;
    first.setState(() => first.count = 5);
    await tester.pump();
    expect(find.text('count 5', skipOffstage: false), findsOneWidget);

    failingStep(root, 1);
    await tester.pump();
    expect(first.mounted, isTrue);
    expect(thrower.mounted, isTrue);
    expect(find.text('count 5', skipOffstage: false), findsOneWidget);

    // both children still reach the parent after the failed pass
    first.setState(() => first.count = 6);
    await tester.pump();
    expect(find.text('count 6', skipOffstage: false), findsOneWidget);

    root.setState(() => root.step = 2);
    await tester.pump();
    expect(liveCounters, 1);
    expect(liveThrowers, 1);
    expect(CounterState.all.single, same(first));
    expect(ThrowerState.all.single, same(thrower));
    expect(find.text('count 6', skipOffstage: false), findsOneWidget);
    expect(find.text('thrower 0'), findsOneWidget);

    thrower.setState(() => thrower.count = 1);
    await tester.pump();
    expect(find.text('thrower 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('states created in a pass that throws are disposed', (
    tester,
  ) async {
    final root = await pumpRoot(
      tester,
      (step) => [
        const NavPage(child: Text('home')),
        if (step >= 1) ...[const Counter(), Thrower(step == 1)],
      ],
    );
    failingStep(root, 1);
    await tester.pump();
    // the new sibling before the thrower, and the thrower itself
    expect((CounterState.created, liveCounters), (1, 0));
    expect((ThrowerState.created, liveThrowers), (1, 0));
    expect(CounterState.all.single.mounted, isFalse);
    expect(find.text('home'), findsOneWidget);

    root.setState(() => root.step = 2);
    await tester.pump();
    expect(liveCounters, 1);
    expect(liveThrowers, 1);
    expect(find.text('thrower 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pass that throws keeps the states it would have removed', (
    tester,
  ) async {
    final root = await pumpRoot(
      tester,
      (step) => [
        const NavPage(child: Text('home')),
        if (step != 1) const Counter(key: ValueKey('a')),
        Thrower(step == 1),
      ],
    );
    final counter = CounterState.all.single;
    final thrower = ThrowerState.all.single;
    counter.setState(() => counter.count = 3);

    // the thrower moves into the counter's slot, and the counter would go
    failingStep(root, 1);
    expect(counter.mounted, isTrue);
    expect(thrower.mounted, isTrue);

    root.setState(() => root.step = 2);
    await tester.pump();
    expect((CounterState.created, liveCounters), (1, 1));
    // unkeyed, so the one in the counter's slot was a new one
    expect((ThrowerState.created, liveThrowers), (2, 1));
    expect(thrower.mounted, isTrue);
    expect(find.text('count 3', skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('two navigators with one key do not share a state', (
    tester,
  ) async {
    final root = await pumpRoot(
      tester,
      (step) => const [
        Counter(key: ValueKey('a')),
        Counter(key: ValueKey('a')),
      ],
    );
    expect(liveCounters, 2);
    root.setState(() => root.step = 1);
    await tester.pump();
    expect((CounterState.created, liveCounters), (2, 2));
  });

  testWidgets('a rebuild queued in a pass that throws is dropped', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: DeclarativeNavigator(navigator: Root2())),
    );
    final root = Root2State.instance;
    Object? thrown;
    try {
      root.setState(() => root.step = 1);
    } catch (e) {
      thrown = e;
    }
    expect(thrown, isStateError);
    // the entry list queued by Poker during the failed pass (step 1, with
    // the Thrower) must not be reconciled after this newer one
    root.setState(() {
      root.step = 2;
      root.label = 'fresh';
    });
    await tester.pump();
    expect(find.text('label fresh'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tab whose navigator throws keeps the other tabs', (
    tester,
  ) async {
    final root = await pumpRoot(
      tester,
      (step) => [
        TabsPage(
          index: 0,
          tabs: [
            const Counter(),
            Thrower(step == 1),
            if (step >= 1) const NavPage(child: Text('third')),
          ],
          builder: (context, tabs) =>
              Scaffold(body: IndexedStack(children: tabs)),
        ),
      ],
    );
    final first = CounterState.all.single;
    final thrower = ThrowerState.all.single;
    first.setState(() => first.count = 5);
    await tester.pump();
    expect(find.text('count 5'), findsOneWidget);

    failingStep(root, 1);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(first.mounted, isTrue);
    expect(find.text('count 5'), findsOneWidget);

    first.setState(() => first.count = 6);
    await tester.pump();
    expect(find.text('count 6'), findsOneWidget);

    root.setState(() => root.step = 2);
    await tester.pump();
    expect((CounterState.created, liveCounters), (1, 1));
    expect((ThrowerState.created, liveThrowers), (1, 1));
    expect(ThrowerState.all.single, same(thrower));
    expect(find.text('count 6'), findsOneWidget);
    expect(find.text('third', skipOffstage: false), findsOneWidget);

    thrower.setState(() => thrower.count = 1);
    await tester.pump();
    expect(find.text('thrower 1', skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new tabs whose first build throws are disposed', (tester) async {
    final root = await pumpRoot(
      tester,
      (step) => [
        const NavPage(child: Text('home')),
        if (step >= 1)
          TabsPage(
            index: 0,
            tabs: [const Counter(), Thrower(step == 1)],
            builder: (context, tabs) =>
                Scaffold(body: IndexedStack(children: tabs)),
          ),
      ],
    );
    failingStep(root, 1);
    await tester.pump();
    expect((CounterState.created, liveCounters), (1, 0));
    expect((ThrowerState.created, liveThrowers), (1, 0));
    expect(find.text('home'), findsOneWidget);

    root.setState(() => root.step = 2);
    await tester.pump();
    expect(liveCounters, 1);
    expect(liveThrowers, 1);
    expect(find.text('count 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
