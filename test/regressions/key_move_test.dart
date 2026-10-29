import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class Counter extends StatefulNavigator<Never> {
  const Counter({super.key});

  @override
  StatefulNavigatorState<Counter, Never> createState() => _CounterState();
}

class _CounterState extends StatefulNavigatorState<Counter, Never> {
  int count = 0;

  @override
  List<NavEntry<Never>> build() => [
    NavPage(
      child: Scaffold(
        body: TextButton(
          onPressed: () => setState(() => count++),
          child: Text('count $count'),
        ),
      ),
    ),
  ];
}

class Root extends StatefulNavigator<Never> {
  const Root();

  @override
  StatefulNavigatorState<Root, Never> createState() => RootState();
}

class RootState extends StatefulNavigatorState<Root, Never> {
  static late RootState latest;
  bool notice = true;

  @override
  void initState() {
    super.initState();
    latest = this;
  }

  void dismiss() => setState(() => notice = false);

  @override
  List<NavEntry<Never>> build() => [
    const NavPage(child: Text('home')),
    if (notice) const NavPage(child: Text('notice')),
    const Counter(key: ValueKey('counter')),
  ];
}

void main() {
  testWidgets('a keyed navigator keeps its state when an entry below goes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: DeclarativeNavigator(navigator: Root())),
    );
    await tester.tap(find.text('count 0'));
    await tester.pumpAndSettle();
    expect(find.text('count 1'), findsOneWidget);
    RootState.latest.dismiss();
    await tester.pumpAndSettle();
    expect(find.text('count 1'), findsOneWidget);
  });
}
