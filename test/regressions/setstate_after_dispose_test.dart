import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// What setState() and open() after dispose() do once `assert(mounted)` is
// compiled out (release, profile). `flutter test` cannot disable asserts,
// so the middle navigator overrides the public `mounted` getter to make the
// assert pass; everything after the assert is the library's code.

class _Store extends ChangeNotifier {
  bool get watched => hasListeners;
}

final _store = _Store();
final _showMid = ValueNotifier(true);
int _childInits = 0;
int _childDisposes = 0;
int _rootApplied = 0;
_MidState? _mid;

class _Root extends StatefulNavigator<String> {
  const _Root();
  @override
  _RootState createState() => _RootState();
}

class _RootState extends StatefulNavigatorState<_Root, String> {
  @override
  void initState() {
    super.initState();
    watch(_showMid);
  }

  @override
  void applyRoute(String route) => _rootApplied++;

  @override
  List<NavEntry<String>> build() => [
    const NavPage(child: Text('root')),
    if (_showMid.value) const _Mid(),
  ];
}

class _Mid extends StatefulNavigator<String> {
  const _Mid();
  @override
  _MidState createState() => _mid = _MidState();
}

class _MidState extends StatefulNavigatorState<_Mid, String> {
  bool releaseMode = false;
  int counter = 0;

  // stands in for "asserts disabled"
  @override
  bool get mounted => releaseMode || super.mounted;

  @override
  void applyRoute(String route) {}

  @override
  List<NavEntry<String>> build() => [const _Child()];
}

class _Child extends StatefulNavigator<Never> {
  const _Child();
  @override
  _ChildState createState() => _ChildState();
}

class _ChildState extends StatefulNavigatorState<_Child, Never> {
  @override
  void initState() {
    super.initState();
    _childInits++;
    watch(_store);
  }

  @override
  List<NavEntry<Never>> build() => [const NavPage(child: Text('child'))];

  @override
  void dispose() {
    _childDisposes++;
    super.dispose();
  }
}

void main() {
  testWidgets('setState and open after dispose do nothing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DeclarativeNavigator(navigator: _Root())),
    );
    expect(find.text('child'), findsOneWidget);
    expect(_childInits, 1);
    expect(_store.watched, isTrue);

    final mid = _mid!;
    _showMid.value = false;
    await tester.pumpAndSettle();
    expect(find.text('child'), findsNothing);
    expect(_childDisposes, 1);
    expect(_store.watched, isFalse);
    _rootApplied = 0;

    // a late async callback without a `mounted` check, asserts compiled out
    mid.releaseMode = true;
    mid.setState(() => mid.counter++);
    expect(_childInits, 1, reason: 'a child state was created on a dead tree');
    expect(_store.watched, isFalse, reason: 'leaked watch subscription');
    expect(mid.counter, 0);

    mid.open('elsewhere');
    expect(_rootApplied, 0, reason: 'a disposed navigator navigated');
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
