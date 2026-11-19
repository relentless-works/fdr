import 'dart:async';

import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'routes.dart';

final builds = <String, int>{};
void _count(String name) => builds[name] = (builds[name] ?? 0) + 1;

// an edit that makes the root's build throw
var throwInBuild = false;
var siblingReassembles = 0;

class _Root<R> extends StatefulNavigator<R> {
  const _Root({this.tabs = false});
  final bool tabs;
  @override
  _RootState<R> createState() => _RootState<R>();
}

class _RootState<R> extends StatefulNavigatorState<_Root<R>, R> {
  @override
  void applyRoute(R route) {}

  @override
  List<NavEntry<R>> build() {
    _count('root');
    if (throwInBuild) throw StateError('build boom');
    if (navigator.tabs) {
      return [
        TabsPage(
          index: 0,
          tabs: const [_Mid(), _Leaf()],
          builder: (context, tabs) =>
              Scaffold(body: IndexedStack(children: tabs)),
        ),
      ];
    }
    return [const NavPage(child: Text('root')), const _Mid()];
  }
}

class _Mid extends StatefulNavigator<Never> {
  const _Mid();
  @override
  _MidState createState() => _MidState();
}

class _MidState extends StatefulNavigatorState<_Mid, Never> {
  @override
  List<NavEntry<Never>> build() {
    _count('mid');
    return [const NavPage(child: Text('mid')), const _Leaf()];
  }
}

class _Leaf extends StatefulNavigator<Never> {
  const _Leaf();
  @override
  _LeafState createState() => _LeafState();
}

class _LeafState extends StatefulNavigatorState<_Leaf, Never> {
  int taps = 0;

  @override
  List<NavEntry<Never>> build() {
    _count('leaf');
    return [
      NavPage(
        child: TextButton(
          onPressed: () => setState(() => taps++),
          child: Text('leaf $taps'),
        ),
      ),
    ];
  }
}

// a widget next to the navigators, reassembled after them
class _Sibling extends StatefulWidget {
  const _Sibling();
  @override
  State<_Sibling> createState() => _SiblingState();
}

class _SiblingState extends State<_Sibling> {
  @override
  void reassemble() {
    super.reassemble();
    siblingReassembles++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox(height: 10);
}

Future<void> hotReload(WidgetTester tester) async {
  builds.clear();
  // performReassemble awaits endOfFrame; do not await it before pumping
  unawaited(tester.binding.reassembleApplication());
  await tester.pump();
  await tester.pump();
}

// A hot reload after an edit that makes the root's build throw, and one
// after the edit is fixed.
Future<void> expectReloadReportsBuildError(WidgetTester tester) async {
  expect(find.text('leaf 0'), findsOneWidget);
  throwInBuild = true;
  addTearDown(() => throwInBuild = false);
  // a throw out of State.reassemble would end here, with the rest of the
  // app not reassembled and the binding's events left locked
  await hotReload(tester);
  expect(tester.takeException(), isStateError);
  expect(siblingReassembles, 1);
  // ignore: invalid_use_of_protected_member
  expect(tester.binding.locked, isFalse);
  // the navigators keep what they showed
  expect(find.text('leaf 0'), findsOneWidget);

  throwInBuild = false;
  await hotReload(tester);
  expect(tester.takeException(), isNull);
  expect(builds, {'root': 1, 'mid': 1, 'leaf': 1});
  expect(siblingReassembles, 2);
}

void main() {
  setUp(() {
    builds.clear();
    siblingReassembles = 0;
  });

  testWidgets('one host: hot reload builds each navigator once', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: DeclarativeNavigator(navigator: _Root<Never>())),
    );
    await tester.pumpAndSettle();
    expect(builds, {'root': 1, 'mid': 1, 'leaf': 1});
    await tester.tap(find.text('leaf 0'));
    await tester.pump();

    await hotReload(tester);
    expect(builds, {'root': 1, 'mid': 1, 'leaf': 1});
    // state is kept
    expect(find.text('leaf 1'), findsOneWidget);
  });

  testWidgets('two hosts: hot reload builds each navigator once', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            Expanded(child: DeclarativeNavigator(navigator: _Root<Never>())),
            Expanded(child: DeclarativeNavigator(navigator: _Root<Never>())),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(builds, {'root': 2, 'mid': 2, 'leaf': 2});

    await hotReload(tester);
    expect(builds, {'root': 2, 'mid': 2, 'leaf': 2});
  });

  testWidgets('tabs: hot reload builds the navigators of every tab once', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DeclarativeNavigator(navigator: _Root<Never>(tabs: true)),
      ),
    );
    await tester.pumpAndSettle();
    // the leaf in the first tab's Mid, and the one that is the second tab
    expect(builds, {'root': 1, 'mid': 1, 'leaf': 2});

    await hotReload(tester);
    expect(builds, {'root': 1, 'mid': 1, 'leaf': 2});
  });

  testWidgets('router: hot reload builds each navigator once', (tester) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final router = FdrRouter<RR>(root: const _Root<RR>(), fromUrl: RR.fromUrl);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
    await tester.pumpAndSettle();

    await hotReload(tester);
    expect(builds, {'root': 1, 'mid': 1, 'leaf': 1});
    expect(tester.takeException(), isNull);
  });

  testWidgets('DeclarativeNavigator: a build that throws on hot reload is '
      'reported, and the rest of the app is reassembled', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            Expanded(child: DeclarativeNavigator(navigator: _Root<Never>())),
            _Sibling(),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectReloadReportsBuildError(tester);
  });

  testWidgets('router: a build that throws on hot reload is reported, and '
      'the rest of the app is reassembled', (tester) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final router = FdrRouter<RR>(root: const _Root<RR>(), fromUrl: RR.fromUrl);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router.config,
        builder: (context, child) => Column(
          children: [
            Expanded(child: child!),
            const _Sibling(),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectReloadReportsBuildError(tester);
  });
}
