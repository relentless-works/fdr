import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class Old extends StatefulNavigator<Never> {
  const Old();
  @override
  OldState createState() => OldState();
}

class OldState extends StatefulNavigatorState<Old, Never> {
  @override
  void dispose() {
    super.dispose();
    throw StateError('dispose boom');
  }

  @override
  List<NavEntry<Never>> build() => [const NavPage(child: Text('old'))];
}

class New extends StatefulNavigator<Never> {
  const New();
  @override
  NewState createState() => NewState();
}

class NewState extends StatefulNavigatorState<New, Never> {
  static final all = <NewState>[];

  @override
  void initState() {
    super.initState();
    all.add(this);
  }

  @override
  List<NavEntry<Never>> build() => [const NavPage(child: Text('new'))];
}

class Root extends StatefulNavigator<Never> {
  const Root();
  @override
  RootState createState() => RootState();
}

class RootState extends StatefulNavigatorState<Root, Never> {
  static late RootState latest;
  int step = 0;

  @override
  void initState() {
    super.initState();
    latest = this;
  }

  @override
  List<NavEntry<Never>> build() => [
    const NavPage(child: Text('home')),
    if (step == 0) const Old(),
    if (step == 1) const New(),
  ];
}

void main() {
  setUp(NewState.all.clear);

  testWidgets('a dispose that throws is reported, and the update that '
      'removed the navigator stands', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DeclarativeNavigator(navigator: Root())),
    );
    await tester.pumpAndSettle();
    expect(find.text('old'), findsOneWidget);

    final root = RootState.latest;
    root.setState(() => root.step = 1);
    expect(tester.takeException(), isStateError);
    await tester.pumpAndSettle();
    // the navigator created in that update is the one shown
    expect(find.text('old'), findsNothing);
    expect(find.text('new'), findsOneWidget);
    expect(NewState.all.single.mounted, isTrue);

    // and it is disposed when it goes
    root.setState(() => root.step = 2);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(NewState.all.single.mounted, isFalse);
    expect(find.text('home'), findsOneWidget);
  });
}
