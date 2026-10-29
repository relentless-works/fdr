import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// a build with statements: a sync* body instead of a list literal
class _Steps extends StatefulNavigator<Never> {
  const _Steps();

  @override
  _StepsState createState() => _StepsState();
}

class _StepsState extends StatefulNavigatorState<_Steps, Never> {
  int step = 0;

  @override
  Iterable<NavEntry<Never>> build() sync* {
    yield NavPage(
      child: TextButton(
        onPressed: () => setState(() => step = 2),
        child: const Text('start'),
      ),
    );
    for (var i = 1; i <= step; i++) {
      yield NavPage(
        onPop: () => setState(() => step = i - 1),
        child: Scaffold(appBar: AppBar(), body: Text('step $i')),
      );
    }
  }
}

void main() {
  testWidgets('build can be a sync* body', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DeclarativeNavigator(navigator: _Steps())),
    );
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    expect(find.text('step 2'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('step 1'), findsOneWidget);
  });
}
