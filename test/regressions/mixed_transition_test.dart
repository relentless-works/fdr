import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoPage;
import 'package:fdr/fdr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// NavPage.cupertino's route did not hand its transition to the page below
// (cupertino_ui's delegatedTransition), so a Material page stood still while
// a Cupertino page slid in over it; below a CupertinoPage it moves along.

class _Nav extends StatefulNavigator<Never> {
  const _Nav({required this.fullscreenDialog});
  final bool fullscreenDialog;
  @override
  _NavState createState() => _NavState();
}

class _NavState extends StatefulNavigatorState<_Nav, Never> {
  static late _NavState latest;
  bool top = false;

  @override
  void initState() {
    super.initState();
    latest = this;
  }

  @override
  List<NavEntry<Never>> build() => [
    const NavPage.material(child: Center(child: Text('below'))),
    if (top)
      NavPage.cupertino(
        fullscreenDialog: navigator.fullscreenDialog,
        child: const Center(child: Text('top')),
      ),
  ];
}

/// Where the Material page is 200 ms into the push of the Cupertino page.
Future<double> pushOver(WidgetTester tester, Widget home) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.android),
      home: home,
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.getCenter(find.text('below')).dx, 400);
  _NavState.latest.setState(() => _NavState.latest.top = true);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  final dx = tester.getCenter(find.text('below', skipOffstage: false)).dx;
  await tester.pumpAndSettle();
  return dx;
}

void main() {
  testWidgets('a Material page moves below a NavPage.cupertino as below a '
      'CupertinoPage', (tester) async {
    final dx = await pushOver(
      tester,
      const DeclarativeNavigator(navigator: _Nav(fullscreenDialog: false)),
    );
    expect(dx, lessThan(400));

    // the same stack of Flutter's own pages
    final pages = ValueNotifier<List<Page<Object?>>>(const [
      MaterialPage(child: Center(child: Text('below'))),
    ]);
    addTearDown(pages.dispose);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: ValueListenableBuilder(
          valueListenable: pages,
          builder: (context, value, _) =>
              Navigator(pages: value, onDidRemovePage: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    pages.value = [
      ...pages.value,
      const CupertinoPage(child: Center(child: Text('top'))),
    ];
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getCenter(find.text('below')).dx, moreOrLessEquals(dx));
  });

  testWidgets('a Material page stays below a fullscreen dialog', (
    tester,
  ) async {
    final dx = await pushOver(
      tester,
      const DeclarativeNavigator(navigator: _Nav(fullscreenDialog: true)),
    );
    expect(dx, 400);
  });
}
