import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Session extends ChangeNotifier {
  bool loggedIn = false;

  bool get watched => hasListeners;

  void logIn() {
    loggedIn = true;
    notifyListeners();
  }

  void logOut() {
    loggedIn = false;
    notifyListeners();
  }
}

class _AuthNavigator extends StatefulNavigator<Never> {
  const _AuthNavigator({required this.session});
  final _Session session;

  @override
  _AuthNavigatorState createState() => _AuthNavigatorState();
}

class _AuthNavigatorState
    extends StatefulNavigatorState<_AuthNavigator, Never> {
  @override
  void initState() {
    super.initState();
    watch(navigator.session);
  }

  @override
  List<DeclarativeNavigatable<Never>> build() => [
    if (navigator.session.loggedIn)
      const Text('home').page(onPop: null)
    else
      const Text('login').page(onPop: null),
  ];
}

void main() {
  testWidgets('a watched session drives the pages', (tester) async {
    final session = _Session();
    await tester.pumpWidget(
      MaterialApp(
        home: DeclarativeNavigator(navigator: _AuthNavigator(session: session)),
      ),
    );
    expect(find.text('login'), findsOneWidget);

    session.logIn();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);

    session.logOut();
    await tester.pumpAndSettle();
    expect(find.text('login'), findsOneWidget);
  });

  testWidgets('the subscription ends with the navigator', (tester) async {
    final session = _Session();
    await tester.pumpWidget(
      MaterialApp(
        home: DeclarativeNavigator(navigator: _AuthNavigator(session: session)),
      ),
    );
    expect(session.watched, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(session.watched, isFalse);
  });
}
