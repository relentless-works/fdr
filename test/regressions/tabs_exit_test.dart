import 'package:fdr/fdr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

final lengths = <int>[];

class Root extends StatefulNavigator<Never> {
  const Root();
  @override
  RootState createState() => RootState();
}

class RootState extends StatefulNavigatorState<Root, Never> {
  static late RootState latest;
  bool tabs = true;
  @override
  void initState() {
    super.initState();
    latest = this;
  }

  @override
  List<NavEntry<Never>> build() => [
    const NavPage(child: Scaffold(body: Text('home'))),
    if (tabs)
      TabsPage(
        index: 1,
        tabs: const [
          NavPage(child: Text('tab a')),
          NavPage(child: Text('tab b')),
        ],
        builder: (context, tabs) {
          MediaQuery.sizeOf(context);
          lengths.add(tabs.length);
          return Scaffold(body: IndexedStack(index: 1, children: tabs));
        },
      ),
  ];
}

void main() {
  testWidgets('a removed TabsPage still shows its tabs while it animates out', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: DeclarativeNavigator(navigator: Root())),
    );
    await tester.pumpAndSettle();
    expect(find.text('tab b'), findsOneWidget);
    lengths.clear();

    final root = RootState.latest;
    root.setState(() => root.tabs = false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('tab b'), findsOneWidget);

    // anything the builder depends on changes during the exit transition
    tester.view.physicalSize = const Size(900, 700);
    addTearDown(tester.view.reset);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(lengths, isNotEmpty);
    expect(lengths.where((length) => length != 2), isEmpty);
    expect(find.text('tab b'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('tab b'), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });
}
