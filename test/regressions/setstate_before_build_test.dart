import 'package:fdr/fdr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

final log = <String>[];

class _Store extends ChangeNotifier {
  void reset() => notifyListeners();
}

// where the navigator calls setState
enum In { initState, initStateWatch, didUpdateNavigator, applyRoute }

class _Root extends StatefulNavigator<String> {
  const _Root(this.where);
  final In where;
  @override
  _RootState createState() => _RootState();
}

class _RootState extends StatefulNavigatorState<_Root, String> {
  static late _RootState latest;
  String order = 'order-42';

  @override
  void initState() {
    super.initState();
    latest = this;
  }

  @override
  void applyRoute(String route) => order = route;

  @override
  List<NavEntry<String>> build() => [
    const NavPage(child: Text('root')),
    NestedNavigator<String, String>(
      route: order,
      child: _Mid(where: navigator.where, order: order),
    ),
  ];
}

class _Mid extends StatefulNavigator<String> {
  const _Mid({required this.where, required this.order});
  final In where;
  final String order;
  @override
  _MidState createState() => _MidState();
}

class _MidState extends StatefulNavigatorState<_Mid, String> {
  String id = 'default';
  int changes = 0;
  final store = _Store();

  @override
  void initState() {
    super.initState();
    log.add('mid.initState');
    switch (navigator.where) {
      case In.initState:
        setState(() => changes++);
      case In.initStateWatch:
        watch(store);
        store.reset(); // notifies synchronously
      case In.didUpdateNavigator || In.applyRoute:
    }
  }

  @override
  void didUpdateNavigator(_Mid oldNavigator) {
    super.didUpdateNavigator(oldNavigator);
    if (oldNavigator.order == navigator.order) return;
    log.add('mid.didUpdateNavigator');
    if (navigator.where == In.didUpdateNavigator) setState(() => changes++);
  }

  @override
  void applyRoute(String route) {
    log.add('mid.applyRoute($route)');
    if (navigator.where == In.applyRoute) setState(() => changes++);
    id = route;
  }

  @override
  List<NavEntry<String>> build() {
    log.add('mid.build($id)');
    return [_Leaf(id: id, changes: changes)];
  }
}

class _Leaf extends StatefulNavigator<Never> {
  const _Leaf({required this.id, required this.changes});
  final String id;
  final int changes;
  @override
  _LeafState createState() => _LeafState();
}

class _LeafState extends StatefulNavigatorState<_Leaf, Never> {
  @override
  void initState() {
    super.initState();
    // stands for a side effect, e.g. FutureNavigator starting its load
    log.add('leaf.initState(${navigator.id})');
  }

  @override
  List<NavEntry<Never>> build() => [
    NavPage(child: Text('leaf ${navigator.id} ${navigator.changes}')),
  ];
}

void main() {
  setUp(log.clear);

  Future<void> pumpRoot(WidgetTester tester, In where) => tester.pumpWidget(
    MaterialApp(home: DeclarativeNavigator(navigator: _Root(where))),
  );

  for (final where in [In.initState, In.initStateWatch, In.applyRoute]) {
    testWidgets('initState, applyRoute, build: no build before applyRoute '
        '(setState in ${where.name})', (tester) async {
      await pumpRoot(tester, where);
      final changes = where == In.initStateWatch ? 0 : 1;
      expect(find.text('leaf order-42 $changes'), findsOneWidget);
      expect(log, [
        'mid.initState',
        'mid.applyRoute(order-42)',
        'mid.build(order-42)',
        'leaf.initState(order-42)',
      ]);
    });
  }

  for (final where in [In.didUpdateNavigator, In.applyRoute]) {
    testWidgets('didUpdateNavigator, applyRoute, build: one build '
        '(setState in ${where.name})', (tester) async {
      await pumpRoot(tester, where);
      log.clear();
      // an incoming route for the existing child
      final root = _RootState.latest;
      root.open('order-7');
      await tester.pump();
      expect(log, [
        'mid.didUpdateNavigator',
        'mid.applyRoute(order-7)',
        'mid.build(order-7)',
      ]);
      final changes = where == In.didUpdateNavigator ? 1 : 2;
      expect(find.text('leaf order-7 $changes'), findsOneWidget);
    });
  }

  testWidgets('setState after a setState in initState still rebuilds', (
    tester,
  ) async {
    await pumpRoot(tester, In.initStateWatch);
    final root = _RootState.latest;
    log.clear();
    root.setState(() => root.order = 'order-9');
    await tester.pump();
    // no incoming route: the child keeps its state, but was rebuilt
    expect(log, ['mid.didUpdateNavigator', 'mid.build(order-42)']);
  });
}
