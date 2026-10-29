import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// a modal bottom sheet as a page of the stack
class _SheetPage extends Page<Object?> {
  const _SheetPage({super.key, super.canPop, required this.child});

  final Widget child;

  @override
  Route<Object?> createRoute(BuildContext context) => ModalBottomSheetRoute(
    settings: this,
    isScrollControlled: false,
    builder: (_) => child,
  );
}

class _Filters extends StatefulNavigator<Never> {
  const _Filters();

  @override
  _FiltersState createState() => _FiltersState();
}

class _FiltersState extends StatefulNavigatorState<_Filters, Never> {
  static int pops = 0;
  bool filtering = false;

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
        onPop: () {
          pops++;
          setState(() => filtering = false);
        },
        builder: (key, canPop, child) =>
            _SheetPage(key: key, canPop: canPop, child: child),
        child: const SizedBox(height: 200, child: Text('filters')),
      ),
  ];
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
}
