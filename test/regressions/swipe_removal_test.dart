import 'package:fdr/fdr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _Nav extends StatefulNavigator<Never> {
  const _Nav({required this.material});
  final bool material;

  @override
  _NavState createState() => _NavState();
}

class _NavState extends StatefulNavigatorState<_Nav, Never> {
  static late _NavState latest;
  bool detail = true;
  int pops = 0;

  @override
  void initState() {
    super.initState();
    latest = this;
  }

  void pop() {
    pops++;
    setState(() => detail = false);
  }

  @override
  List<NavEntry<Never>> build() => [
    const NavPage(child: Center(child: Text('home'))),
    if (detail)
      navigator.material
          ? NavPage.material(
              onPop: pop,
              child: const Center(child: Text('detail')),
            )
          : NavPage(
              onPop: pop,
              child: const Center(child: Text('detail')),
            ),
  ];
}

/// [home, detail] on iOS; the user drags detail back by [distance] and lets
/// go. With [removeAt], the state removes detail while the finger is down (a
/// timer, a server event) and the finger moves [removeAt] further. Returns
/// how often onPop ran.
Future<int> swipe(
  WidgetTester tester, {
  required bool material,
  required double distance,
  double? removeAt,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.iOS),
      home: DeclarativeNavigator(navigator: _Nav(material: material)),
    ),
  );
  await tester.pumpAndSettle();
  final gesture = await tester.startGesture(const Offset(5, 300));
  await gesture.moveBy(const Offset(50, 0));
  await tester.pump();
  await gesture.moveBy(Offset(distance - 50, 0));
  await tester.pump(const Duration(milliseconds: 16));
  if (removeAt != null) {
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).last);
    expect(navigator.userGestureInProgress, isTrue);
    _NavState.latest.setState(() => _NavState.latest.detail = false);
    await tester.pump();
    if (removeAt > 0) {
      // this drag update stops the exit animation the removal started
      await gesture.moveBy(Offset(removeAt, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
  }
  await gesture.up();
  await tester.pumpAndSettle();
  return _NavState.latest.pops;
}

void main() {
  for (final material in [false, true]) {
    final kind = material ? 'material' : 'adaptive';

    for (final distance in [180.0, 580.0]) {
      testWidgets(
        '$kind: a page the state removes during a swipe back goes, after '
        '$distance px',
        (tester) async {
          final pops = await swipe(
            tester,
            material: material,
            distance: distance,
            removeAt: 20,
          );
          expect(find.text('detail'), findsNothing);
          expect(find.text('home').hitTestable(), findsOneWidget);
          expect(pops, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('$kind: the state removes the page, the finger rests', (
      tester,
    ) async {
      final pops = await swipe(
        tester,
        material: material,
        distance: 180,
        removeAt: 0,
      );
      expect(find.text('detail'), findsNothing);
      expect(find.text('home').hitTestable(), findsOneWidget);
      expect(pops, 0);
    });

    testWidgets('$kind: a completed swipe back runs onPop once', (
      tester,
    ) async {
      final pops = await swipe(tester, material: material, distance: 580);
      expect(find.text('detail'), findsNothing);
      expect(find.text('home').hitTestable(), findsOneWidget);
      expect(pops, 1);
    });

    testWidgets('$kind: a cancelled swipe back keeps the page', (tester) async {
      final pops = await swipe(tester, material: material, distance: 180);
      expect(find.text('detail').hitTestable(), findsOneWidget);
      expect(pops, 0);
    });
  }
}
