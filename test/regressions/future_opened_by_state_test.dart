import 'package:fdr/fdr.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../routing/async_app.dart';

// The loading page of a FutureNavigator is addressed by the route it was
// given. Opened by a plain setState, that is the stored child route, which
// has to be set together with the id.
class PlainShop extends StatefulNavigator<ShopRoute> {
  const PlainShop();
  @override
  PlainShopState createState() => PlainShopState();
}

late PlainShopState shop;

class PlainShopState extends StatefulNavigatorState<PlainShop, ShopRoute> {
  int? selected;
  OrderRoute? orderRoute;

  @override
  void initState() {
    super.initState();
    shop = this;
  }

  void select(int id) => setState(() {
    selected = id;
    orderRoute = const OrderOverview();
  });

  @override
  void applyRoute(ShopRoute route) {
    switch (route) {
      case OrderListRoute():
        selected = null;
        orderRoute = null;
      case OrderAt(:final id, :final child):
        selected = id;
        orderRoute = child;
    }
  }

  @override
  List<NavEntry<ShopRoute>> build() => [
    const NavPage(route: OrderListRoute(), child: Text('list')),
    if (selected case final id?)
      NestedNavigator(
        at: (route) => OrderAt(id, route),
        route: orderRoute,
        onPop: () => setState(() {
          selected = null;
          orderRoute = null;
        }),
        child: FutureNavigator<Order, OrderRoute>(
          key: ValueKey(id),
          load: () => api.order(id),
          loading: const LoadingView('Loading order'),
          error: (error, retry) => ErrorView(error: error, retry: retry),
          builder: (order, reload) =>
              OrderNavigator(order: order, reload: reload),
        ),
      ),
  ];
}

void main() {
  final navLog = <MethodCall>[];
  List<({String uri, bool replace})> reports() => [
    for (final call in navLog)
      if (call.method == 'routeInformationUpdated')
        (
          uri: (call.arguments as Map)['uri'] as String,
          replace: (call.arguments as Map)['replace'] as bool,
        ),
  ];

  setUp(() {
    api = FakeApi();
    navLog.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.navigation, (call) async {
          navLog.add(call);
          return null;
        });
  });

  testWidgets('opened by setState with the child route, the URL names the '
      'order while it loads and finishing the load adds no entry', (
    tester,
  ) async {
    final router = FdrRouter<ShopRoute>(
      root: const PlainShop(),
      fromUrl: ShopRoute.fromUrl,
      initialRouteInformation: RouteInformation(uri: Uri.parse('/orders')),
      sessionId: 1,
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/orders');

    shop.select(42);
    await tester.pumpAndSettle();
    expect(find.text('Loading order'), findsOneWidget);
    expect(router.currentUrl, '/orders/42');
    expect(reports().last, (uri: '/orders/42', replace: false));
    final before = reports().length;

    api.completeOrder(42);
    await tester.pumpAndSettle();
    expect(find.text('Order #42 v1'), findsOneWidget);
    expect(router.currentUrl, '/orders/42');
    expect(reports().skip(before).every((r) => r.replace), isTrue);
    expect(router.provider.shadowHistory, ['/orders', '/orders/42']);
  });
}
