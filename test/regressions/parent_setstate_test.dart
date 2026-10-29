import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class Wizard extends StatefulNavigator<Never> {
  const Wizard({required this.onStarted});
  final VoidCallback onStarted;
  @override
  WizardState createState() => WizardState();
}

class WizardState extends StatefulNavigatorState<Wizard, Never> {
  static int created = 0;
  static int disposed = 0;
  @override
  void initState() {
    super.initState();
    created++;
    navigator.onStarted();
  }

  @override
  void dispose() {
    disposed++;
    super.dispose();
  }

  @override
  List<NavEntry<Never>> build() => [const NavPage(child: Text('wizard'))];
}

class Root extends StatefulNavigator<Never> {
  const Root();
  @override
  RootState createState() => RootState();
}

class RootState extends StatefulNavigatorState<Root, Never> {
  static late RootState latest;
  bool wizard = false;
  int starts = 0;
  @override
  void initState() {
    super.initState();
    latest = this;
  }

  @override
  List<NavEntry<Never>> build() => [
    Text('starts $starts').let((t) => NavPage(child: t)),
    if (wizard)
      Wizard(
        onStarted: () {
          // the parent shows a hint once the wizard started
          if (starts < 3) setState(() => starts++);
        },
      ),
  ];
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

void main() {
  testWidgets('a child that notifies its parent in initState', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DeclarativeNavigator(navigator: Root())),
    );
    final root = RootState.latest;
    root.setState(() => root.wizard = true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(WizardState.created - WizardState.disposed, 1);
    expect(WizardState.created, 1);
  });
}
