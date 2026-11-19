import 'package:flutter_test/flutter_test.dart';

import '../routing/example_app.dart';
import 'model_browser.dart';

// Sequences of user actions against a model of the browser history. After
// each step: what the app shows, the address bar, the browser's entries.

void main() {
  testWidgets('a push after a reload and a browser forward gets a serial of '
      'its own', (tester) async {
    final s = BrowserSession(tester, '/orders');
    await s.load();
    await s.tap(open42);
    s.expectAt('/orders/42', entries: ['/orders', '/orders/42']);
    await s.traverse(-1);
    s.expectAt('/orders', entries: ['/orders', '/orders/42'], at: 0);

    // the reloaded app does not know the entry after its own
    await s.load();
    expect(s.router.provider.shadowHistory, ['/orders']);
    await s.traverse(1);
    s.expectAt('/orders/42', entries: ['/orders', '/orders/42']);

    const three = ['/orders', '/orders/42', '/orders/42/items/3'];
    await s.tap(item3);
    s.expectAt('/orders/42/items/3', entries: three);
    final serials = [for (final e in s.browser.entries) (e.state! as Map)['i']];
    expect(serials.toSet().length, 3, reason: 'serials: $serials');

    await s.traverse(-1);
    s.expectAt('/orders/42', entries: three, at: 1);
    await s.traverse(1);
    s.expectAt('/orders/42/items/3', entries: three);

    // closing both levels goes back two entries, to the list
    final orders = OrdersNavigatorState.latest!;
    orders.setState(() => orders.selectedId = null);
    await tester.pumpAndSettle();
    await s.arrive();
    expect(s.browser.deltas, [-2]);
    s.expectAt('/orders', entries: three, at: 0);
    expect(find.text('Order 42'), findsNothing);
  });

  group('while a back is in flight', () {
    const three = ['/orders', '/orders/42', '/orders/42/items/3'];

    Future<BrowserSession> atItem(WidgetTester tester) async {
      final s = BrowserSession(tester, '/orders');
      await s.load();
      await s.tap(open42);
      await s.tap(item3);
      s.expectAt('/orders/42/items/3', entries: three);
      return s;
    }

    testWidgets('a rebuild before a second back is not replayed after it', (
      tester,
    ) async {
      final s = await atItem(tester);
      await s.tapInFlight(back);
      expect(s.router.currentUrl, '/orders/42');
      final orders = OrdersNavigatorState.latest!;
      orders.setState(() => orders.counter++);
      await tester.pumpAndSettle();
      await s.tapInFlight(back);
      expect(s.router.currentUrl, '/orders');
      expect(s.router.provider.pendingBacks, 2);

      await s.arrive();
      expect(s.browser.deltas, [-1, -1]);
      s.expectAt('/orders', entries: three, at: 0);
    });

    testWidgets('a push before a back over two levels is not replayed', (
      tester,
    ) async {
      final s = await atItem(tester);
      await s.tapInFlight(back);
      await s.tapInFlight(item3);
      expect(s.router.currentUrl, '/orders/42/items/3');
      final orders = OrdersNavigatorState.latest!;
      orders.setState(() => orders.selectedId = null);
      await tester.pumpAndSettle();
      expect(s.router.currentUrl, '/orders');

      await s.arrive();
      expect(s.browser.deltas, [-1, -1]);
      s.expectAt('/orders', entries: three, at: 0);
    });

    testWidgets('opening a page and closing it again adds no entry', (
      tester,
    ) async {
      final s = BrowserSession(tester, '/orders');
      await s.load();
      await s.tap(open42);
      const two = ['/orders', '/orders/42'];
      s.expectAt('/orders/42', entries: two);

      await s.tapInFlight(back);
      await s.tapInFlight(open42);
      expect(s.router.currentUrl, '/orders/42');
      await s.tapInFlight(back);
      expect(s.router.currentUrl, '/orders');

      await s.arrive();
      expect(s.browser.deltas, [-1]);
      expect(s.browser.reports.where((r) => !r.$2), [('/orders/42', false)]);
      s.expectAt('/orders', entries: two, at: 0);

      // forward still leads to the order
      await s.traverse(1);
      s.expectAt('/orders/42', entries: two);
    });

    testWidgets('a push that stays is still reported after the back', (
      tester,
    ) async {
      final s = await atItem(tester);
      await s.tapInFlight(back);
      // item 3 again, then the list, then order 42: not back at the entry
      await s.tapInFlight(item3);
      await s.tapInFlight(back);
      await s.tapInFlight(item3);
      await s.arrive();
      s.expectAt('/orders/42/items/3', entries: three);
    });
  });
}
