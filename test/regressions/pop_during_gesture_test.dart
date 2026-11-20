import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoPage, CupertinoSheetRoute;
import 'package:fdr/fdr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// Flutter's back gestures and its bottom sheet call Navigator.pop themselves
// once they have moved the route out. The pop of a page without onPop threw
// into those handlers: the swipe never ended (the page parked off screen, the
// Navigator took no input), and a dragged sheet stayed as an invisible route
// over the app. The pop is refused without a throw there and the route comes
// back (doc section 11). Only the route the gesture moves is treated so: a pop
// of another page by the app meanwhile throws as always.

class Probe extends StatefulWidget {
  const Probe(this.label, {super.key});
  final String label;
  @override
  State<Probe> createState() => _ProbeState();
}

class _ProbeState extends State<Probe> {
  @override
  Widget build(BuildContext context) => Center(child: Text(widget.label));
}

class SheetPage extends Page<Object?> {
  const SheetPage({super.key, super.canPop, required this.child});
  final Widget child;

  @override
  Route<Object?> createRoute(BuildContext context) =>
      ModalBottomSheetRoute<Object?>(
        settings: this,
        isScrollControlled: false,
        builder: (context) =>
            (ModalRoute.settingsOf(context)! as SheetPage).child,
      );
}

class CupertinoSheetPage extends Page<Object?> {
  const CupertinoSheetPage({super.key, super.canPop, required this.child});
  final Widget child;

  @override
  Route<Object?> createRoute(BuildContext context) =>
      CupertinoSheetRoute<Object?>(
        settings: this,
        scrollableBuilder: (context, controller) =>
            (ModalRoute.settingsOf(context)! as CupertinoSheetPage).child,
      );
}

typedef Top = NavEntry<Never> Function(VoidCallback? onPop);

class Nav extends StatefulNavigator<Never> {
  const Nav(this.top);
  final Top top;
  @override
  NavState createState() => NavState();
}

class NavState extends StatefulNavigatorState<Nav, Never> {
  static late NavState latest;
  bool shown = true;
  bool canPop = true;
  bool saving = false;
  int pops = 0;

  @override
  void initState() {
    super.initState();
    latest = this;
  }

  void pop() => setState(() {
    pops++;
    shown = false;
  });

  /// What a form does while it saves.
  void disablePop() => setState(() => canPop = false);

  /// The state removes the page itself (a timer, a server event).
  void remove() => setState(() => shown = false);

  void showSaving() => setState(() => saving = true);

  @override
  List<NavEntry<Never>> build() => [
    NavPage(
      child: Center(
        child: TextButton(onPressed: () => taps++, child: const Text('home')),
      ),
    ),
    if (shown) navigator.top(canPop ? pop : null),
    if (saving) const DialogPage(child: Text('saving')),
  ];
}

int taps = 0;

Future<void> show(
  WidgetTester tester,
  Top top, {
  TargetPlatform platform = TargetPlatform.iOS,
}) async {
  taps = 0;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      home: DeclarativeNavigator(navigator: Nav(top)),
    ),
  );
  await tester.pumpAndSettle();
}

NavigatorState navigatorOf(WidgetTester tester) =>
    tester.state<NavigatorState>(find.bySubtype<Navigator>().last);

State probe(WidgetTester tester) =>
    tester.state(find.byType(Probe, skipOffstage: false));

ModalRoute<Object?> routeOf(WidgetTester tester, String label) =>
    ModalRoute.of(tester.element(find.text(label, skipOffstage: false)))!;

/// The page is where it was, with its Route and State, and takes input.
Future<void> expectStays(
  WidgetTester tester,
  String label,
  State state,
  Route<Object?> route,
) async {
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  expect(navigatorOf(tester).userGestureInProgress, isFalse);
  expect(find.text(label).hitTestable(), findsOneWidget);
  expect(tester.getCenter(find.text(label)).dx, 400);
  expect(probe(tester), same(state));
  expect(routeOf(tester, label), same(route));
  expect(route.isCurrent, isTrue);
  expect(routeOf(tester, label).animation!.status, AnimationStatus.completed);
  expect(NavState.latest.pops, 0);
}

