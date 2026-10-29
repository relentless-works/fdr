import 'package:fdr_example/url_routing/shop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const loadTime = Duration(milliseconds: 600);

  Future<void> pumpShop(WidgetTester tester, String url) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = url;
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final router = createShopRouter(ShopApi(delay: loadTime));
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
  }

  testWidgets('a deep link through a failing order recovers on retry', (
    tester,
  ) async {
    await pumpShop(tester, '/orders/13/items/2');
    expect(find.byType(LoadingPage), findsOneWidget);
    await tester.pump(loadTime);
    await tester.pump();
    expect(find.textContaining('could not be loaded'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump(loadTime);
    await tester.pump(loadTime);
    await tester.pumpAndSettle();
    expect(find.text('Item 2 of order #13'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('tabs keep their stacks', (tester) async {
    await pumpShop(tester, '/orders/7');
    await tester.pump(loadTime);
    await tester.pumpAndSettle();
    expect(find.text('Order #7 (v1)'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsWidgets);

    await tester.tap(find.byIcon(Icons.receipt_long));
    await tester.pumpAndSettle();
    expect(find.text('Order #7 (v1)'), findsOneWidget);
  });
}
