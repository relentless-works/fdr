import 'package:fdr/fdr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

enum Step { home, edit, saved, other, stay }

class Other extends StatelessWidget {
  const Other({super.key});
  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(), body: const Text('other'));
}

class Flow extends StatefulNavigator<Never> {
  const Flow({required this.onPop});
  final Step Function(Step step) onPop;

  @override
  FlowState createState() => FlowState();
}

class FlowState extends StatefulNavigatorState<Flow, Never> {
  Step step = Step.home;

  @override
  List<NavEntry<Never>> build() => [
    NavPage(
      child: TextButton(
        onPressed: () => setState(() => step = Step.edit),
        child: const Text('start'),
      ),
    ),
    if (step == Step.edit || step == Step.stay)
      NavPage(
        onPop: () => setState(() => step = navigator.onPop(step)),
        child: Scaffold(appBar: AppBar(), body: const Text('edit')),
      ),
    if (step == Step.saved)
      DialogPage(
        onPop: () => setState(() => step = Step.home),
        child: const Text('saved!'),
      ),
    if (step == Step.other)
      NavPage(
        onPop: () => setState(() => step = Step.home),
        child: const Other(),
      ),
  ];
}

Future<List<String>> popEdit(WidgetTester tester, Flow flow) async {
  final errors = <String>[];
  final old = FlutterError.onError;
  FlutterError.onError = (details) => errors.add('${details.exception}');
  addTearDown(() => FlutterError.onError = old);
  await tester.pumpWidget(
    MaterialApp(home: DeclarativeNavigator(navigator: flow)),
  );
  await tester.tap(find.text('start'));
  await tester.pumpAndSettle();
  expect(find.text('edit'), findsOneWidget);
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
  FlutterError.onError = old;
  return errors;
}

void main() {
  testWidgets('onPop that puts a dialog in the popped page\'s place', (
    tester,
  ) async {
    final errors = await popEdit(tester, Flow(onPop: (_) => Step.saved));
    expect(find.text('saved!'), findsOneWidget);
    expect(find.text('edit'), findsNothing);
    expect(errors, isEmpty);
  });

  testWidgets('onPop that puts another page in the popped page\'s place', (
    tester,
  ) async {
    final errors = await popEdit(tester, Flow(onPop: (_) => Step.other));
    expect(find.text('other'), findsOneWidget);
    expect(find.text('edit'), findsNothing);
    expect(errors, isEmpty);
  });

  testWidgets('onPop that keeps the page is still reported', (tester) async {
    final errors = await popEdit(tester, Flow(onPop: (_) => Step.stay));
    expect(errors, [contains('ran but the state still builds the page')]);
  });

  testWidgets('onPop that changes nothing is still reported', (tester) async {
    final errors = await popEdit(tester, Flow(onPop: (step) => step));
    expect(errors, [contains('ran but the state still builds the page')]);
  });
}
