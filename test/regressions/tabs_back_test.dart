import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class App extends StatefulNavigator<Never> {
  const App({this.deep = const {}});
  final Set<int> deep;
  @override
  AppState createState() => AppState();
}

class AppState extends StatefulNavigatorState<App, Never> {
  static int pops = 0;
  int tab = 0;
  late final deep = {...navigator.deep};

  @override
  List<NavEntry<Never>> build() => [
    TabsPage(
      index: tab,
      tabs: [
        for (final i in [0, 1])
          Branch(
            name: 't$i',
            deep: deep.contains(i),
            onPop: () => setState(() {
              deep.remove(i);
              pops++;
            }),
          ),
      ],
      builder: (context, tabs) => Scaffold(
        body: IndexedStack(index: tab, children: tabs),
        bottomNavigationBar: Row(
          children: [
            TextButton(
              onPressed: () => setState(() => tab = 0),
              child: const Text('go0'),
            ),
            TextButton(
              onPressed: () => setState(() => tab = 1),
              child: const Text('go1'),
            ),
            TextButton(
              onPressed: () => setState(() => deep.add(tab)),
              child: const Text('deepen'),
            ),
          ],
        ),
      ),
    ),
  ];
}

class Branch extends StatelessNavigator<Never> {
  const Branch({required this.name, required this.deep, required this.onPop});
  final String name;
  final bool deep;
  final VoidCallback onPop;
  @override
  List<NavEntry<Never>> build() => [
    NavPage(child: Text('$name root')),
    if (deep) NavPage(onPop: onPop, child: Text('$name deep')),
  ];
}

void main() {
  late List<MethodCall> calls;

  Future<void> boot(WidgetTester tester, {Set<int> deep = const {}}) async {
    calls = [];
    AppState.pops = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DeclarativeNavigator(navigator: App(deep: deep)),
      ),
    );
    await tester.pumpAndSettle();
  }

  int exits() => calls.where((c) => c.method == 'SystemNavigator.pop').length;

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets('back at the root of the active tab leaves the app', (
    tester,
  ) async {
    await boot(tester);
    await back(tester);
    expect(exits(), 1);
  });

  testWidgets('a deep inactive tab does not keep back from leaving the app', (
    tester,
  ) async {
    await boot(tester, deep: {1});
    await back(tester);
    expect(AppState.pops, 0);
    expect(exits(), 1);
  });

  testWidgets('back leaves the app after switching away from a deep tab', (
    tester,
  ) async {
    await boot(tester);
    await tap(tester, 'go1');
    await tap(tester, 'deepen');
    expect(find.text('t1 deep'), findsOneWidget);
    await tap(tester, 'go0');
    await back(tester);
    expect(exits(), 1);
    expect(AppState.pops, 0);
    await back(tester);
    expect(exits(), 2);
  });

  testWidgets('back pops a deep active tab, then leaves the app', (
    tester,
  ) async {
    await boot(tester, deep: {1});
    await tap(tester, 'go1');
    await back(tester);
    expect(exits(), 0);
    expect(AppState.pops, 1);
    expect(find.text('t1 deep'), findsNothing);
    await back(tester);
    expect(exits(), 1);
  });

  testWidgets('back follows the active tab when both tabs are deep', (
    tester,
  ) async {
    await boot(tester, deep: {0, 1});
    await tap(tester, 'go1');
    await tap(tester, 'go0');
    await back(tester);
    expect(exits(), 0);
    expect(find.text('t0 deep'), findsNothing);
    await back(tester);
    expect(exits(), 1);
    await tap(tester, 'go1');
    await back(tester);
    expect(exits(), 1);
    expect(find.text('t1 deep'), findsNothing);
    expect(AppState.pops, 2);
    await back(tester);
    expect(exits(), 2);
  });
}
