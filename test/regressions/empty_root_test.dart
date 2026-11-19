import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'routes.dart';

class _Empty<R> extends StatelessNavigator<R> {
  const _Empty();

  @override
  List<NavEntry<R>> build() => [];
}

class _Toggle extends StatefulNavigator<Never> {
  const _Toggle();

  @override
  _ToggleState createState() => _ToggleState();
}

class _ToggleState extends StatefulNavigatorState<_Toggle, Never> {
  static late _ToggleState latest;
  bool show = true;

  @override
  void initState() {
    super.initState();
    latest = this;
  }

  @override
  List<NavEntry<Never>> build() => [
    if (show)
      NavPage(
        child: TextButton(
          onPressed: () => setState(() => show = false),
          child: const Text('hide'),
        ),
      ),
  ];
}

// the errors reported while [body] runs, as text
Future<String> errorsOf(Future<void> Function() body) async {
  final errors = <FlutterErrorDetails>[];
  final old = FlutterError.onError;
  FlutterError.onError = errors.add;
  await body();
  FlutterError.onError = old;
  return errors.map((e) => e.exceptionAsString()).join('\n---\n');
}

void expectFdrError(String text, String host, String navigator) {
  expect(text, contains('$host shows no page'));
  expect(text, contains(navigator));
  expect(text, isNot(contains('Navigator.pages must not be empty')));
  expect(text, isNot(contains('onGenerateRoute')));
}

void main() {
  testWidgets('an empty root build list is reported by fdr', (tester) async {
    final text = await errorsOf(
      () => tester.pumpWidget(
        const MaterialApp(
          home: DeclarativeNavigator(navigator: _Empty<Never>()),
        ),
      ),
    );
    expectFdrError(text, 'DeclarativeNavigator', '_Empty<Never>');
  });

  testWidgets('a root that becomes empty after a state change', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DeclarativeNavigator(navigator: _Toggle())),
    );
    expect(find.text('hide'), findsOneWidget);

    final text = await errorsOf(() async {
      await tester.tap(find.text('hide'));
      await tester.pump();
    });
    expectFdrError(text, 'DeclarativeNavigator', '_Toggle');

    // the pages come back
    _ToggleState.latest.setState(() => _ToggleState.latest.show = true);
    await tester.pumpAndSettle();
    expect(find.text('hide'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty root under the router is reported by fdr', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final router = FdrRouter<RR>(root: const _Empty<RR>(), fromUrl: RR.fromUrl);
    final text = await errorsOf(
      () => tester.pumpWidget(MaterialApp.router(routerConfig: router.config)),
    );
    expectFdrError(text, 'the router (RR)', '_Empty<RR>');
  });
}
