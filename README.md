# FDR

Declarative routing as easy as `Widget.build`.

## Features

FDR enables you to derive the displayed pages and navigation stack from your app's state – at all times.
When used in combination with proper state modelling as the basis, this allows for complex navigation flows that'll always work. No more `push` and `popUntil` that might be slightly different in every scenario.

## URL routing

Navigators can take part in URLs, for Flutter Web (address bar, reload, browser back and forward, bookmarks) and for deep links on mobile. Every such navigator declares a sealed route type and a codec that both parses and prints its part of the URL; pages say which route addresses them:

```dart
class OrdersNavigatorState
    extends StatefulNavigatorState<OrdersNavigator, OrdersRoute> {
  int? selectedId;

  @override
  void applyRoute(OrdersRoute route) {
    selectedId = switch (route) {
      OrderList() => null,
      OrderDetail(:final id) => id,
    };
  }

  @override
  List<DeclarativeNavigatable<OrdersRoute>> build() => [
    OrderListPage(onOpen: (id) => navigate(OrderDetail(id)))
        .page(onPop: null, route: const OrderList()),
    if (selectedId case final id?)
      OrderDetailPage(id: id).page(
        onPop: () => setState(() => selectedId = null),
        route: OrderDetail(id),
      ),
  ];
}

final router = FdrRouter<AppRoute>(
  root: const AppNavigator(),
  codec: appCodec,
  notFound: NotFoundRoute.new,
);

MaterialApp.router(routerConfig: router.config);
```

In-app pops go back in the browser history instead of adding entries.

Also included:

- `shell(...)` for a persistent tab bar with one nested navigator per tab;
- `AsyncNavigator`, which loads data by id and hands the model to the child navigator, while deep links into the loaded levels keep working;
- `watch(listenable)` to rebuild a navigator when app state owned elsewhere changes.

See [doc/url-routing.md](doc/url-routing.md) for the design, and `example/lib/main_url_routing.dart` for a runnable demo (`flutter run -d chrome -t lib/main_url_routing.dart` in `example/`).

