import 'package:fdr/fdr.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// Navigator.pop ignores Page.canPop, so it used to take a page without onPop
// out of the Navigator: reported, and gone until some later build of that
// navigator put it back. It throws to its caller now and the page stays, with
// its Route and State (doc section 11).

class Probe extends StatefulWidget {
  const Probe(this.label, {super.key});
  final String label;
  @override
  State<Probe> createState() => _ProbeState();
}

class _ProbeState extends State<Probe> {
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    drawer: const Drawer(child: Text('drawer')),
    body: Text(widget.label),
  );
}

class Root extends StatefulNavigator<Never> {
  const Root(this.pages);
  final List<NavEntry<Never>> Function(RootState state) pages;
  @override
  StatefulNavigatorState<Root, Never> createState() => RootState();
}

class RootState extends StatefulNavigatorState<Root, Never> {
  static late RootState latest;
  bool shown = true;
  int pops = 0;

  @override
  void initState() {
    super.initState();
    latest = this;
  }

  void close() => setState(() {
    shown = false;
    pops++;
  });

  @override
  List<NavEntry<Never>> build() => navigator.pages(this);
}

class Tabs extends StatelessNavigator<Never> {
  const Tabs();
  @override
  List<NavEntry<Never>> build() => [
    TabsPage(
      index: 0,
      tabs: const [Branch()],
      builder: (context, tabs) => tabs.single,
    ),
  ];
}

class Branch extends StatelessNavigator<Never> {
  const Branch();
  @override
  List<NavEntry<Never>> build() => const [
    NavPage(child: Probe('tab root')),
    NavPage(child: Probe('tab top')),
  ];
}

Future<void> show(
  WidgetTester tester,
  List<NavEntry<Never>> Function(RootState state) pages,
) async {
  await tester.pumpWidget(
    MaterialApp(home: DeclarativeNavigator(navigator: Root(pages))),
  );
  await tester.pumpAndSettle();
}

State state(WidgetTester tester, String label) => tester.state(
  find
      .ancestor(
        of: find.text(label, skipOffstage: false),
        matching: find.byType(Probe, skipOffstage: false),
      )
      .first,
);

ModalRoute<Object?> routeOf(WidgetTester tester, String label) =>
    ModalRoute.of(tester.element(find.text(label, skipOffstage: false)))!;

NavigatorState navigatorOf(WidgetTester tester, String label) =>
    Navigator.of(tester.element(find.text(label, skipOffstage: false)));

Matcher throwsNoOnPop(String call) => throwsA(
  isA<FlutterError>().having(
    (e) => e.message,
    'message',
    allOf(contains('$call was called on page'), contains('has no onPop')),
  ),
);

