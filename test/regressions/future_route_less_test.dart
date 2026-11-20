import 'dart:async';

import 'package:fdr/fdr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// A FutureNavigator's loading page, its error page and the first page of the
// loaded child are one page: with a route they share its key, and without
// one (an app without URLs) they have to be matched as one page as well.
// Keyed by the navigator that built them and their child's type, each step
// was a new page that slid in over the one before (doc sections 9 and 11).

class Loading extends StatelessWidget {
  const Loading({super.key});
  @override
  Widget build(BuildContext context) => const Material(child: Text('loading'));
}

class Failed extends StatelessWidget {
  const Failed(this.retry, {super.key});
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Material(
    child: TextButton(onPressed: retry, child: const Text('retry')),
  );
}

class Content extends StatefulNavigator<Never> {
  const Content(this.data);
  final String data;
  @override
  StatefulNavigatorState<Content, Never> createState() => ContentState();
}

class ContentState extends StatefulNavigatorState<Content, Never> {
  static late ContentState latest;
  bool detail = false;

  @override
  void initState() {
    super.initState();
    latest = this;
  }

  @override
  List<NavEntry<Never>> build() => [
    NavPage(child: Material(child: Text(navigator.data))),
    if (detail) const NavPage(child: Material(child: Text('detail'))),
  ];
}

class Root extends StatelessNavigator<Never> {
  const Root(this.load, {required this.nested});
  final Future<String> Function() load;
  final bool nested;

  @override
  List<NavEntry<Never>> build() {
    final future = FutureNavigator<String, Never>(
      key: const ValueKey('order'),
      load: load,
      loading: const Loading(),
      error: (error, retry) => Failed(retry),
      builder: (data, _) => Content(data),
    );
    return [
      const NavPage(child: Material(child: Text('home'))),
      if (nested) NestedNavigator<Never, Never>(child: future) else future,
    ];
  }
}

ModalRoute<Object?> routeOf(WidgetTester tester, String label) =>
    ModalRoute.of(tester.element(find.text(label, skipOffstage: false)))!;

void main() {
  for (final nested in [true, false]) {
    final where = nested ? 'in a NestedNavigator' : 'placed directly';
    late Completer<String> load;

    Future<Route<Object?>> show(WidgetTester tester) async {
      load = Completer();
      await tester.pumpWidget(
        MaterialApp(
          home: DeclarativeNavigator(
            navigator: Root(() => load.future, nested: nested),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return routeOf(tester, 'loading');
    }

    /// The page showing [label] is [route], without a transition.
    Future<void> expectInPlace(
      WidgetTester tester,
      String label,
      Route<Object?> route,
    ) async {
      await tester.pump();
      // into a transition, if one started
      await tester.pump(const Duration(milliseconds: 50));
      final shown = routeOf(tester, label);
      expect(shown, same(route));
      expect(shown.animation!.status, AnimationStatus.completed);
      expect(route.isActive, isTrue);
      expect(find.text(label).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    testWidgets('without routes, the loaded page replaces the loading page '
        'in place ($where)', (tester) async {
      final route = await show(tester);
      load.complete('order');
      await expectInPlace(tester, 'order', route);
      expect(find.text('loading', skipOffstage: false), findsNothing);

      // a page the child shows above it is a new page, and leaves it alone
      ContentState.latest.setState(() => ContentState.latest.detail = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final detail = routeOf(tester, 'detail');
      expect(detail, isNot(same(route)));
      expect(detail.animation!.status, AnimationStatus.forward);
      expect(routeOf(tester, 'order'), same(route));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('without routes, the error page and the retry replace the '
        'loading page in place ($where)', (tester) async {
      final route = await show(tester);
      load.completeError(StateError('offline'));
      await expectInPlace(tester, 'retry', route);

      load = Completer();
      await tester.tap(find.text('retry'));
      await expectInPlace(tester, 'loading', route);

      load.complete('order');
      await expectInPlace(tester, 'order', route);
    });
  }
}
