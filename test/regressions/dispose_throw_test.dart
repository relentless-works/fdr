import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class Old extends StatefulNavigator<Never> {
  const Old();
  @override
  OldState createState() => OldState();
}

class OldState extends StatefulNavigatorState<Old, Never> {
  @override
  void dispose() {
    super.dispose();
    throw StateError('dispose boom');
  }

  @override
  List<NavEntry<Never>> build() => [const NavPage(child: Text('old'))];
}

class New extends StatefulNavigator<Never> {
  const New();
  @override
  NewState createState() => NewState();
}

class NewState extends StatefulNavigatorState<New, Never> {
  static final all = <NewState>[];

  @override
  void initState() {
    super.initState();
    all.add(this);
  }

  @override
  List<NavEntry<Never>> build() => [const NavPage(child: Text('new'))];
}

class Root extends StatefulNavigator<Never> {
  const Root();
  @override
  RootState createState() => RootState();
}

class RootState extends StatefulNavigatorState<Root, Never> {
  static late RootState latest;
  int step = 0;

  @override
  void initState() {
    super.initState();
    latest = this;
  }

  @override
  List<NavEntry<Never>> build() => [
    const NavPage(child: Text('home')),
    if (step == 0) const Old(),
    if (step == 1) const New(),
  ];
}

// a sibling of the navigator whose dispose throws, with a subscription
class Watcher extends StatefulNavigator<Never> {
  const Watcher(this.notifier);
  final ValueNotifier<int> notifier;
  @override
  WatcherState createState() => WatcherState();
}

class WatcherState extends StatefulNavigatorState<Watcher, Never> {
  static late WatcherState latest;
  static int builds = 0;

  @override
  void initState() {
    super.initState();
    latest = this;
    watch(navigator.notifier);
  }

  @override
  List<NavEntry<Never>> build() {
    builds++;
    return [const NavPage(child: Text('watcher'))];
  }
}

class Group extends StatefulNavigator<Never> {
  const Group(this.notifier, {this.tabs = false});
  final ValueNotifier<int> notifier;
  final bool tabs;
  @override
  GroupState createState() => GroupState();
}

class GroupState extends StatefulNavigatorState<Group, Never> {
  @override
  List<NavEntry<Never>> build() {
    final children = [const Old(), Watcher(navigator.notifier)];
    if (!navigator.tabs) return children;
    return [
      TabsPage(
        index: 1,
        tabs: children,
        builder: (context, tabs) => IndexedStack(index: 1, children: tabs),
      ),
    ];
  }
}

class Shell extends StatefulNavigator<Never> {
  const Shell(this.child);
  final StatefulNavigator<Never> child;
  @override
  ShellState createState() => ShellState();
}

class ShellState extends StatefulNavigatorState<Shell, Never> {
  static late ShellState latest;
  bool shown = true;

  @override
  void initState() {
    super.initState();
    latest = this;
  }

  @override
  List<NavEntry<Never>> build() => [
    const NavPage(child: Text('home')),
    if (shown) navigator.child,
  ];
}

class Vm {}

void main() {
  setUp(NewState.all.clear);

  testWidgets('a dispose that throws is reported, and the update that '
      'removed the navigator stands', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DeclarativeNavigator(navigator: Root())),
    );
    await tester.pumpAndSettle();
    expect(find.text('old'), findsOneWidget);

    final root = RootState.latest;
    root.setState(() => root.step = 1);
    expect(tester.takeException(), isStateError);
    await tester.pumpAndSettle();
    // the navigator created in that update is the one shown
    expect(find.text('old'), findsNothing);
    expect(find.text('new'), findsOneWidget);
    expect(NewState.all.single.mounted, isTrue);

    // and it is disposed when it goes
    root.setState(() => root.step = 2);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(NewState.all.single.mounted, isFalse);
    expect(find.text('home'), findsOneWidget);
  });

  for (final tabs in [false, true]) {
    testWidgets('a dispose that throws below a removed navigator leaves no '
        'sibling mounted (tabs: $tabs)', (tester) async {
      final notifier = ValueNotifier(0);
      addTearDown(notifier.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: DeclarativeNavigator(
            navigator: Shell(Group(notifier, tabs: tabs)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final watcher = WatcherState.latest;
      expect(find.text('watcher'), findsOneWidget);
      expect(watcher.mounted, isTrue);

      final shell = ShellState.latest;
      shell.setState(() => shell.shown = false);
      expect(tester.takeException(), isStateError);
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(watcher.mounted, isFalse);

      // and it no longer rebuilds on its watch
      final builds = WatcherState.builds;
      notifier.value++;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(WatcherState.builds, builds);
    });
  }

  testWidgets('a FutureNavigator whose child throws in dispose still '
      'releases its value', (tester) async {
    final vm = Vm();
    final released = <Vm>[];
    await tester.pumpWidget(
      MaterialApp(
        home: DeclarativeNavigator(
          navigator: Shell(
            FutureNavigator<Vm, Never>(
              key: const ValueKey(1),
              load: () async => vm,
              onDispose: released.add,
              loading: const Text('loading'),
              error: (e, retry) => Text('$e'),
              builder: (vm, reload) => const Old(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('old'), findsOneWidget);

    final shell = ShellState.latest;
    shell.setState(() => shell.shown = false);
    expect(tester.takeException(), isStateError);
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(released, [vm]);
  });
}
