import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final log = <String>[];

class Vm extends ChangeNotifier {
  bool released = false;
  void save() {
    if (released) log.add('child used released vm');
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
  List<NavEntry<Never>> build() => [const NavPage(child: Text('order'))];

  @override
  void dispose() {
    // e.g. flush a draft into the view model
    navigator.vm.save();
    log.add('child disposed');
    super.dispose();
  }
}

class Root extends StatefulNavigator<Never> {
  const Root();
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
          load: () async => Vm(),
          onDispose: (vm) {
            vm.released = true;
            vm.dispose();
            log.add('released');
          },
          loading: const Text('loading'),
          error: (e, retry) => Text('$e'),
          builder: (vm, _) => OrderNav(vm),
        ),
      ),
  ];
}

void main() {
  testWidgets('onDispose runs after the navigators built from the data', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: DeclarativeNavigator(navigator: Root())),
    );
    await tester.pumpAndSettle();
    expect(find.text('order'), findsOneWidget);
    final root = RootState.latest;
    root.setState(() => root.shown = false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(log, ['child disposed', 'released']);
  });
}
