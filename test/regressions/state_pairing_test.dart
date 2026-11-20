import 'package:fdr/fdr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class Leaf extends StatefulNavigator<Never> {
  const Leaf();

  @override
  LeafState createState() => LeafState();
}

class LeafState extends StatefulNavigatorState<Leaf, Never> {
  @override
  List<NavEntry<Never>> build() => [const NavPage(child: Text('leaf'))];
}

// copied from Leaf, createState not adapted: compiles, because both have
// the same route type
class Copy extends StatefulNavigator<Never> {
  const Copy();

  @override
  LeafState createState() => LeafState();
}

void main() {
  testWidgets('a createState that returns another navigator\'s state', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: DeclarativeNavigator(navigator: Copy())),
    );
    expect(
      tester.takeException(),
      isA<FlutterError>().having(
        (e) => e.message,
        'message',
        contains('Copy.createState() returned LeafState, the state of Leaf'),
      ),
    );
  });
}
