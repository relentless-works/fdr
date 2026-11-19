import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// a modal bottom sheet as a page of the stack; the route reads the child of
// the current page, which a rebuild replaces
class _SheetPage extends Page<Object?> {
  const _SheetPage({super.key, super.canPop, required this.child});

  final Widget child;

  @override
  Route<Object?> createRoute(BuildContext context) => ModalBottomSheetRoute(
    settings: this,
    isScrollControlled: false,
    builder: (context) => (ModalRoute.settingsOf(context)! as _SheetPage).child,
  );
}

Page<Object?> _passesOn(LocalKey key, bool canPop, Widget child) =>
    _SheetPage(key: key, canPop: canPop, child: child);

class _Filters extends StatefulNavigator<Never> {
  const _Filters({this.poppable = true, this.builder = _passesOn});

  final bool poppable;
  final CustomPageBuilder builder;

  @override
  _FiltersState createState() => _FiltersState();
}

class _FiltersState extends StatefulNavigatorState<_Filters, Never> {
  static int pops = 0;
  static late _FiltersState latest;
  bool filtering = false;
  String label = 'filters';

  @override
  List<NavEntry<Never>> build() => [
    NavPage(
      child: Scaffold(
        body: TextButton(
          onPressed: () => setState(() => filtering = true),
          child: const Text('filter'),
        ),
      ),
    ),
    if (filtering)
      CustomPage(
        onPop: navigator.poppable
            ? () {
                pops++;
                setState(() => filtering = false);
              }
            : null,
        builder: navigator.builder,
        child: SizedBox(height: 200, child: Text(label)),
      ),
  ];

  @override
  void initState() {
    super.initState();
    latest = this;
  }
}

void main() {
  testWidgets('a bottom sheet page goes through onPop', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DeclarativeNavigator(navigator: _Filters())),
    );
    await tester.tap(find.text('filter'));
    await tester.pumpAndSettle();
    expect(find.text('filters'), findsOneWidget);

    // a tap on the barrier above the sheet
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.text('filters'), findsNothing);
    expect(_FiltersState.pops, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a bottom sheet page shows the content of the latest build', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: DeclarativeNavigator(navigator: _Filters())),
    );
    await tester.tap(find.text('filter'));
    await tester.pumpAndSettle();
    _FiltersState.latest.setState(() => _FiltersState.latest.label = 'two');
    await tester.pumpAndSettle();
    expect(find.text('two'), findsOneWidget);
  });

  testWidgets('a builder that does not pass the key on is an error', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DeclarativeNavigator(
          navigator: _Filters(
            builder: (key, canPop, child) =>
                _SheetPage(canPop: canPop, child: child),
          ),
        ),
      ),
    );
    await tester.tap(find.text('filter'));
    await tester.pump();
    expect(
      tester.takeException(),
      isA<AssertionError>().having(
        (e) => e.message,
        'message',
        contains('has to pass `key` on'),
      ),
    );
  });

  testWidgets('a builder that does not pass canPop on is an error', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DeclarativeNavigator(
          navigator: _Filters(
            poppable: false,
            builder: (key, canPop, child) => _SheetPage(key: key, child: child),
          ),
        ),
      ),
    );
    await tester.tap(find.text('filter'));
    await tester.pump();
    expect(
      tester.takeException(),
      isA<AssertionError>().having(
        (e) => e.message,
        'message',
        contains('has to pass `canPop` on'),
      ),
    );
  });

  testWidgets('a builder may keep a page from being popped', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DeclarativeNavigator(
          navigator: _Filters(
            builder: (key, canPop, child) =>
                _SheetPage(key: key, canPop: false, child: child),
          ),
        ),
      ),
    );
    await tester.tap(find.text('filter'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('filters'), findsOneWidget);
  });
}
