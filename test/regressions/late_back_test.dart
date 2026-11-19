import 'package:fdr/fdr.dart';
import 'package:flutter_test/flutter_test.dart';

import 'model_browser.dart';

// An in-app back whose `history.go(-1)` the browser carries out only after
// the provider gave it up as lost. The provider has reported the pop in
// another way by then, so the entry that arrives late is not where the app
// is: the app keeps its state, and the browser is sent back to its entry,
// once every back that was given up has arrived.
//
// After each step: the page shown, the app's URL, the address bar, the
// browser's entries and its position.

enum Fallback {
  push(HistoryAction.push, ['/orders', '/orders/42', '/orders']),
  // the entry being left is overwritten, as for any pop that replaces
  replace(HistoryAction.replace, ['/orders', '/orders']);

  const Fallback(this.action, this.afterTimeout);
  final HistoryAction action;

  /// The entries once the back was given up and reported instead.
  final List<String> afterTimeout;
}

enum Carried {
  /// The delta is applied to the entry the browser is on when it carries
  /// the traversal out (WebKit's scheduled history navigation).
  fromWhereItIsThen,

  /// The target was fixed when `history.go` was called (Chrome resolves it
  /// in the browser process); only the popstate is late.
  toTheEntryAskedFor,
}

void main() {
  void expectState(
    BrowserSession s,
    String page, {
    required String app,
    String? bar,
    required List<String> entries,
    int? at,
    int pendingBacks = 0,
    bool browserOnAppEntry = true,
  }) {
    final provider = s.router.provider;
    final state =
        'app ${s.router.currentUrl}, bar ${s.browser.bar}, '
        'entries ${s.browser.urls}@${s.browser.index}, '
        'shadow ${provider.shadowHistory}@${provider.shadowIndex}, '
        'awaited ${provider.pendingBacks}, asked ${s.browser.deltas}';
    expect(find.text(page), findsOneWidget, reason: state);
    expect(s.router.currentUrl, app, reason: state);
    expect(s.browser.bar, bar ?? app, reason: state);
    expect(s.browser.urls, entries, reason: state);
    expect(s.browser.index, at ?? entries.length - 1, reason: state);
    expect(provider.pendingBacks, pendingBacks, reason: state);
    if (pendingBacks == 0 && browserOnAppEntry) {
      expect(provider.shadowHistory, entries, reason: state);
      expect(provider.shadowIndex, s.browser.index, reason: state);
    }
  }

  // Order 42 opened from the list, then the in-app back, which the browser
  // does not carry out before the provider gives it up.
  Future<BrowserSession> backGivenUp(
    WidgetTester tester,
    Fallback fallback,
  ) async {
    final s = BrowserSession(tester, '/orders', popFallback: fallback.action);
    await s.load();
    expectState(s, 'Orders', app: '/orders', entries: ['/orders']);

    await s.tap(open42);
    expectState(
      s,
      'Order 42',
      app: '/orders/42',
      entries: ['/orders', '/orders/42'],
    );

    await s.tapInFlight(back);
    expect(s.browser.deltas, [-1]);
    expectState(
      s,
      'Orders',
      app: '/orders',
      bar: '/orders/42',
      entries: ['/orders', '/orders/42'],
      pendingBacks: 1,
    );

    await tester.pump(lost);
    await tester.pumpAndSettle();
    expectState(s, 'Orders', app: '/orders', entries: fallback.afterTimeout);
    expect(s.browser.deltas, [-1]);
    return s;
  }

  // Order 42 and its item 3 opened from the list, then two in-app backs,
  // neither of which the browser carries out before the provider gives up.
  Future<BrowserSession> twoBacksGivenUp(
    WidgetTester tester,
    Fallback fallback,
  ) async {
    const item = '/orders/42/items/3';
    const opened = ['/orders', '/orders/42', item];
    final s = BrowserSession(tester, '/orders', popFallback: fallback.action);
    await s.load();
    await s.tap(open42);
    await s.tap(item3);
    expectState(s, 'Item 3 of 42', app: item, entries: opened);

    await s.tapInFlight(back);
    expectState(
      s,
      'Order 42',
      app: '/orders/42',
      bar: item,
      entries: opened,
      pendingBacks: 1,
    );
    await s.tapInFlight(back);
    expect(s.browser.deltas, [-1, -1]);
    expectState(
      s,
      'Orders',
      app: '/orders',
      bar: item,
      entries: opened,
      pendingBacks: 2,
    );

    await tester.pump(lost);
    await tester.pumpAndSettle();
    expectState(
      s,
      'Orders',
      app: '/orders',
      entries: switch (fallback) {
        Fallback.push => [...opened, '/orders'],
        Fallback.replace => ['/orders', '/orders/42', '/orders'],
      },
    );
    expect(s.browser.deltas, [-1, -1]);
    return s;
  }

  // the browser carries out the `history.go(-1)` of the first in-app back,
  // then what the app asks for in response
  Future<void> carryOutLate(BrowserSession s, Carried carried) async {
    expect(s.browser.pending.first, -1);
    switch (carried) {
      case Carried.fromWhereItIsThen:
        break;
      case Carried.toTheEntryAskedFor:
        s.browser.pending.removeAt(0);
        // the list the order was opened from
        await s.traverse(0 - s.browser.index);
    }
    await s.arrive();
  }

  for (final fallback in Fallback.values) {
    for (final carried in Carried.values) {
      final variant = '${fallback.name}, ${carried.name}';

      testWidgets('a back carried out late leaves the app where it is '
          '($variant)', (tester) async {
        final s = await backGivenUp(tester, fallback);
        final entries = fallback.afterTimeout;

        await carryOutLate(s, carried);
        // not on Order 42 again, and the browser is back on the app's entry
        expect(find.text('Order 42'), findsNothing);
        expectState(s, 'Orders', app: '/orders', entries: entries);
        // forward again, from the entry the browser went to
        final forward = switch (carried) {
          Carried.fromWhereItIsThen => 1,
          Carried.toTheEntryAskedFor => entries.length - 1,
        };
        expect(s.browser.deltas, [-1, forward]);

        // and navigation is reported as before
        await s.tap(open42);
        expectState(
          s,
          'Order 42',
          app: '/orders/42',
          entries: [...entries, '/orders/42'],
        );
        await s.tap(back);
        expectState(
          s,
          'Orders',
          app: '/orders',
          entries: [...entries, '/orders/42'],
          at: entries.length - 1,
        );
        expect(s.browser.deltas, [-1, forward, -1]);
      });

      testWidgets('a back carried out late, after the user went on, leaves '
          'them there ($variant)', (tester) async {
        final s = await backGivenUp(tester, fallback);
        final entries = [
          ...fallback.afterTimeout,
          '/settings',
          '/settings/profile',
        ];

        await s.tapInFlight(tabSettings);
        expectState(
          s,
          'Settings',
          app: '/settings',
          entries: entries.sublist(0, entries.length - 1),
        );
        await s.tapInFlight(profile);
        expectState(s, 'Profile', app: '/settings/profile', entries: entries);
        expect(s.browser.deltas, [-1]);

        await carryOutLate(s, carried);
        expectState(s, 'Profile', app: '/settings/profile', entries: entries);
        expect(s.browser.deltas, [
          -1,
          switch (carried) {
            Carried.fromWhereItIsThen => 1,
            Carried.toTheEntryAskedFor => entries.length - 1,
          },
        ]);
        // neither the list nor the settings were reported again
        expect(s.browser.reports.last, ('/settings/profile', false));

        await s.tap(back);
        expectState(
          s,
          'Settings',
          app: '/settings',
          entries: entries,
          at: entries.length - 2,
        );
      });
    }
  }

  // the browser carries out the oldest `history.go` of the app: by its
  // delta from where it is, or to the entry [asked] that was fixed then
  Future<void> carryOutNext(
    BrowserSession s,
    Carried carried, {
    required int asked,
  }) async {
    final delta = s.browser.pending.removeAt(0);
    await s.traverse(switch (carried) {
      Carried.fromWhereItIsThen => delta,
      Carried.toTheEntryAskedFor => asked - s.browser.index,
    });
  }

  for (final fallback in Fallback.values) {
    for (final carried in Carried.values) {
      final variant = '${fallback.name}, ${carried.name}';

      testWidgets('a back carried out late while the next one is in flight '
          'is not taken for that one ($variant)', (tester) async {
        final s = await backGivenUp(tester, fallback);
        final entries = [...fallback.afterTimeout, '/orders/42'];
        // the list, in the entry written when the back was given up
        final list = entries.length - 2;

        await s.tapInFlight(open42);
        expectState(s, 'Order 42', app: '/orders/42', entries: entries);
        await s.tapInFlight(back);
        expect(s.browser.deltas, [-1, -1]);
        expectState(
          s,
          'Orders',
          app: '/orders',
          bar: '/orders/42',
          entries: entries,
          pendingBacks: 1,
        );

        // the back given up
        await carryOutNext(s, carried, asked: 0);
        switch (carried) {
          case Carried.fromWhereItIsThen:
            // on the entry of the second back, which is still to come
            expectState(
              s,
              'Orders',
              app: '/orders',
              entries: entries,
              at: list,
            );
          case Carried.toTheEntryAskedFor:
            expectState(
              s,
              'Orders',
              app: '/orders',
              entries: entries,
              at: 0,
              pendingBacks: 1,
            );
        }
        expect(s.browser.deltas, [-1, -1]);

        // the second back
        await carryOutNext(s, carried, asked: list);
        switch (carried) {
          case Carried.fromWhereItIsThen:
            // one entry too far: not shown, and the browser is sent back
            expectState(
              s,
              'Orders',
              app: '/orders',
              bar: entries[list - 1],
              entries: entries,
              at: list - 1,
              pendingBacks: 1,
            );
            expect(s.browser.deltas, [-1, -1, 1]);
            await s.arrive();
          case Carried.toTheEntryAskedFor:
            expect(s.browser.deltas, [-1, -1]);
        }
        expect(find.text('Order 42'), findsNothing);
        expectState(s, 'Orders', app: '/orders', entries: entries, at: list);
        final asked = [...s.browser.deltas];

        await tester.pump(lost);
        expectState(s, 'Orders', app: '/orders', entries: entries, at: list);
        // and the browser's buttons are the user's again
        await s.traverse(1);
        expectState(s, 'Order 42', app: '/orders/42', entries: entries);
        await s.tap(back);
        expectState(s, 'Orders', app: '/orders', entries: entries, at: list);
        expect(s.browser.deltas, [...asked, -1]);
      });

      testWidgets('two backs given up together and carried out late leave '
          'the app where it is ($variant)', (tester) async {
        final s = await twoBacksGivenUp(tester, fallback);
        final entries = s.browser.urls;
        final last = entries.length - 1;

        // the first one: the app waits for the second
        await carryOutNext(s, carried, asked: 1);
        final first = switch (carried) {
          Carried.fromWhereItIsThen => last - 1,
          Carried.toTheEntryAskedFor => 1,
        };
        expectState(
          s,
          'Orders',
          app: '/orders',
          bar: entries[first],
          entries: entries,
          at: first,
          browserOnAppEntry: false,
        );
        expect(s.browser.deltas, [-1, -1]);

        // the second one: the browser is sent back to the app's entry
        await carryOutNext(s, carried, asked: 0);
        final second = switch (carried) {
          Carried.fromWhereItIsThen => last - 2,
          Carried.toTheEntryAskedFor => 0,
        };
        expectState(
          s,
          'Orders',
          app: '/orders',
          bar: entries[second],
          entries: entries,
          at: second,
          pendingBacks: 1,
        );
        expect(s.browser.deltas, [-1, -1, last - second]);

        await s.arrive();
        expect(find.text('Order 42'), findsNothing);
        expectState(s, 'Orders', app: '/orders', entries: entries);
        expect(s.browser.deltas, [-1, -1, last - second]);

        // and navigation is reported as before
        await s.tap(open42);
        expectState(
          s,
          'Order 42',
          app: '/orders/42',
          entries: [...entries, '/orders/42'],
        );
        await s.tap(back);
        expectState(
          s,
          'Orders',
          app: '/orders',
          entries: [...entries, '/orders/42'],
          at: last,
        );
        expect(s.browser.deltas, [-1, -1, last - second, -1]);
      });
    }
  }

  testWidgets('of two backs given up together, the first carried out late '
      'and the second never: the browser is sent back', (tester) async {
    final s = await twoBacksGivenUp(tester, Fallback.push);
    final entries = s.browser.urls;

    await carryOutNext(s, Carried.fromWhereItIsThen, asked: 1);
    s.browser.pending.clear();
    expectState(
      s,
      'Orders',
      app: '/orders',
      bar: '/orders/42/items/3',
      entries: entries,
      at: 2,
      browserOnAppEntry: false,
    );
    expect(s.browser.deltas, [-1, -1]);

    await tester.pump(lost);
    expect(s.browser.deltas, [-1, -1, 1]);
    await s.arrive();
    expectState(s, 'Orders', app: '/orders', entries: entries);

    await s.traverse(-1);
    expectState(
      s,
      'Item 3 of 42',
      app: '/orders/42/items/3',
      entries: entries,
      at: 2,
    );
    expect(s.browser.deltas, [-1, -1, 1]);
  });

  // the app cannot tell it from the late one
  testWidgets('a browser back while the late one is still expected is taken '
      'for it', (tester) async {
    final s = await backGivenUp(tester, Fallback.push);
    const entries = ['/orders', '/orders/42', '/orders'];
    // really lost: the browser never carries it out
    s.browser.pending.clear();

    await s.traverse(-1);
    expectState(
      s,
      'Orders',
      app: '/orders',
      bar: '/orders/42',
      entries: entries,
      at: 1,
      pendingBacks: 1,
    );
    expect(s.browser.deltas, [-1, 1]);
    await s.arrive();
    expectState(s, 'Orders', app: '/orders', entries: entries);

    // the next one is the user's
    await s.traverse(-1);
    expectState(s, 'Order 42', app: '/orders/42', entries: entries, at: 1);
    expect(s.browser.deltas, [-1, 1]);
  });

  testWidgets('a browser back once the late one is no longer expected is '
      'the user\'s', (tester) async {
    final s = await backGivenUp(tester, Fallback.push);
    const entries = ['/orders', '/orders/42', '/orders'];
    s.browser.pending.clear();

    await tester.pump(lost);
    expectState(s, 'Orders', app: '/orders', entries: entries);

    await s.traverse(-1);
    expectState(s, 'Order 42', app: '/orders/42', entries: entries, at: 1);
    expect(s.browser.deltas, [-1]);
  });

  testWidgets('a browser back after another entry arrived is the user\'s', (
    tester,
  ) async {
    final s = await backGivenUp(tester, Fallback.push);
    const entries = ['/orders', '/orders/42', '/orders', '/settings'];
    s.browser.pending.clear();

    // a hash typed into the address bar: the browser has moved on
    await s.type('/settings');
    expectState(s, 'Settings', app: '/settings', entries: entries);

    await s.traverse(-1);
    expectState(s, 'Orders', app: '/orders', entries: entries, at: 2);
    await s.traverse(-1);
    expectState(s, 'Order 42', app: '/orders/42', entries: entries, at: 1);
    expect(s.browser.deltas, [-1]);
  });

  // The traversal was carried out in time, so the two browser models do not
  // differ here: only its delivery did not reach the app.
  testWidgets('a back that happened, with a page opened before it was given '
      'up, is not expected any more', (tester) async {
    final s = BrowserSession(tester, '/orders');
    await s.load();
    await s.tap(open42);
    expectState(
      s,
      'Order 42',
      app: '/orders/42',
      entries: ['/orders', '/orders/42'],
    );

    await s.tapInFlight(back);
    // the browser goes back, the entry is not delivered
    s.browser.pending.clear();
    s.browser.index = 0;
    expectState(
      s,
      'Orders',
      app: '/orders',
      entries: ['/orders', '/orders/42'],
      at: 0,
      pendingBacks: 1,
    );

    await s.tapInFlight(tabSettings);
    expectState(
      s,
      'Settings',
      app: '/settings',
      bar: '/orders',
      entries: ['/orders', '/orders/42'],
      at: 0,
      pendingBacks: 1,
    );

    await tester.pump(lost);
    await tester.pumpAndSettle();
    const entries = ['/orders', '/settings'];
    expectState(s, 'Settings', app: '/settings', entries: entries);

    // nothing is outstanding: this back is the user's
    await s.traverse(-1);
    expectState(s, 'Orders', app: '/orders', entries: entries, at: 0);
    expect(s.browser.deltas, [-1]);
    await s.traverse(1);
    expectState(s, 'Settings', app: '/settings', entries: entries);
    expect(s.browser.deltas, [-1]);
  });
}
