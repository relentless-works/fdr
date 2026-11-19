import 'package:fdr/fdr.dart';
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

  testWidgets('a requested pop that closes two levels goes back two entries', (
    tester,
  ) async {
    const three = ['/orders', '/orders/42', '/orders/42/items/3'];
    final s = BrowserSession(tester, '/orders');
    await s.load();
    await s.tap(open42);
    await s.tap(item3);
    final orders = OrdersNavigatorState.latest!;
    orders.setState(() => orders.selectedId = null, history: HistoryAction.pop);
    await tester.pumpAndSettle();
    await s.arrive();
    expect(s.browser.deltas, [-2]);
    s.expectAt('/orders', entries: three, at: 0);

    // one that closes one level goes back one
    await s.traverse(2);
    s.expectAt('/orders/42/items/3', entries: three);
    orders.setState(
      () => orders.selectedItem = null,
      history: HistoryAction.pop,
    );
    await tester.pumpAndSettle();
    await s.arrive();
    expect(s.browser.deltas, [-2, -1]);
    s.expectAt('/orders/42', entries: three, at: 1);
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

  group('a back the browser does not deliver', () {
    testWidgets('does not stop later navigation from being reported', (
      tester,
    ) async {
      final s = BrowserSession(tester, '/orders');
      await s.load();
      await s.tap(open42);
      await s.tapInFlight(back);
      // the browser does nothing
      s.browser.pending.clear();
      await s.tapInFlight(tabSettings);
      await s.tapInFlight(profile);
      expect(s.router.currentUrl, '/settings/profile');
      expect(s.browser.bar, '/orders/42');

      await tester.pump(lost);
      s.expectAt(
        '/settings/profile',
        entries: ['/orders', '/orders/42', '/settings/profile'],
      );

      // and reporting goes on as usual
      await s.tap(back);
      s.expectAt(
        '/settings',
        entries: ['/orders', '/orders/42', '/settings/profile', '/settings'],
      );
    });

    testWidgets('past the start of the history falls back to a push', (
      tester,
    ) async {
      final s = BrowserSession(tester, '/orders');
      await s.load();
      await s.tap(open42);
      // the browser dropped its oldest entry, as it does at its limit
      s.browser
        ..entries.removeAt(0)
        ..index = 0;
      await s.tap(back);
      expect(s.browser.deltas, [-1]);
      expect(s.router.currentUrl, '/orders');
      expect(s.browser.bar, '/orders/42');

      await tester.pump(lost);
      expect(s.router.currentUrl, '/orders');
      expect(s.browser.bar, '/orders');
      expect(s.browser.urls, ['/orders/42', '/orders']);
      expect(s.router.provider.pendingBacks, 0);

      // browser back shows the order again
      await s.traverse(-1);
      expect(s.router.currentUrl, '/orders/42');
      expect(find.text('Order 42'), findsOneWidget);
    });

    testWidgets('but carried out adds no entry', (tester) async {
      final s = BrowserSession(tester, '/orders');
      await s.load();
      await s.tap(open42);
      await s.tapInFlight(back);
      // the entry changes, but the app never hears of it
      s.browser
        ..pending.clear()
        ..index = 0;
      await tester.pump(lost);
      s.expectAt('/orders', entries: ['/orders', '/orders/42'], at: 0);
      expect(s.browser.reports.where((r) => !r.$2), [('/orders/42', false)]);

      await s.tap(open42);
      s.expectAt('/orders/42', entries: ['/orders', '/orders/42']);
    });

    testWidgets('is still awaited within the time it may take', (tester) async {
      final s = BrowserSession(tester, '/orders');
      await s.load();
      await s.tap(open42);
      await s.tapInFlight(back);
      await tester.pump(lost - const Duration(seconds: 1));
      expect(s.router.provider.pendingBacks, 1);
      await s.arrive();
      await tester.pump(lost);
      s.expectAt('/orders', entries: ['/orders', '/orders/42'], at: 0);
      expect(s.browser.reports.where((r) => !r.$2), [('/orders/42', false)]);
    });
  });

  group('a URL typed into the address bar', () {
    Future<BrowserSession> atOrder(WidgetTester tester) async {
      final s = BrowserSession(tester, '/orders');
      await s.load();
      await s.tap(open42);
      s.expectAt('/orders/42', entries: ['/orders', '/orders/42']);
      return s;
    }

    testWidgets('keeps the entries before it for an in-app back', (
      tester,
    ) async {
      const three = ['/orders', '/orders/42', '/orders/42/items/3'];
      final s = await atOrder(tester);
      await s.type('/orders/42/items/3');
      expect(find.text('Item 3 of 42'), findsOneWidget);
      s.expectAt('/orders/42/items/3', entries: three);

      await s.tap(back);
      expect(s.browser.deltas, [-1]);
      s.expectAt('/orders/42', entries: three, at: 1);
      await s.tap(back);
      expect(s.browser.deltas, [-1, -1]);
      s.expectAt('/orders', entries: three, at: 0);

      // the typed entry is one of the app's now
      await s.traverse(2);
      s.expectAt('/orders/42/items/3', entries: three);
    });

    testWidgets('that does not exist is left with a back', (tester) async {
      const three = ['/orders', '/orders/42', '/orders/42/nope'];
      final s = await atOrder(tester);
      await s.type('/orders/42/nope');
      expect(find.text('No page at /orders/42/nope'), findsOneWidget);
      s.expectAt('/orders/42/nope', entries: three);

      await s.tap(back);
      expect(s.browser.deltas, [-1]);
      s.expectAt('/orders/42', entries: three, at: 1);
    });

    testWidgets('in an old spelling is corrected in its entry', (tester) async {
      final s = await atOrder(tester);
      await s.type('/order/7');
      expect(find.text('Order 7'), findsOneWidget);
      const three = ['/orders', '/orders/42', '/orders/7'];
      s.expectAt('/orders/7', entries: three);
      // one level up is not the entry before: nothing to go back to
      await s.tap(back);
      expect(s.browser.deltas, isEmpty);
      s.expectAt('/orders', entries: [...three, '/orders']);
    });

    testWidgets('replaces the entries after it', (tester) async {
      final s = await atOrder(tester);
      await s.traverse(-1);
      await s.type('/settings');
      s.expectAt('/settings', entries: ['/orders', '/settings']);
      await s.tap(profile);
      s.expectAt(
        '/settings/profile',
        entries: ['/orders', '/settings', '/settings/profile'],
      );
    });

    testWidgets('by another session starts a new shadow', (tester) async {
      final s = await atOrder(tester);
      await s.type(
        '/orders/42/items/3',
        state: {'fdr': 1, 's': 2, 'i': 7, 'h': null, 'b': <Object?>[]},
      );
      expect(s.router.currentUrl, '/orders/42/items/3');
      expect(s.router.provider.shadowHistory, ['/orders/42/items/3']);
      await s.tap(back);
      expect(s.browser.deltas, isEmpty);
      expect(s.browser.urls, [
        '/orders',
        '/orders/42',
        '/orders/42/items/3',
        '/orders/42',
      ]);
    });
  });

  group('a rebuild', () {
    testWidgets('that changes neither URL nor history state is not sent', (
      tester,
    ) async {
      final s = BrowserSession(tester, '/orders');
      await s.load();
      await s.tap(open42);
      final orders = OrdersNavigatorState.latest!;
      final sent = s.browser.reports.length;
      for (var i = 0; i < 150; i++) {
        orders.setState(() => orders.counter++);
        await tester.pump(const Duration(milliseconds: 66));
      }
      expect(find.text('counter 150'), findsOneWidget);
      expect(s.browser.reports.length, sent);
      s.expectAt('/orders/42', entries: ['/orders', '/orders/42']);

      // a change of the history state alone is written to the entry, once
      orders.setState(() => orders.scroll = 120);
      await tester.pumpAndSettle();
      orders.setState(() => orders.counter++);
      await tester.pumpAndSettle();
      expect(s.browser.reports.sublist(sent), [('/orders/42', true)]);
      expect('${s.browser.currentState}', contains('scroll: 120'));
      s.expectAt('/orders/42', entries: ['/orders', '/orders/42']);
    });

    testWidgets('after a browser back is not sent either, a changed state '
        'is', (tester) async {
      final s = BrowserSession(tester, '/orders');
      await s.load();
      final orders = OrdersNavigatorState.latest!;
      orders.setState(() => orders.scroll = 120);
      await tester.pumpAndSettle();
      await s.tap(open42);
      orders.setState(() => orders.scroll = 30);
      await tester.pumpAndSettle();
      expect('${s.browser.currentState}', contains('scroll: 30'));

      await s.traverse(-1);
      expect(find.text('scroll 120.0'), findsOneWidget);
      final sent = s.browser.reports.length;
      orders.setState(() => orders.counter++);
      await tester.pumpAndSettle();
      expect(s.browser.reports.length, sent);

      orders.setState(() => orders.scroll = 40);
      await tester.pumpAndSettle();
      expect(s.browser.reports.sublist(sent), [('/orders', true)]);
      expect('${s.browser.currentState}', contains('scroll: 40'));
      s.expectAt('/orders', entries: ['/orders', '/orders/42'], at: 0);

      // the reloaded app writes its entry again
      await s.load();
      expect(s.browser.reports.last, ('/orders', true));
      expect(find.text('scroll 40.0'), findsOneWidget);
      expect(s.browser.urls, ['/orders', '/orders/42']);
      expect((s.router.currentUrl, s.browser.bar), ('/orders', '/orders'));
    });
  });

  group('a long session', () {
    testWidgets('keeps a bounded shadow history off the web', (tester) async {
      final router = await startOffTheWeb(tester, '/orders');
      final orders = OrdersNavigatorState.latest!;
      for (var i = 0; i < 100; i++) {
        orders.setState(() => orders.selectedId = 42);
        await tester.pump();
        orders.setState(() => orders.selectedId = null);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(router.currentUrl, '/orders');
      expect(router.provider.shadowHistory.length, 65);
      expect(router.provider.shadowIndex, 64);
    });

    testWidgets('still goes back in the browser, also past what the shadow '
        'keeps', (tester) async {
      final s = BrowserSession(tester, '/orders');
      await s.load();
      for (var id = 1; id <= 70; id++) {
        s.router.open(HomeAt(OrdersAt(OrderDetail(id))));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      final urls = ['/orders', for (var id = 1; id <= 70; id++) '/orders/$id'];
      expect(s.browser.urls, urls);
      expect(
        (s.router.currentUrl, s.browser.bar),
        ('/orders/70', '/orders/70'),
      );
      expect(s.router.provider.shadowHistory, urls.sublist(6));

      await s.tap(item3);
      await s.tap(back);
      expect(s.browser.deltas, [-1]);
      expect(s.browser.urls, [...urls, '/orders/70/items/3']);
      expect(
        (s.router.currentUrl, s.browser.bar),
        ('/orders/70', '/orders/70'),
      );
      // the entries before an entry that a reload can still use
      final recorded = (s.browser.currentState! as Map)['b'] as List;
      expect(recorded.length, 32);
      expect(recorded.last, [70, '/orders/69']);

      // browser back to an entry the shadow dropped, and on from there
      await s.traverse(-70);
      expect((s.router.currentUrl, s.browser.bar), ('/orders', '/orders'));
      expect(s.router.provider.shadowIndex, 0);
      await s.traverse(1);
      expect((s.router.currentUrl, s.browser.bar), ('/orders/1', '/orders/1'));
      await s.tap(back);
      expect(s.browser.deltas, [-1, -1]);
      expect((s.router.currentUrl, s.browser.bar), ('/orders', '/orders'));
      expect(s.browser.urls, [...urls, '/orders/70/items/3']);
      expect(s.browser.index, 0);
    });
  });
}
