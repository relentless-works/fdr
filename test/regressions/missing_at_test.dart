import 'package:fdr/fdr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'routes.dart';

sealed class ChildRoute extends NavRoute {
  const ChildRoute();
}

final class ChildHome extends ChildRoute {
  const ChildHome();

  @override
  Url toUrl() => const Url([]);
}

class Child extends StatefulNavigator<ChildRoute> {
  const Child();

  @override
  ChildState createState() => ChildState();
}

class ChildState extends StatefulNavigatorState<Child, ChildRoute> {
  @override
  List<NavEntry<ChildRoute>> build() => [
    NavPage(route: const ChildHome(), child: scaffold('child')),
  ];
}

class Root extends StatefulNavigator<RR> {
  const Root();

  @override
  RootState createState() => RootState();
}

class RootState extends StatefulNavigatorState<Root, RR> {
  static late RootState latest;
  bool child = false;

  @override
  void initState() {
    super.initState();
    latest = this;
  }

  @override
  List<NavEntry<RR>> build() => [
    NavPage(route: const RA(), child: scaffold('A')),
    // forgot `at`: compiles, the child's routes are not RR
    if (child) const NestedNavigator<RR, ChildRoute>(child: Child()),
  ];
}

void main() {
  // a check in every build mode: with only an assert, a release build
  // failed later with a bare cast error from deep inside fdr
  testWidgets('a NestedNavigator that needs `at` is a FlutterError', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: DeclarativeNavigator(navigator: Root())),
    );
    expect(
      () => RootState.latest.setState(() => RootState.latest.child = true),
      throwsA(
        isA<FlutterError>().having(
          (e) => e.message,
          'message',
          contains('NestedNavigator around Child needs `at`'),
        ),
      ),
    );
  });
}
