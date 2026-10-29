import 'package:fdr/fdr.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _OnePage extends StatelessNavigator<Never> {
  const _OnePage(this.page);
  final NavPage<Never> page;

  @override
  List<NavEntry<Never>> build() => [page];
}

final _material = isA<MaterialRouteTransitionMixin<Object?>>();
final _cupertino = isA<CupertinoRouteTransitionMixin<Object?>>();

void main() {
  Future<Route<Object?>?> routeOf(
    WidgetTester tester,
    TargetPlatform platform,
    NavPage<Never> page,
  ) async {
    // a fresh Navigator: an existing route keeps its type
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: platform),
        home: DeclarativeNavigator(navigator: _OnePage(page)),
      ),
    );
    return ModalRoute.of(tester.element(find.text('page')));
  }

  for (final (platform, route) in [
    (TargetPlatform.android, _material),
    (TargetPlatform.windows, _material),
    (TargetPlatform.iOS, _cupertino),
    (TargetPlatform.macOS, _cupertino),
  ]) {
    testWidgets('NavPage picks the route from the Theme platform $platform', (
      tester,
    ) async {
      const page = NavPage<Never>(child: Text('page'));
      expect(await routeOf(tester, platform, page), route);
    });
  }

  testWidgets('NavPage.material and NavPage.cupertino ignore the platform', (
    tester,
  ) async {
    const material = NavPage<Never>.material(child: Text('page'));
    expect(await routeOf(tester, TargetPlatform.iOS, material), _material);
    const cupertino = NavPage<Never>.cupertino(child: Text('page'));
    expect(
      await routeOf(tester, TargetPlatform.android, cupertino),
      _cupertino,
    );
  });
}
