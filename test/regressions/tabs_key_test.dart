import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TabsPage<Never> tabs(String name) => TabsPage(
  index: 0,
  tabs: [NavPage(child: Text('$name tab'))],
  builder: (context, tabs) => Scaffold(body: IndexedStack(children: tabs)),
);

class Picker extends StatefulNavigator<Never> {
  const Picker();
  @override
  PickerState createState() => PickerState();
}

class PickerState extends StatefulNavigatorState<Picker, Never> {
  @override
  List<NavEntry<Never>> build() => [tabs('picker')];
}

class Root extends StatefulNavigator<Never> {
  const Root();
  @override
  RootState createState() => RootState();
}

class RootState extends StatefulNavigatorState<Root, Never> {
  static late RootState latest;
  bool picking = false;
  @override
  void initState() {
    super.initState();
    latest = this;
  }

  @override
  List<NavEntry<Never>> build() => [
    tabs('main'),
    if (picking)
      NestedNavigator(
        onPop: () => setState(() => picking = false),
        child: const Picker(),
      ),
  ];
}

void main() {
  testWidgets('two tabs pages in one stack', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DeclarativeNavigator(navigator: Root())),
    );
    final root = RootState.latest;
    root.setState(() => root.picking = true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('picker tab'), findsOneWidget);
  });
}
