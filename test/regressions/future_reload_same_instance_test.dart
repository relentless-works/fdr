import 'dart:async';

import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// A load that returns the instance already shown (a cached view model, a
// repository refreshing in place) must not release it while it is shown.

class Vm extends ChangeNotifier {
  int value = 0;
  void bump() {
    value++;
    notifyListeners();
  }
}

class OrderNav extends StatefulNavigator<Never> {
  const OrderNav(this.vm);
  final Vm vm;
  @override
  OrderNavState createState() => OrderNavState();
}

class OrderNavState extends StatefulNavigatorState<OrderNav, Never> {
  @override
  void initState() {
    super.initState();
    watch(navigator.vm);
  }

  @override
  List<NavEntry<Never>> build() => [
    NavPage(child: Text('order ${navigator.vm.value}')),
  ];
}

class Root extends StatefulNavigator<Never> {
  const Root(this.load, this.released, this.onReload);
  final Future<Vm> Function() load;
  final List<Vm> released;
  final void Function(Future<void> Function()) onReload;
  @override
  RootState createState() => RootState();
}

class RootState extends StatefulNavigatorState<Root, Never> {
  static late RootState latest;
  bool shown = true;

  @override
  void initState() {
    super.initState();
    latest = this;
  }

  @override
  List<NavEntry<Never>> build() => [
    const NavPage(child: Text('home')),
    if (shown)
      NestedNavigator(
        onPop: () => setState(() => shown = false),
        child: FutureNavigator<Vm, Never>(
          key: const ValueKey(1),
          load: navigator.load,
          onDispose: (vm) {
            navigator.released.add(vm);
            vm.dispose();
          },
          loading: const Text('loading'),
          error: (e, retry) => Text('$e'),
          builder: (vm, reload) {
            navigator.onReload(reload);
            return OrderNav(vm);
          },
        ),
      ),
  ];
}

void main() {
  testWidgets('a reload that returns the same instance does not release it', (
    tester,
  ) async {
    final vm = Vm();
    final released = <Vm>[];
    late Future<void> Function() reload;
    await tester.pumpWidget(
      MaterialApp(
        home: DeclarativeNavigator(
          navigator: Root(() async => vm, released, (r) => reload = r),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('order 0'), findsOneWidget);

    await reload();
    await tester.pumpAndSettle();
    expect(released, isEmpty, reason: 'released the value still shown');
    vm.bump();
    await tester.pumpAndSettle();
    expect(find.text('order 1'), findsOneWidget);

    // released once, when it is no longer shown
    final root = RootState.latest;
    root.setState(() => root.shown = false);
    await tester.pumpAndSettle();
    expect(released, [vm]);
  });

  testWidgets('a superseded reload returning the shown instance keeps it', (
    tester,
  ) async {
    final vm = Vm();
    final released = <Vm>[];
    late Future<void> Function() reload;
    var gate = Completer<Vm>()..complete(vm);
    await tester.pumpWidget(
      MaterialApp(
        home: DeclarativeNavigator(
          navigator: Root(() => gate.future, released, (r) => reload = r),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final first = gate = Completer<Vm>();
    final a = reload();
    final second = gate = Completer<Vm>();
    final b = reload();
    second.complete(vm);
    first.complete(vm);
    await a;
    await b;
    await tester.pumpAndSettle();
    expect(released, isEmpty, reason: 'released the value still shown');

    final root = RootState.latest;
    root.setState(() => root.shown = false);
    await tester.pumpAndSettle();
    expect(released, [vm]);
  });

  testWidgets('a value loaded after the navigator is gone is released once', (
    tester,
  ) async {
    final vm = Vm();
    final released = <Vm>[];
    late Future<void> Function() reload;
    var gate = Completer<Vm>()..complete(vm);
    await tester.pumpWidget(
      MaterialApp(
        home: DeclarativeNavigator(
          navigator: Root(() => gate.future, released, (r) => reload = r),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // a reload still in flight when the navigator is removed resolves to
    // the instance that was shown, which dispose already released
    final late = gate = Completer<Vm>();
    final pending = reload();
    final root = RootState.latest;
    root.setState(() => root.shown = false);
    await tester.pumpAndSettle();
    expect(released, [vm]);
    late.complete(vm);
    await pending;
    await tester.pumpAndSettle();
    expect(released, [vm]);
  });
}
