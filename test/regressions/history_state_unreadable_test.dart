import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../routing/url_routing_test.dart'
    show
        FakeBrowserHistory,
        browserNavigatesTo,
        envelope,
        navLog,
        pumpApp,
        reports;

// History state outlives the build that wrote it: an entry of an earlier
// deployment stays in the tab's history, also across reloads.

// the same tree, as a build with another historyState shape wrote it
Object? unreadable(Object? h) => switch (h) {
  final Map<Object?, Object?> map => {
    for (final e in map.entries)
      e.key: e.key == 'scroll' ? 'x' : unreadable(e.value),
  },
  final List<Object?> list => [for (final e in list) unreadable(e)],
  _ => h,
};

void main() {
  setUp(() {
    navLog.clear();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.navigation, (call) async {
      navLog.add(call);
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.navigation, null);
      TestWidgetsFlutterBinding.instance.platformDispatcher
          .clearDefaultRouteNameTestValue();
    });
  });

  // the entry of /orders with a scroll offset, the order opened on top
  Future<Map<Object?, Object?>> writtenState(WidgetTester tester) async {
    await pumpApp(tester, initialUrl: '/orders');
    await tester.tap(find.byKey(const Key('scroll')));
    await tester.tap(find.byKey(const Key('open-42')));
    await tester.pumpAndSettle();
    final entry = reports.lastWhere(
      (r) => r.uri == '/orders' && (r.state! as Map)['h'] != null,
    );
    return entry.state! as Map;
  }

  testWidgets('a reload on an entry this build cannot read starts the app '
      'and overwrites the entry', (tester) async {
    final bad = unreadable(await writtenState(tester));
    expect('$bad', contains('scroll: x'));

    await tester.pumpWidget(const SizedBox());
    navLog.clear();
    final history = FakeBrowserHistory()..currentState = bad;
    final router = await pumpApp(
      tester,
      initialUrl: '/orders',
      browserHistory: history,
    );
    expect(tester.takeException(), isA<TypeError>());
    expect(router.currentUrl, '/orders');
    expect(find.text('scroll 0.0'), findsOneWidget);
    // the next reload reads what this build wrote
    expect((reports.last.uri, reports.last.replace), ('/orders', true));
    expect('${reports.last.state}', isNot(contains('scroll: x')));
  });

  testWidgets('browser back onto an entry this build cannot read shows its '
      'page', (tester) async {
    final bad = unreadable((await writtenState(tester))['h']);
    expect(find.text('Order 42'), findsOneWidget);
    navLog.clear();
    await browserNavigatesTo(tester, '/orders', state: envelope(1, bad));
    expect(tester.takeException(), isA<TypeError>());
    expect(find.text('Order 42'), findsNothing);
    // the navigator keeps the state it had
    expect(find.text('scroll 120.0'), findsOneWidget);
    expect((reports.last.uri, reports.last.replace), ('/orders', true));
    expect('${reports.last.state}', isNot(contains('scroll: x')));
  });
}