/// Pops the page showing [label], which has no onPop: the call throws and
/// the page, its Route and its State stay.
Future<void> expectPopRefused(WidgetTester tester, String label) async {
  final before = state(tester, label);
  final route = routeOf(tester, label);
  expect(navigatorOf(tester, label).pop, throwsNoOnPop('Navigator.pop'));
  expect(route.isActive, isTrue);
  expect(route.animation!.status, AnimationStatus.completed);
  await tester.pump();
  expect(find.text(label), findsOneWidget);
  expect(state(tester, label), same(before));
  expect(routeOf(tester, label), same(route));
  // the Navigator still takes updates and pops
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  const home = NavPage<Never>(child: Probe('home'));

  final kinds = <String, NavEntry<Never>>{
    'a material NavPage': const NavPage.material(child: Probe('top')),
    'a cupertino NavPage': const NavPage.cupertino(child: Probe('top')),
    'an adaptive NavPage': const NavPage(child: Probe('top')),
    'a DialogPage': const DialogPage(child: Probe('top')),
    'a CustomPage': CustomPage(
      builder: (key, canPop, child) =>
          MaterialPage(key: key, canPop: canPop, child: child),
      child: const Probe('top'),
    ),
  };
  for (final MapEntry(key: kind, value: page) in kinds.entries) {
    testWidgets('Navigator.pop of $kind without onPop throws', (tester) async {
      await show(tester, (_) => [home, page]);
      await expectPopRefused(tester, 'top');
    });
  }

  testWidgets('Navigator.pop of the root page throws', (tester) async {
    await show(tester, (_) => [home]);
    await expectPopRefused(tester, 'home');
  });

  testWidgets('Navigator.pop inside a tab throws, also at its root', (
    tester,
  ) async {
    await show(tester, (_) => [const Tabs()]);
    await expectPopRefused(tester, 'tab top');
    // the tabs page itself, from the owner's Navigator
    final outer = Navigator.of(navigatorOf(tester, 'tab top').context);
    expect(outer.pop, throwsNoOnPop('Navigator.pop'));
    await tester.pump();
    expect(find.text('tab top'), findsOneWidget);
  });

  testWidgets('a button that pops reports the error of its handler', (
    tester,
  ) async {
    await show(
      tester,
      (_) => [
        home,
        DialogPage(
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ok'),
            ),
          ),
        ),
      ],
    );
    await tester.tap(find.text('ok'));
    await tester.pump();
    expect(
      tester.takeException(),
      isA<FlutterError>().having(
        (e) => e.message,
        'message',
        contains('has no onPop'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ok'), findsOneWidget);
  });

  testWidgets('popUntil stops at a page without onPop', (tester) async {
    await show(
      tester,
      (state) => [
        home,
        const NavPage(child: Probe('middle')),
        if (state.shown) NavPage(onPop: state.close, child: const Probe('top')),
      ],
    );
    final middle = state(tester, 'middle');
    final navigator = navigatorOf(tester, 'top');
    expect(
      () => navigator.popUntil((route) => route.isFirst),
      throwsNoOnPop('Navigator.pop'),
    );
    await tester.pumpAndSettle();
    // the page with onPop went through it, the one without stays
    expect(RootState.latest.pops, 1);
    expect(find.text('top'), findsNothing);
    expect(find.text('middle'), findsOneWidget);
    expect(state(tester, 'middle'), same(middle));
  });

  testWidgets('Navigator.removeRoute of a page without onPop throws', (
    tester,
  ) async {
    await show(tester, (_) => [home, const NavPage(child: Probe('top'))]);
    final before = state(tester, 'top');
    final navigator = navigatorOf(tester, 'top');
    expect(
      () => navigator.removeRoute(routeOf(tester, 'top')),
      throwsNoOnPop('Navigator.removeRoute'),
    );
    await tester.pump();
    expect(state(tester, 'top'), same(before));
  });

  // what Flutter reports to onDidRemovePage besides a pop
  Future<void> expectShownAgain(WidgetTester tester, String label) async {
    final removed = routeOf(tester, label);
    navigatorOf(tester, label).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (context, _, _) => const Text('replacement'),
      ),
    );
    expect(
      tester.takeException(),
      isA<FlutterError>().having(
        (e) => e.message,
        'message',
        allOf(contains('has no onPop'), contains('shown again')),
      ),
    );
    // in the frame of the replacement, next to the route that is leaving
    await tester.pump();
    expect(find.text(label, skipOffstage: false), findsNWidgets(2));
    await tester.pumpAndSettle();
    expect(find.text(label), findsOneWidget);
    expect(routeOf(tester, label), isNot(same(removed)));
    expect(routeOf(tester, label).isActive, isTrue);
    expect(tester.takeException(), isNull);
  }

  testWidgets('a replaced page without onPop is back in the next frame', (
    tester,
  ) async {
    await show(tester, (_) => [home, const NavPage(child: Probe('top'))]);
    await expectShownAgain(tester, 'top');
  });

  testWidgets('a replaced page without onPop in a tab is back as well', (
    tester,
  ) async {
    await show(tester, (_) => [const Tabs()]);
    await expectShownAgain(tester, 'tab top');
  });

  testWidgets('Navigator.pop closes a drawer of a page without onPop', (
    tester,
  ) async {
    await show(tester, (_) => [home, const NavPage(child: Probe('top'))]);
    tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();
    expect(find.text('drawer'), findsOneWidget);
    navigatorOf(tester, 'top').pop();
    await tester.pumpAndSettle();
    expect(find.text('drawer'), findsNothing);
    expect(find.text('top'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Navigator.pop of a route pushed on a page without onPop', (
    tester,
  ) async {
    await show(tester, (_) => [home]);
    final navigator = navigatorOf(tester, 'home');
    final result = showDialog<int>(
      context: tester.element(find.text('home')),
      useRootNavigator: false,
      builder: (context) => const Text('pushed'),
    );
    await tester.pumpAndSettle();
    navigator.pop(7);
    await tester.pumpAndSettle();
    expect(await result, 7);
    expect(find.text('pushed'), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('back button and system back stay silent without onPop', (
    tester,
  ) async {
    final exits = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') exits.add(call);
        return null;
      },
    );
    await show(tester, (_) => [home, const NavPage(child: Probe('top'))]);
    expect(find.byType(BackButton), findsNothing);
    final before = state(tester, 'top');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(await navigatorOf(tester, 'top').maybePop(), isTrue);
    await tester.pumpAndSettle();
    expect(state(tester, 'top'), same(before));
    expect(exits, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Navigator.pop of a page with onPop runs it once', (
    tester,
  ) async {
    await show(
      tester,
      (state) => [
        home,
        if (state.shown) NavPage(onPop: state.close, child: const Probe('top')),
      ],
    );
    navigatorOf(tester, 'top').pop();
    await tester.pumpAndSettle();
    expect(RootState.latest.pops, 1);
    expect(find.text('top'), findsNothing);
    expect(find.text('home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a page the state removes goes without onPop', (tester) async {
    await show(
      tester,
      (state) => [home, if (state.shown) const NavPage(child: Probe('top'))],
    );
    RootState.latest.setState(() => RootState.latest.shown = false);
    await tester.pumpAndSettle();
    expect(find.text('top'), findsNothing);
    expect(find.text('home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
