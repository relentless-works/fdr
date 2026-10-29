import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'async_app.dart';

final _navLog = <MethodCall>[];

List<({String uri, bool replace})> get _reports => [
  for (final call in _navLog)
    if (call.method == 'routeInformationUpdated')
      (
        uri: (call.arguments as Map)['uri'] as String,
        replace: (call.arguments as Map)['replace'] as bool,
      ),
];

late FdrRouter<ShopRoute> _router;

String get _url => _router.delegate.currentUrl!;

Future<void> _pumpShop(WidgetTester tester, String initialUrl) async {
  tester.binding.platformDispatcher.defaultRouteNameTestValue = initialUrl;
  _router = FdrRouter<ShopRoute>(
    root: const ShopNavigator(),
    codec: shopCodec,
    notFound: (_) => const OrderListRoute(),
    sessionId: 1,
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: _router.config));
  await tester.pump();
}

Future<void> _browserNavigatesTo(WidgetTester tester, String location) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMethodCodec().encodeMethodCall(
      MethodCall('pushRouteInformation', {'location': location}),
    ),
    (_) {},
  );
  await tester.pumpAndSettle();
}

Finder _anywhere(String text) => find.text(text, skipOffstage: false);

void main() {
  setUp(() {
    api = FakeApi();
    OrderNavigatorState.created = 0;
    _navLog.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.navigation, (call) async {
          _navLog.add(call);
          return null;
        });
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher
        .clearDefaultRouteNameTestValue();
  });

  testWidgets('a deep link loads level by level and keeps its URL', (
    tester,
  ) async {
    await _pumpShop(tester, '/orders/42/items/3/reviews');
    expect(find.text('Loading order'), findsOneWidget);
    expect(_url, '/orders/42/items/3/reviews');

    api.completeOrder(42);
    await tester.pumpAndSettle();
    // the order navigator got the model and handed the rest to the item level
    expect(find.text('Loading item'), findsOneWidget);
    expect(_anywhere('Order #42 v1'), findsOneWidget);
    expect(api.itemLoads.keys, [3]);
    expect(_url, '/orders/42/items/3/reviews');

    api.completeItem(42, 3);
    await tester.pumpAndSettle();
    expect(find.text('Reviews of Item 3 of order 42'), findsOneWidget);
    expect(_url, '/orders/42/items/3/reviews');
    // loading never touched the history: one entry, only replaced
    expect(_reports.map((r) => r.uri).toSet(), {'/orders/42/items/3/reviews'});
    expect(_reports.every((r) => r.replace), isTrue);

    // back walks the stack the deep link implied
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Item 3 of order 42'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Order #42 v1'), findsOneWidget);
    expect(_url, '/orders/42');
  });

  testWidgets('opening pushes one entry; finishing the load only replaces it', (
    tester,
  ) async {
    await _pumpShop(tester, '/orders');
    await tester.tap(find.byKey(const Key('open-42')));
    await tester.pumpAndSettle();
    expect(find.text('Loading order'), findsOneWidget);
    expect((_reports.last.uri, _reports.last.replace), ('/orders/42', false));
    final pushes = _reports.where((r) => !r.replace).length;

    api.completeOrder(42);
    await tester.pumpAndSettle();
    expect(find.text('Order #42 v1'), findsOneWidget);
    expect(_reports.where((r) => !r.replace).length, pushes);
    expect(_router.provider.shadowHistory, ['/orders', '/orders/42']);
  });

  testWidgets('a failed load shows an error at the same URL; retry loads', (
    tester,
  ) async {
    await _pumpShop(tester, '/orders/42');
    api.failOrder(42);
    await tester.pumpAndSettle();
    expect(find.textContaining('offline'), findsOneWidget);
    expect(_url, '/orders/42');

    await tester.tap(find.byKey(const Key('retry')));
    await tester.pumpAndSettle();
    expect(find.text('Loading order'), findsOneWidget);
    api.completeOrder(42);
    await tester.pumpAndSettle();
    expect(find.text('Order #42 v1'), findsOneWidget);
  });

  testWidgets('a newer URL wins over a load still in flight', (tester) async {
    await _pumpShop(tester, '/orders/42');
    await _browserNavigatesTo(tester, '/orders/7');
    expect(find.text('Loading order'), findsOneWidget);

    // the stale result arrives late: never shown, released right away
    api.completeOrder(42);
    await tester.pumpAndSettle();
    expect(_anywhere('Order #42 v1'), findsNothing);
    expect(api.releasedOrders, ['Order #42 v1']);

    api.completeOrder(7);
    await tester.pumpAndSettle();
    expect(find.text('Order #7 v1'), findsOneWidget);
    expect(_url, '/orders/7');
  });

  testWidgets('re-applying the URL while loading does not load again', (
    tester,
  ) async {
    await _pumpShop(tester, '/orders/42');
    await _browserNavigatesTo(tester, '/orders/42');
    expect(api.orderLoads[42], hasLength(1));
  });

  testWidgets('leaving while loading drops the load', (tester) async {
    await _pumpShop(tester, '/orders');
    await tester.tap(find.byKey(const Key('open-42')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(_url, '/orders');

    api.completeOrder(42);
    await tester.pumpAndSettle();
    expect(_anywhere('Order #42 v1'), findsNothing);
    expect(api.releasedOrders, ['Order #42 v1']);
  });

  testWidgets('data the app already has is passed down without loading', (
    tester,
  ) async {
    await _pumpShop(tester, '/orders');
    await tester.tap(find.byKey(const Key('open-loaded-7')));
    await tester.pumpAndSettle();
    expect(find.text('Order #7 v1'), findsOneWidget);
    expect(api.orderLoads[7], isNull);
    expect(_url, '/orders/7');
  });

  testWidgets('a reload hands new data to the same child state', (
    tester,
  ) async {
    await _pumpShop(tester, '/orders/42/items/3');
    api.completeOrder(42);
    await tester.pumpAndSettle();
    api.completeItem(42, 3);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('refresh')));
    await tester.pump();
    // the old data stays on screen while reloading
    expect(find.text('Order #42 v1'), findsOneWidget);
    api.completeOrder(42, version: 2);
    await tester.pumpAndSettle();
    expect(find.text('Order #42 v2'), findsOneWidget);
    expect(OrderNavigatorState.created, 1);
    expect(api.releasedOrders, ['Order #42 v1']);
  });

  testWidgets('leaving a loaded order releases it', (tester) async {
    await _pumpShop(tester, '/orders/42');
    api.completeOrder(42);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(_url, '/orders');
    expect(api.releasedOrders, ['Order #42 v1']);
  });
}
