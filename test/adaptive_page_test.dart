import 'package:fdr/fdr.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _OnePage extends StatelessNavigator<Never> {
  const _OnePage();

  @override
  List<DeclarativeNavigatable<Never>> build() => [
    const Text('page').page(onPop: null),
  ];
}

void main() {
  for (final (platform, route) in [
    (TargetPlatform.android, isA<MaterialRouteTransitionMixin<Object?>>()),
    (TargetPlatform.windows, isA<MaterialRouteTransitionMixin<Object?>>()),
    (TargetPlatform.iOS, isA<CupertinoRouteTransitionMixin<Object?>>()),
    (TargetPlatform.macOS, isA<CupertinoRouteTransitionMixin<Object?>>()),
  ]) {
    testWidgets('the Theme platform $platform picks the route', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: const DeclarativeNavigator(navigator: _OnePage()),
        ),
      );
      expect(ModalRoute.of(tester.element(find.text('page'))), route);
    });
  }
}
