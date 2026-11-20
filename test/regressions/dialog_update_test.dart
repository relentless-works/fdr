import 'package:fdr/fdr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _Nav extends StatefulNavigator<Never> {
  const _Nav(this.builder);

  final List<NavEntry<Never>> Function(_NavState state) builder;

  @override
  _NavState createState() => _NavState();
}

class _NavState extends StatefulNavigatorState<_Nav, Never> {
  static late _NavState latest;

  int n = 0;
  bool shown = true;

  @override
  List<NavEntry<Never>> build() {
    latest = this;
    return navigator.builder(this);
  }
}

Future<void> _pumpNav(
  WidgetTester tester,
  List<NavEntry<Never>> Function(_NavState state) builder,
) async {
  await tester.pumpWidget(
    MaterialApp(home: DeclarativeNavigator(navigator: _Nav(builder))),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a NavPage shows the content of the latest build', (
    tester,
  ) async {
    await _pumpNav(
      tester,
      (s) => [
        const NavPage(child: Scaffold(body: Text('home'))),
        NavPage(
          onPop: () => s.setState(() {}),
          child: Scaffold(body: Text('count ${s.n}')),
        ),
      ],
    );
    expect(find.text('count 0'), findsOneWidget);
    _NavState.latest.setState(() => _NavState.latest.n = 1);
    await tester.pumpAndSettle();
    expect(find.text('count 1'), findsOneWidget);
  });

  testWidgets('a DialogPage shows the content of the latest build', (
    tester,
  ) async {
    await _pumpNav(
      tester,
      (s) => [
        const NavPage(child: Scaffold(body: Text('home'))),
        DialogPage(
          onPop: () => s.setState(() {}),
          child: AlertDialog(content: Text('count ${s.n}')),
        ),
      ],
    );
    expect(find.text('count 0'), findsOneWidget);
    _NavState.latest.setState(() => _NavState.latest.n = 1);
    await tester.pumpAndSettle();
    expect(find.text('count 1'), findsOneWidget);
  });

  testWidgets('a DialogPage barrier dismisses once onPop is set', (
    tester,
  ) async {
    await _pumpNav(
      tester,
      (s) => [
        const NavPage(child: Scaffold(body: Text('home'))),
        if (s.shown)
          DialogPage(
            onPop: s.n == 0 ? null : () => s.setState(() => s.shown = false),
            child: const AlertDialog(content: Text('dialog')),
          ),
      ],
    );
    expect(find.text('dialog'), findsOneWidget);

    // not dismissible yet
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('dialog'), findsOneWidget);

    _NavState.latest.setState(() => _NavState.latest.n = 1);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('dialog'), findsNothing);
  });

  testWidgets('a DialogPage barrier no longer dismisses once onPop is null', (
    tester,
  ) async {
    await _pumpNav(
      tester,
      (s) => [
        const NavPage(child: Scaffold(body: Text('home'))),
        if (s.shown)
          DialogPage(
            onPop: s.n == 1 ? null : () => s.setState(() => s.shown = false),
            child: const AlertDialog(content: Text('dialog')),
          ),
      ],
    );
    _NavState.latest.setState(() => _NavState.latest.n = 1);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('dialog'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a DialogPage barrier follows barrierDismissible', (
    tester,
  ) async {
    await _pumpNav(
      tester,
      (s) => [
        const NavPage(child: Scaffold(body: Text('home'))),
        if (s.shown)
          DialogPage(
            onPop: () => s.setState(() => s.shown = false),
            barrierDismissible: s.n == 1,
            child: const AlertDialog(content: Text('dialog')),
          ),
      ],
    );
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('dialog'), findsOneWidget);

    _NavState.latest.setState(() => _NavState.latest.n = 1);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('dialog'), findsNothing);
  });
}
