import 'package:fdr/fdr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// A page without a route is matched like an unkeyed widget: by the kind of
// page and its child's type and key, among the pages of its navigator above
// the same routed page. A page that comes or goes below it must not hand its
// Route and State to another page (doc section 11).

class Probe extends StatefulWidget {
  const Probe(this.label, {super.key});
  final String label;
  @override
  State<Probe> createState() => _ProbeState();
}

class _ProbeState extends State<Probe> {
  @override
  Widget build(BuildContext context) => Material(child: Text(widget.label));
}

class Other extends StatefulWidget {
  const Other(this.label, {super.key});
  final String label;
  @override
  State<Other> createState() => _OtherState();
}

class _OtherState extends State<Other> {
  @override
  Widget build(BuildContext context) => Material(child: Text(widget.label));
}

class Root extends StatefulNavigator<Never> {
  const Root(this.pages);
  final List<NavEntry<Never>> Function() pages;
  @override
  StatefulNavigatorState<Root, Never> createState() => RootState();
}

class RootState extends StatefulNavigatorState<Root, Never> {
  static late RootState latest;

  @override
  void initState() {
    super.initState();
    latest = this;
  }

  @override
  List<NavEntry<Never>> build() => [
    const NavPage(child: Text('home')),
    ...navigator.pages(),
  ];
}

class Child extends StatefulNavigator<Never> {
  const Child(this.label, {super.key});
  final String label;
  @override
  StatefulNavigatorState<Child, Never> createState() => _ChildState();
}

class _ChildState extends StatefulNavigatorState<Child, Never> {
  @override
  List<NavEntry<Never>> build() => [NavPage(child: Probe(navigator.label))];
}

Future<void> show(
  WidgetTester tester,
  List<NavEntry<Never>> Function() pages,
) async {
  await tester.pumpWidget(
    MaterialApp(home: DeclarativeNavigator(navigator: Root(pages))),
  );
  await tester.pumpAndSettle();
}

Future<void> rebuild(WidgetTester tester, void Function() change) async {
  RootState.latest.setState(change);
  await tester.pump();
  // into the transitions the change started
  await tester.pump(const Duration(milliseconds: 50));
}

State state(WidgetTester tester, String label) => tester.state(
  find
      .ancestor(
        of: find.text(label, skipOffstage: false),
        matching: find.bySubtype<StatefulWidget>(skipOffstage: false),
      )
      .first,
);

ModalRoute<Object?> routeOf(WidgetTester tester, String label) =>
    ModalRoute.of(tester.element(find.text(label, skipOffstage: false)))!;