void main() {
  final swiped = <String, Top>{
    'an adaptive NavPage': (onPop) =>
        NavPage(onPop: onPop, child: const Probe('detail')),
    'a material NavPage': (onPop) =>
        NavPage.material(onPop: onPop, child: const Probe('detail')),
    'a CustomPage of a CupertinoPage': (onPop) => CustomPage(
      onPop: onPop,
      builder: (key, canPop, child) =>
          CupertinoPage(key: key, canPop: canPop, child: child),
      child: const Probe('detail'),
    ),
  };

  for (final MapEntry(key: kind, value: top) in swiped.entries) {
    testWidgets('$kind that loses onPop during a swipe back stays', (
      tester,
    ) async {
      await show(tester, top);
      final state = probe(tester);
      final route = routeOf(tester, 'detail');
      final gesture = await tester.startGesture(const Offset(5, 300));
      await gesture.moveBy(const Offset(50, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(530, 0));
      await tester.pump(const Duration(milliseconds: 16));
      expect(navigatorOf(tester).userGestureInProgress, isTrue);
      NavState.latest.disablePop();
      await tester.pump();
      await gesture.up();
      expect(tester.takeException(), isNull);
      await expectStays(tester, 'detail', state, route);
      expect(tester.takeException(), isNull);

      // and the next swipe does not start
      await tester.dragFrom(const Offset(5, 300), const Offset(580, 0));
      await tester.pumpAndSettle();
      expect(find.text('detail').hitTestable(), findsOneWidget);
    });
  }

  testWidgets('a page that loses onPop during a predictive back stays', (
    tester,
  ) async {
    await show(
      tester,
      (onPop) => NavPage(onPop: onPop, child: const Probe('detail')),
      platform: TargetPlatform.android,
    );
    final state = probe(tester);
    final route = routeOf(tester, 'detail');
    // what PredictiveBackPageTransitionsBuilder calls on the route
    route.handleStartBackGesture(progress: 1);
    route.handleUpdateBackGestureProgress(progress: 0.4);
    await tester.pump();
    NavState.latest.disablePop();
    await tester.pump();
    route.handleCommitBackGesture();
    await expectStays(tester, 'detail', state, route);
    expect(tester.takeException(), isNull);
  });

  testWidgets('popUntil during a swipe back throws at a page without onPop', (
    tester,
  ) async {
    await show(tester, swiped.values.first);
    final state = probe(tester);
    final route = routeOf(tester, 'detail');
    final gesture = await tester.startGesture(const Offset(5, 300));
    await gesture.moveBy(const Offset(50, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(200, 0));
    await tester.pump(const Duration(milliseconds: 16));
    NavState.latest.disablePop();
    await tester.pump();
    final navigator = navigatorOf(tester);
    expect(
      () => navigator.popUntil((route) => route.isFirst),
      throwsA(
        isA<FlutterError>().having(
          (e) => e.message,
          'message',
          contains('has no onPop'),
        ),
      ),
    );
    await gesture.up();
    await expectStays(tester, 'detail', state, route);
  });

  final throwsNoOnPop = throwsA(
    isA<FlutterError>().having(
      (e) => e.message,
      'message',
      allOf(contains('Navigator.pop was called on page'), contains('no onPop')),
    ),
  );

  Future<TestGesture> startSwipe(WidgetTester tester) async {
    final gesture = await tester.startGesture(const Offset(5, 300));
    await gesture.moveBy(const Offset(50, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(150, 0));
    await tester.pump(const Duration(milliseconds: 16));
    expect(navigatorOf(tester).userGestureInProgress, isTrue);
    return gesture;
  }

  testWidgets('Navigator.pop of the page below a swiped page that the state '
      'removed throws', (tester) async {
    await show(tester, swiped.values.first);
    final gesture = await startSwipe(tester);
    NavState.latest.remove();
    await tester.pump();
    // the top page is home now, which has no onPop
    expect(() => navigatorOf(tester).pop(), throwsNoOnPop);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(navigatorOf(tester).userGestureInProgress, isFalse);
    expect(find.text('detail'), findsNothing);
    await tester.tap(find.text('home'));
    expect(taps, 1);
    expect(NavState.latest.pops, 0);
  });

  testWidgets('Navigator.pop of a page without onPop shown over a swiped page '
      'throws', (tester) async {
    await show(tester, swiped.values.first);
    final state = probe(tester);
    final gesture = await startSwipe(tester);
    NavState.latest.showSaving();
    await tester.pump();
    expect(() => navigatorOf(tester).pop(), throwsNoOnPop);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(navigatorOf(tester).userGestureInProgress, isFalse);
    expect(find.text('saving').hitTestable(), findsOneWidget);
    expect(probe(tester), same(state));
    expect(tester.getCenter(find.text('detail')).dx, 400);
    expect(NavState.latest.pops, 0);
  });

  testWidgets('a page refused during a swipe that the state then removes is '
      'not brought back', (tester) async {
    await show(tester, swiped.values.first);
    final gesture = await startSwipe(tester);
    NavState.latest.disablePop();
    await tester.pump();
    // the app's pop of the swiped page is refused like the handler's
    navigatorOf(tester).pop();
    NavState.latest.remove();
    await tester.pump();
    await gesture.moveBy(const Offset(100, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(navigatorOf(tester).userGestureInProgress, isFalse);
    expect(find.text('detail', skipOffstage: false), findsNothing);
    await tester.tap(find.text('home'));
    expect(taps, 1);
    expect(NavState.latest.pops, 0);
  });

  group('a Cupertino sheet page', () {
    NavEntry<Never> sheet(VoidCallback? onPop) => CustomPage(
      onPop: onPop,
      builder: (key, canPop, child) =>
          CupertinoSheetPage(key: key, canPop: canPop, child: child),
      child: const Probe('sheet'),
    );

    // its drag is a user gesture that starts whatever Page.canPop says
    testWidgets('without onPop that is dragged down comes back, reported', (
      tester,
    ) async {
      await show(tester, (_) => sheet(null));
      final state = probe(tester);
      final route = routeOf(tester, 'sheet');
      await tester.dragFrom(const Offset(400, 100), const Offset(0, 450));
      expect(
        tester.takeException(),
        isA<FlutterError>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('Navigator.pop was called on page'),
            contains('has no onPop'),
            contains('shown again'),
            contains('enableDrag: canPop'),
          ),
        ),
      );
      await expectStays(tester, 'sheet', state, route);
      expect(tester.takeException(), isNull);
    });

    testWidgets('with onPop that is dragged down runs it once', (tester) async {
      await show(tester, sheet);
      await tester.dragFrom(const Offset(400, 100), const Offset(0, 450));
      await tester.pumpAndSettle();
      expect(NavState.latest.pops, 1);
      expect(find.text('sheet'), findsNothing);
      await tester.tap(find.text('home'));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('a bottom sheet page', () {
    NavEntry<Never> sheet(VoidCallback? onPop) => CustomPage(
      onPop: onPop,
      builder: (key, canPop, child) =>
          SheetPage(key: key, canPop: canPop, child: child),
      child: const SizedBox(height: 300, child: Probe('sheet')),
    );

    testWidgets('without onPop that is dragged down comes back, reported', (
      tester,
    ) async {
      await show(tester, (_) => sheet(null));
      final state = probe(tester);
      final route = routeOf(tester, 'sheet');
      await tester.drag(find.text('sheet'), const Offset(0, 280));
      expect(
        tester.takeException(),
        isA<FlutterError>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('Navigator.pop was called on page'),
            contains('has no onPop'),
            contains('shown again'),
          ),
        ),
      );
      await expectStays(tester, 'sheet', state, route);
      expect(tester.takeException(), isNull);

      // the barrier still asks first, so it stays silent
      await tester.tapAt(const Offset(400, 50));
      await tester.pumpAndSettle();
      expect(find.text('sheet').hitTestable(), findsOneWidget);
      expect(taps, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('with onPop that is dragged down runs it once', (tester) async {
      await show(tester, sheet);
      await tester.drag(find.text('sheet'), const Offset(0, 280));
      await tester.pumpAndSettle();
      expect(NavState.latest.pops, 1);
      expect(find.text('sheet'), findsNothing);
      await tester.tap(find.text('home'));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });
  });
}
