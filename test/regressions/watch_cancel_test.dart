import 'dart:async';

import 'package:fdr/fdr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _Session extends ChangeNotifier {
  _Session(this.name);
  final String name;
  bool get watched => hasListeners;
  void ping() => notifyListeners();
}

class _Nav extends StatefulNavigator<Never> {
  const _Nav({required this.session});
  final _Session session;

  @override
  _NavState createState() => _NavState();
}

class _NavState extends StatefulNavigatorState<_Nav, Never> {
  static late _NavState latest;
  int builds = 0;
  late VoidCallback unwatch;

  @override
  void initState() {
    super.initState();
    latest = this;
    unwatch = watch(navigator.session);
  }

  @override
  void didUpdateNavigator(_Nav oldNavigator) {
    super.didUpdateNavigator(oldNavigator);
    if (oldNavigator.session != navigator.session) {
      unwatch();
      unwatch = watch(navigator.session);
    }
  }

  @override
  List<NavEntry<Never>> build() {
    builds++;
    return [NavPage(child: Text(navigator.session.name))];
  }
}

class _StreamNav extends StatefulNavigator<Never> {
  const _StreamNav({required this.stream, this.onError});
  final Stream<Object?> stream;
  final void Function(Object error, StackTrace stackTrace)? onError;

  @override
  _StreamNavState createState() => _StreamNavState();
}

class _StreamNavState extends StatefulNavigatorState<_StreamNav, Never> {
  static late _StreamNavState latest;
  int builds = 0;
  late VoidCallback cancel;

  @override
  void initState() {
    super.initState();
    latest = this;
    cancel = listen(navigator.stream, onError: navigator.onError);
  }

  @override
  List<NavEntry<Never>> build() {
    builds++;
    return [const NavPage(child: Text('page'))];
  }
}

Widget _app(StatefulNavigator<Never> navigator) =>
    MaterialApp(home: DeclarativeNavigator(navigator: navigator));

void main() {
  testWidgets('a replaced session can be unwatched', (tester) async {
    final a = _Session('a');
    final b = _Session('b');
    await tester.pumpWidget(_app(_Nav(session: a)));
    await tester.pumpWidget(_app(_Nav(session: b)));
    expect(find.text('b'), findsOneWidget);
    expect(a.watched, isFalse);
    expect(b.watched, isTrue);

    final builds = _NavState.latest.builds;
    a.ping();
    await tester.pump();
    expect(_NavState.latest.builds, builds);
    b.ping();
    await tester.pump();
    expect(_NavState.latest.builds, builds + 1);
  });

  testWidgets('cancelling twice or after dispose does nothing', (tester) async {
    final a = _Session('a');
    await tester.pumpWidget(_app(_Nav(session: a)));
    final state = _NavState.latest;
    final unwatch = state.unwatch;
    unwatch();
    unwatch();
    expect(a.watched, isFalse);
    // a second watch of the same listenable is independent of the first
    state.unwatch = state.watch(a);
    unwatch();
    expect(a.watched, isTrue);

    await tester.pumpWidget(const SizedBox());
    expect(a.watched, isFalse);
    state.unwatch();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a cancelled stream no longer rebuilds', (tester) async {
    final controller = StreamController<Object?>.broadcast(sync: true);
    await tester.pumpWidget(_app(_StreamNav(stream: controller.stream)));
    final state = _StreamNavState.latest;
    controller.add(1);
    expect(state.builds, 2);

    state.cancel();
    expect(controller.hasListener, isFalse);
    controller.add(2);
    expect(state.builds, 2);

    await tester.pumpWidget(const SizedBox());
    state.cancel();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stream error goes to onError', (tester) async {
    final controller = StreamController<Object?>.broadcast(sync: true);
    final errors = <Object>[];
    await tester.pumpWidget(
      _app(
        _StreamNav(
          stream: controller.stream,
          onError: (error, _) => errors.add(error),
        ),
      ),
    );
    final error = StateError('repository failed');
    controller.addError(error);
    await tester.pump();
    expect(errors, [error]);
    expect(tester.takeException(), isNull);

    // the subscription stays
    controller.add(1);
    expect(_StreamNavState.latest.builds, 2);
  });
}
