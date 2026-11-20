// TODO(tp): Move goldens in here so implementation can be shared with demo gallery?
import 'package:fdr_example/main.dart';
import 'package:fdr_example/src/examples/dynamic_pop_navigator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

final _gallery = find.text('Example selection');

Future<void> _open(WidgetTester tester, String example) async {
  await tester.tap(find.text(example));
  await tester.pumpAndSettle();
}

Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

void main() {
  for (final example in [
    'List Detail',
    'Dynamic back behavior',
    'Stateful Navigator',
    'Stateless Navigator',
    'Overlay Portal',
    'Tab shell',
  ]) {
    testWidgets('the gallery opens "$example"', (tester) async {
      await tester.pumpWidget(const MyApp());
      await _open(tester, example);
      expect(tester.takeException(), isNull);
      expect(_gallery.hitTestable(), findsNothing);
    });
  }

  testWidgets('the dynamic back example leaves the page once it may', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await _open(tester, 'Dynamic back behavior');
    expect(find.byType(PopToggle), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);

    // system back is refused while the page has no onPop
    await _systemBack(tester);
    expect(find.byType(PopToggle), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(PopToggle), findsNothing);
    expect(find.text('Dynamic pop parent'), findsOneWidget);

    // the example's first page goes back to the gallery
    await _systemBack(tester);
    expect(_gallery, findsOneWidget);
  });
}
