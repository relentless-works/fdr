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

  testWidgets('the order list filter lives in the query', (tester) async {
    await pumpShop(tester, '/orders?sorting=name&status=open');
    expect(find.text('Order #12'), findsOneWidget);
    expect(find.text('Order #1'), findsNothing);
    // sorted by name: #12 comes before #3
    expect(
      tester.getTopLeft(find.text('Order #12')).dy,
      lessThan(tester.getTopLeft(find.text('Order #3')).dy),
    );
  });

  testWidgets('an older spelling opens the order', (tester) async {
    await pumpShop(tester, '/order/7');
    await tester.pump(loadTime);
    await tester.pumpAndSettle();
    expect(find.text('Order #7 (v1)'), findsOneWidget);
  });

  testWidgets('a failed cancel shows a dialog that OK closes', (tester) async {
    await pumpShop(tester, '/orders/7');
    await tester.pump(loadTime);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel order'));
    await tester.pump(loadTime);
    await tester.pumpAndSettle();
    expect(find.text('Could not cancel'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Could not cancel'), findsNothing);
    expect(find.text('Order #7 (v1)'), findsOneWidget);
  });
}
