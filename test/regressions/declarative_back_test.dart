import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// --- the smallest app: two pages, no URLs --------------------------------

class AppNavigator extends StatefulNavigator<Never> {
  const AppNavigator();

  @override
  StatefulNavigatorState<AppNavigator, Never> createState() => _AppState();
}

class _AppState extends StatefulNavigatorState<AppNavigator, Never> {
  bool details = false;

  @override
  List<NavEntry<Never>> build() => [
    NavPage(
      child: Scaffold(
        appBar: AppBar(title: const Text('Home')),
        body: TextButton(
          onPressed: () => setState(() => details = true),
          child: const Text('open'),
        ),
      ),
    ),
    if (details)
      NavPage(
        onPop: () => setState(() => details = false),
        child: Scaffold(appBar: AppBar(title: const Text('Details'))),
      ),
  ];
}

void main() {
  testWidgets('Android back on the second page of a DeclarativeNavigator', (
    tester,
  ) async {
    final platformCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call);
        return null;
      },
    );
    await tester.pumpWidget(
      const MaterialApp(home: DeclarativeNavigator(navigator: AppNavigator())),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Details'), findsOneWidget);

    await tester.binding.handlePopRoute(); // Android system back
    await tester.pumpAndSettle();
    expect(find.text('Details'), findsNothing);
    expect(
      platformCalls.where((c) => c.method == 'SystemNavigator.pop'),
      isEmpty,
    );
  });
}
