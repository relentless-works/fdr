import 'package:fdr/fdr.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

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
  late List<MethodCall> platformCalls;

  setUp(() => platformCalls = []);

  Future<void> pump(WidgetTester tester, Widget app) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call);
        return null;
      },
    );
    await tester.pumpWidget(app);
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Details'), findsOneWidget);
  }

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute(); // Android system back
    await tester.pumpAndSettle();
  }

  int exits() =>
      platformCalls.where((c) => c.method == 'SystemNavigator.pop').length;

  testWidgets('Android back on the second page of a DeclarativeNavigator', (
    tester,
  ) async {
    await pump(
      tester,
      const MaterialApp(home: DeclarativeNavigator(navigator: AppNavigator())),
    );
    await open(tester);
    await back(tester);
    expect(find.text('Details'), findsNothing);
    expect(exits(), 0);
  });

  // no enclosing route for the pop handler to register with
  testWidgets('Android back in a DeclarativeNavigator in MaterialApp.builder', (
    tester,
  ) async {
    await pump(
      tester,
      MaterialApp(
        builder: (_, _) =>
            const DeclarativeNavigator(navigator: AppNavigator()),
      ),
    );
    await open(tester);
    await back(tester);
    expect(find.text('Details'), findsNothing);
    expect(exits(), 0);
    // on the first page, back leaves the app
    await back(tester);
    expect(find.text('Home'), findsOneWidget);
    expect(exits(), 1);
  });

  testWidgets('Android back in a DeclarativeNavigator without an app', (
    tester,
  ) async {
    await pump(
      tester,
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(),
          child: Localizations(
            locale: const Locale('en'),
            delegates: const [
              DefaultMaterialLocalizations.delegate,
              DefaultWidgetsLocalizations.delegate,
            ],
            child: const DeclarativeNavigator(navigator: AppNavigator()),
          ),
        ),
      ),
    );
    await open(tester);
    await back(tester);
    expect(find.text('Details'), findsNothing);
    expect(exits(), 0);
  });
}