void main() {
  testWidgets('a page of another type inserted below keeps the upper page', (
    tester,
  ) async {
    var notice = false;
    await show(
      tester,
      () => [
        if (notice) const NavPage(child: Other('notice')),
        const NavPage(child: Probe('top')),
      ],
    );
    final top = state(tester, 'top');
    final route = routeOf(tester, 'top');

    await rebuild(tester, () => notice = true);
    expect(state(tester, 'top'), same(top));
    expect(routeOf(tester, 'top'), same(route));
    expect(route.animation!.status, AnimationStatus.completed);
    expect(routeOf(tester, 'notice'), isNot(same(route)));
    await tester.pumpAndSettle();

    final noticeRoute = routeOf(tester, 'notice');
    await rebuild(tester, () => notice = false);
    expect(state(tester, 'top'), same(top));
    expect(routeOf(tester, 'top'), same(route));
    // the page that left is the one that goes, without taking the top along
    expect(route.animation!.status, AnimationStatus.completed);
    expect(noticeRoute.isActive, isFalse);
    await tester.pumpAndSettle();
    expect(find.text('top'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a keyed page inserted below keeps the upper page', (
    tester,
  ) async {
    var notice = false;
    await show(
      tester,
      () => [
        if (notice)
          const NavPage(key: ValueKey('notice'), child: Probe('notice')),
        const NavPage(child: Probe('top')),
      ],
    );
    final top = state(tester, 'top');
    final route = routeOf(tester, 'top');

    await rebuild(tester, () => notice = true);
    expect(state(tester, 'top'), same(top));
    expect(routeOf(tester, 'top'), same(route));
    expect(route.animation!.status, AnimationStatus.completed);
  });

  testWidgets('another child type at the same position is a new page', (
    tester,
  ) async {
    var other = false;
    await show(
      tester,
      () => [
        other
            ? const NavPage(child: Other('second'))
            : const NavPage(child: Probe('first')),
      ],
    );
    final route = routeOf(tester, 'first');

    await rebuild(tester, () => other = true);
    final second = routeOf(tester, 'second');
    expect(second, isNot(same(route)));
    expect(second.animation!.status, AnimationStatus.forward);
    expect(route.isActive, isFalse);
    await tester.pumpAndSettle();
    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);
  });

  testWidgets('another route class at the same position is a new page', (
    tester,
  ) async {
    var cupertino = false;
    await show(
      tester,
      () => [
        cupertino
            ? const NavPage.cupertino(child: Probe('page'))
            : const NavPage.material(child: Probe('page')),
      ],
    );
    final before = state(tester, 'page');
    final route = routeOf(tester, 'page');

    await rebuild(tester, () => cupertino = true);
    await tester.pumpAndSettle();
    expect(routeOf(tester, 'page'), isNot(same(route)));
    expect(state(tester, 'page'), isNot(same(before)));
  });

  testWidgets('pages of the same type without keys are matched in order', (
    tester,
  ) async {
    var first = true;
    await show(
      tester,
      () => [
        if (first) const NavPage(child: Probe('a')),
        const NavPage(child: Probe('b')),
      ],
    );
    final a = state(tester, 'a');
    final b = state(tester, 'b');
    expect(b, isNot(same(a)));

    // like two unkeyed widgets of one type in a Column: the first one stays
    await rebuild(tester, () => first = false);
    await tester.pumpAndSettle();
    expect(state(tester, 'b'), same(a));
  });

  testWidgets('an explicit key tells pages of the same type apart', (
    tester,
  ) async {
    var first = true;
    await show(
      tester,
      () => [
        if (first) const NavPage(key: ValueKey('a'), child: Probe('a')),
        const NavPage(key: ValueKey('b'), child: Probe('b')),
      ],
    );
    final b = state(tester, 'b');
    final route = routeOf(tester, 'b');

    await rebuild(tester, () => first = false);
    expect(routeOf(tester, 'b'), same(route));
    expect(route.animation!.status, AnimationStatus.completed);
    await tester.pumpAndSettle();
    expect(state(tester, 'b'), same(b));
  });

  testWidgets('the key of the child tells pages of the same type apart', (
    tester,
  ) async {
    var first = true;
    await show(
      tester,
      () => [
        if (first) const NavPage(child: Probe('a', key: ValueKey('a'))),
        const NavPage(child: Probe('b', key: ValueKey('b'))),
      ],
    );
    final b = state(tester, 'b');
    final route = routeOf(tester, 'b');

    await rebuild(tester, () => first = false);
    expect(routeOf(tester, 'b'), same(route));
    await tester.pumpAndSettle();
    expect(state(tester, 'b'), same(b));
  });

  testWidgets('a page inserted below a dialog keeps the dialog', (
    tester,
  ) async {
    var sheet = false;
    var dialogOpen = true;
    await show(
      tester,
      () => [
        if (sheet) const NavPage(child: Probe('sheet')),
        if (dialogOpen)
          DialogPage(
            onPop: () => RootState.latest.setState(() => dialogOpen = false),
            child: const Probe('dialog'),
          ),
      ],
    );
    final dialog = state(tester, 'dialog');
    final route = routeOf(tester, 'dialog');

    await rebuild(tester, () => sheet = true);
    expect(state(tester, 'dialog'), same(dialog));
    expect(routeOf(tester, 'dialog'), same(route));
    expect(route.animation!.status, AnimationStatus.completed);
    await tester.pumpAndSettle();
    // the page below is a page, not a second dialog
    expect(routeOf(tester, 'sheet'), isA<PageRoute<Object?>>());
    expect(tester.takeException(), isNull);

    // a pop still finds the dialog by its key
    Navigator.of(tester.element(find.text('dialog'))).pop();
    await tester.pumpAndSettle();
    expect(dialogOpen, isFalse);
    expect(find.text('dialog'), findsNothing);
    expect(find.text('sheet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a dialog is not taken for the dialog that was below it', (
    tester,
  ) async {
    var first = true;
    await show(
      tester,
      () => [
        if (first) const DialogPage(child: Other('confirm')),
        const DialogPage(child: Probe('details')),
      ],
    );
    final details = state(tester, 'details');
    final route = routeOf(tester, 'details');

    await rebuild(tester, () => first = false);
    expect(routeOf(tester, 'details'), same(route));
    expect(route.animation!.status, AnimationStatus.completed);
    await tester.pumpAndSettle();
    expect(state(tester, 'details'), same(details));
    expect(find.text('confirm'), findsNothing);
  });

  testWidgets('a page is not taken for one of a navigator that left', (
    tester,
  ) async {
    var first = true;
    await show(
      tester,
      () => [
        if (first) const Child('a', key: ValueKey('a')),
        const Child('b', key: ValueKey('b')),
      ],
    );
    final b = state(tester, 'b');
    final route = routeOf(tester, 'b');

    await rebuild(tester, () => first = false);
    expect(routeOf(tester, 'b'), same(route));
    expect(route.animation!.status, AnimationStatus.completed);
    await tester.pumpAndSettle();
    expect(state(tester, 'b'), same(b));
  });
}
