import 'dart:async';

import 'package:fdr/fdr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// The route a FutureNavigator was given is handed to its child once. A child
// created later (a reload whose data the builder turns into another
// navigator) does not start at that long-consumed deep link.
// Routes are plain strings here: 'detail' and 'more'.

class Child extends StatefulNavigator<String> {
  const Child(this.data, this.reload);
  final String data;
  final Future<void> Function() reload;
  @override
  ChildState createState() => ChildState();
}

class ChildState extends StatefulNavigatorState<Child, String> {
  static late ChildState latest;
  bool more = false;
  @override
  void initState() {
    super.initState();
    latest = this;
  }

  @override
  void applyRoute(String route) => more = route == 'more';

  @override
  List<NavEntry<String>> build() => [
    NavPage(route: 'detail', child: Text('detail ${navigator.data}')),
    if (more)
      NavPage(
        route: 'more',
        onPop: () => setState(() => more = false),
        child: const Text('more'),
      ),
  ];
}

class AltChild extends StatefulNavigator<String> {
  const AltChild(this.data);
  final String data;
  @override
  AltChildState createState() => AltChildState();
}

class AltChildState extends StatefulNavigatorState<AltChild, String> {
  String got = 'nothing';
  @override
  void applyRoute(String route) => got = route;

  @override
  List<NavEntry<String>> build() => [
    NavPage(route: 'detail', child: Text('alt got $got')),
  ];
}

late Completer<String> pending;

class Root extends StatefulNavigator<String> {
  const Root();
  @override
  RootState createState() => RootState();
}

class RootState extends StatefulNavigatorState<Root, String> {
  @override
  List<NavEntry<String>> build() => [
    const NavPage(child: Text('home')),
    NestedNavigator<String, String>(
      route: 'more', // the deep link
      child: FutureNavigator<String, String>(
        key: const ValueKey(1),
        load: () => (pending = Completer<String>()).future,
        loading: const Text('loading'),
        error: (e, retry) => Text('$e'),
        builder: (data, reload) =>
            data.startsWith('alt') ? AltChild(data) : Child(data, reload),
      ),
    ),
  ];
}

void main() {
  testWidgets('a child created after a reload does not get the old deep link', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: DeclarativeNavigator(navigator: Root())),
    );
    await tester.pump();
    expect(find.text('loading'), findsOneWidget);

    pending.complete('v1');
    await tester.pumpAndSettle();
    expect(find.text('more'), findsOneWidget); // deep link handed over once

    final child = ChildState.latest;
    child.setState(() => child.more = false); // the user pops to detail
    await tester.pumpAndSettle();
    expect(find.text('detail v1'), findsOneWidget);
    expect(find.text('more'), findsNothing);

    final reloaded = child.navigator.reload();
    pending.complete('alt');
    await reloaded;
    await tester.pumpAndSettle();

    // the user was at 'detail'; the long-consumed 'more' must not come back
    expect(find.text('alt got more'), findsNothing);
    expect(find.text('alt got nothing'), findsOneWidget);
  });
}
