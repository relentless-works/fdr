import 'dart:async';

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
  List<NavEntry<Never>> build() => [
    if (navigator.session.loggedIn)
      const NavPage(child: Text('home'))
    else
      const NavPage(child: Text('login')),
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

  testWidgets('a listened stream drives the pages until disposal', (
    tester,
  ) async {
    final session = _StreamSession();
    await tester.pumpWidget(
      MaterialApp(
        home: DeclarativeNavigator(
          navigator: _StreamAuthNavigator(session: session),
        ),
      ),
    );
    expect(find.text('login'), findsOneWidget);

    session.logIn();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    expect(session.controller.hasListener, isFalse);
  });
}

// a bloc-like store: state plus a stream of changes
class _StreamSession {
  final controller = StreamController<bool>.broadcast(sync: true);
  bool loggedIn = false;

  void logIn() {
    loggedIn = true;
    controller.add(loggedIn);
  }
}

class _StreamAuthNavigator extends StatefulNavigator<Never> {
  const _StreamAuthNavigator({required this.session});
  final _StreamSession session;

  @override
  _StreamAuthNavigatorState createState() => _StreamAuthNavigatorState();
}

class _StreamAuthNavigatorState
    extends StatefulNavigatorState<_StreamAuthNavigator, Never> {
  @override
  void initState() {
    super.initState();
    listen(navigator.session.controller.stream);
  }

  @override
  List<NavEntry<Never>> build() => [
    NavPage(child: Text(navigator.session.loggedIn ? 'home' : 'login')),
  ];
}
