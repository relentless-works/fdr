import 'package:fdr/fdr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

final session = ValueNotifier(true);
final log = <String>[];

// what the leaf does in initState, e.g. a session check that logs out
enum Act { rootSetState, logout, siblingSetState, rootSetStateThenThrow }

class Leaf extends StatefulNavigator<Never> {
  const Leaf(this.act);
  final Act act;
  @override
  LeafState createState() => LeafState();
}

class LeafState extends StatefulNavigatorState<Leaf, Never> {
  static final all = <LeafState>[];
  @override
  void initState() {
    super.initState();
    all.add(this);
    final root = RootState.latest;
    switch (navigator.act) {
      case Act.rootSetState || Act.rootSetStateThenThrow:
        root.setState(() => root.showMid = false);
      case Act.logout:
        session.value = false;
      case Act.siblingSetState:
        final side = SideState.latest;
        side.setState(() => side.label = 'poked');
    }
    log.add('leaf.initState done');
  }

  @override
  void dispose() {
    log.add('leaf.dispose');
    super.dispose();
  }

  @override
  List<NavEntry<Never>> build() {
    log.add('leaf.build');
    if (navigator.act == Act.rootSetStateThenThrow) throw StateError('boom');
    return [const NavPage(child: Text('leaf'))];
  }
}

class Mid extends StatefulNavigator<Never> {
  const Mid();
  @override
  MidState createState() => MidState();
}

class MidState extends StatefulNavigatorState<Mid, Never> {
  static late MidState latest;
  Act? leaf;
  @override
  void initState() {
    super.initState();
    latest = this;
  }

  @override
  void dispose() {
    log.add('mid.dispose');
    super.dispose();
  }

  @override
  List<NavEntry<Never>> build() => [
    const NavPage(child: Text('mid')),
    if (leaf case final act?) Leaf(act),
  ];
}

class Side extends StatefulNavigator<Never> {
  const Side();
  @override
  SideState createState() => SideState();
}

class SideState extends StatefulNavigatorState<Side, Never> {
  static late SideState latest;
  String label = 'side';
  @override
  void initState() {
    super.initState();
    latest = this;
  }

  @override
  List<NavEntry<Never>> build() {
    log.add('side.build($label)');
    return [NavPage(child: Text(label))];
  }
}

class Root extends StatefulNavigator<Never> {
  const Root();
  @override
  RootState createState() => RootState();
}

class RootState extends StatefulNavigatorState<Root, Never> {
  static late RootState latest;
  bool showMid = true;
  @override
  void initState() {
    super.initState();
    latest = this;
    watch(session);
  }

  @override
  List<NavEntry<Never>> build() => [
    const NavPage(child: Text('home')),
    const Side(),
    if (showMid && session.value) const Mid(),
  ];
}

void main() {
  setUp(() {
    session.value = true;
    LeafState.all.clear();
  });

  Future<void> pumpRoot(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DeclarativeNavigator(navigator: Root())),
    );
    await tester.pumpAndSettle();
    expect(find.text('mid'), findsOneWidget);
    log.clear();
  }

  for (final act in [Act.rootSetState, Act.logout]) {
    testWidgets('a child removes the navigator whose pass creates it '
        '(${act.name})', (tester) async {
      await pumpRoot(tester);
      final mid = MidState.latest;
      // the pass starts at Mid, below the root
      mid.setState(() => mid.leaf = act);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Mid finished its pass before the root removed it
      expect(log, [
        'leaf.initState done',
        'leaf.build',
        'side.build(side)',
        'mid.dispose',
        'leaf.dispose',
      ]);
      expect(mid.mounted, isFalse);
      expect(LeafState.all.single.mounted, isFalse);
      expect(find.text('home', skipOffstage: false), findsOneWidget);
      expect(find.text('mid'), findsNothing);
      expect(find.text('leaf'), findsNothing);
    });
  }

  testWidgets('setState on another navigator during a pass runs after it', (
    tester,
  ) async {
    await pumpRoot(tester);
    final mid = MidState.latest;
    mid.setState(() => mid.leaf = Act.siblingSetState);
    expect(log, ['leaf.initState done', 'leaf.build', 'side.build(poked)']);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('poked', skipOffstage: false), findsOneWidget);
    expect(find.text('leaf'), findsOneWidget);
  });

  testWidgets('a rebuild deferred by a pass that throws still runs', (
    tester,
  ) async {
    await pumpRoot(tester);
    final mid = MidState.latest;
    Object? thrown;
    try {
      mid.setState(() => mid.leaf = Act.rootSetStateThenThrow);
    } catch (e) {
      thrown = e;
    }
    expect(thrown, isStateError);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(mid.mounted, isFalse);
    expect(LeafState.all.single.mounted, isFalse);
    expect(find.text('mid'), findsNothing);
  });
}
