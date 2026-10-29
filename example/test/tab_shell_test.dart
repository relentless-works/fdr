import 'package:fdr/fdr.dart';
import 'package:fdr_example/src/examples/list_detail_navigator.dart';
import 'package:fdr_example/src/examples/tab_shell_navigator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tabs keep their stacks behind a persistent bar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: DeclarativeNavigator(navigator: TabShellNavigator())),
    );
    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    expect(find.byType(NumberDetailPage), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.text('Dynamic pop'));
    await tester.pumpAndSettle();
    expect(find.byType(NumberDetailPage), findsNothing);

    await tester.tap(find.text('List detail'));
    await tester.pumpAndSettle();
    expect(find.byType(NumberDetailPage), findsOneWidget);
  });
}
