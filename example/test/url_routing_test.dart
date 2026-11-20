import 'package:fdr/fdr.dart';
import 'package:fdr_example/url_routing/shop.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const loadTime = Duration(milliseconds: 600);

  Future<FdrRouter<ShopRoute>> pumpShop(WidgetTester tester, String url) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = url;
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final router = createShopRouter(ShopApi(delay: loadTime));
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
    return router;
  }

  testWidgets('a deep link through a failing order recovers on retry', (
    tester,
  ) async {
    final router = await pumpShop(tester, '/orders/13/items/2');
    expect(find.byType(LoadingPage), findsOneWidget);
    await tester.pump(loadTime);
    await tester.pump();
    expect(find.textContaining('could not be loaded'), findsOneWidget);
    // the error page is addressed by the URL the user is going to
    expect(router.currentUrl, '/orders/13/items/2');

    await tester.tap(find.text('Retry'));
    await tester.pump(loadTime);
    await tester.pump(loadTime);
    await tester.pumpAndSettle();
    expect(find.text('Item 2 of order #13'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(router.currentUrl, '/orders/13/items/2');
    expect(router.provider.shadowHistory, ['/orders/13/items/2']);
  });

  testWidgets('tabs keep their stacks', (tester) async {
    final router = await pumpShop(tester, '/orders/7');
    await tester.pump(loadTime);
    await tester.pumpAndSettle();
    expect(find.text('Order #7 (v1)'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/settings');
    await tester.tap(find.widgetWithText(ListTile, 'Profile'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfilePage), findsOneWidget);
    expect(router.currentUrl, '/settings/profile');

    await tester.tap(find.byIcon(Icons.receipt_long));
    await tester.pumpAndSettle();
    expect(find.text('Order #7 (v1)'), findsOneWidget);
    expect(router.currentUrl, '/orders/7');

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    expect(find.byType(ProfilePage), findsOneWidget);
    expect(router.currentUrl, '/settings/profile');
  });

  testWidgets('the order list filter lives in the query', (tester) async {
    final router = await pumpShop(tester, '/orders?sorting=name&status=open');
    expect(find.text('Order #12'), findsOneWidget);
    expect(find.text('Order #1'), findsNothing);
    // sorted by name: #12 comes before #3
    expect(
      tester.getTopLeft(find.text('Order #12')).dy,
      lessThan(tester.getTopLeft(find.text('Order #3')).dy),
    );
    expect(router.currentUrl, '/orders?sorting=name&status=open');

    // a new filter replaces the entry instead of adding one
    await tester.tap(find.byTooltip('Sort by date'));
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/orders?status=open');
    expect(
      tester.getTopLeft(find.text('Order #3')).dy,
      lessThan(tester.getTopLeft(find.text('Order #12')).dy),
    );
    expect(router.provider.shadowHistory, ['/orders?status=open']);
  });

  testWidgets('an older spelling opens the order', (tester) async {
    final router = await pumpShop(tester, '/order/7');
    await tester.pump(loadTime);
    await tester.pumpAndSettle();
    expect(find.text('Order #7 (v1)'), findsOneWidget);
    // and is corrected in place
    expect(router.currentUrl, '/orders/7');
    expect(router.provider.shadowHistory, ['/orders/7']);
  });

  testWidgets('a failed cancel shows a dialog that OK closes', (tester) async {
    final router = await pumpShop(tester, '/orders/7');
    await tester.pump(loadTime);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel order'));
    await tester.pump(loadTime);
    await tester.pumpAndSettle();
    expect(find.text('Could not cancel'), findsOneWidget);
    // the dialog has no URL
    expect(router.currentUrl, '/orders/7');

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Could not cancel'), findsNothing);
    expect(find.text('Order #7 (v1)'), findsOneWidget);
    expect(router.currentUrl, '/orders/7');
    expect(router.provider.shadowHistory, ['/orders/7']);
  });
}
