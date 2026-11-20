import 'package:fdr/fdr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

final session = ValueNotifier(true);
final log = <String>[];

// what Mid does in the build its own setState starts
enum Act { rootSetState, logout, selfSetState }

class Leaf extends StatefulNavigator<Never> {
  const Leaf();
  @override
  LeafState createState() => LeafState();
}

class LeafState extends StatefulNavigatorState<Leaf, Never> {
  static final all = <LeafState>[];
  @override
  void initState() {
    super.initState();
    all.add(this);
    log.add('leaf.initState, mid mounted: ${MidState.latest.mounted}');
  }

  @override
  void dispose() {
    log.add('leaf.dispose');
    super.dispose();
  }

  @override
  List<NavEntry<Never>> build() => [const NavPage(child: Text('leaf'))];
}

class Mid extends StatefulNavigator<Never> {
  const Mid();
  @override
  MidState createState() => MidState();
}

class MidState extends StatefulNavigatorState<Mid, Never> {
  static late MidState latest;
  Act? act;
  bool leaf = false;
  int count = 0;

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
  List<NavEntry<Never>> build() {
    log.add('mid.build');
    final act = this.act;
    this.act = null;
    final root = RootState.latest;
    switch (act) {
      case Act.rootSetState:
        root.setState(() => root.showMid = false);
      case Act.logout:
        session.value = false;
      case Act.selfSetState:
        setState(() => count++);
      case null:
    }
    if (act != null) log.add('mid.build done, mounted: $mounted');
    return [NavPage(child: Text('mid $count')), if (leaf) const Leaf()];
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
    expect(find.text('mid 0'), findsOneWidget);
    log.clear();
  }

  for (final act in [Act.rootSetState, Act.logout]) {
    testWidgets('the build that starts an update removes its navigator '
        '(${act.name})', (tester) async {
      await pumpRoot(tester);
      final mid = MidState.latest;
      mid.setState(() {
        mid.act = act;
        mid.leaf = true;
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Mid finished its update before the root removed it
      expect(log, [
        'mid.build',
        'mid.build done, mounted: true',
        'leaf.initState, mid mounted: true',
        'mid.dispose',
        'leaf.dispose',
      ]);
      expect(mid.mounted, isFalse);
      expect(LeafState.all.single.mounted, isFalse);
      expect(find.text('home'), findsOneWidget);
      expect(find.text('leaf'), findsNothing);
    });
  }

  testWidgets('a setState on itself in the build that starts an update '
      'builds again after it', (tester) async {
    await pumpRoot(tester);
    final mid = MidState.latest;
    mid.setState(() => mid.act = Act.selfSetState);
    expect(log, ['mid.build', 'mid.build done, mounted: true', 'mid.build']);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('mid 1', skipOffstage: false), findsOneWidget);
  });
}
