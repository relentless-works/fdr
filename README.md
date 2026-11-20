# FDR

Declarative routing as easy as `Widget.build`.

## Features

FDR enables you to derive the displayed pages and navigation stack from your app's state – at all times.
When used in combination with proper state modelling as the basis, this allows for complex navigation flows that'll always work. No more `push` and `popUntil` that might be slightly different in every scenario.

## A navigator

A navigator's `build` returns its pages from its state, like a widget's `build`:

```dart
import 'package:fdr/fdr.dart';
import 'package:material_ui/material_ui.dart';

class OrdersNavigatorState
    extends StatefulNavigatorState<OrdersNavigator, Never> {
  int? selected;

  @override
  List<NavEntry<Never>> build() => [
    NavPage(child: OrderListPage(onOpen: (id) => setState(() => selected = id))),
    if (selected case final id?)
      NavPage(
        onPop: () => setState(() => selected = null),
        child: OrderPage(id: id),
      ),
  ];
}

MaterialApp(home: DeclarativeNavigator(navigator: OrdersNavigator()));
```

fdr needs Flutter 3.50 and builds on material_ui and cupertino_ui, which replace the deprecated `package:flutter/material.dart` and `cupertino.dart`: `NavPage` and `DialogPage` follow material_ui's `Theme` and localizations.

## URL routing

For Flutter Web (address bar, reload, browser back and forward, bookmarks, links that open in a new tab) and deep links on mobile, a navigator gets a sealed route type. Like `fromJson`/`toJson`, each route type maps its own part of the URL in plain Dart:

```dart
sealed class OrdersRoute extends NavRoute {
  const OrdersRoute();

  static OrdersRoute fromUrl(Url url) => switch (url.segments) {
    [] => const OrderList(),
    [final int id] => OrderDetail(id),
    _ => throw NotFound(url),
  };

  @override
  Url toUrl() => switch (this) {
    OrderList() => const Url([]),
    OrderDetail(:final id) => Url([id]),
  };
}
```

The navigator sets its state from an incoming route, and each page says which route it shows:

```dart
@override
void applyRoute(OrdersRoute route) {
  selected = switch (route) {
    OrderList() => null,
    OrderDetail(:final id) => id,
  };
}

@override
List<NavEntry<OrdersRoute>> build() => [
  const NavPage(route: OrderList(), child: OrderListPage()),
  if (selected case final id?)
    NavPage(
      route: OrderDetail(id),
      onPop: () => setState(() => selected = null),
      child: OrderPage(id: id),
    ),
];

// in OrderListPage: on the web a real <a href>, which also opens in a new tab
RouteLink(
  route: OrderDetail(id),
  builder: (context, open) => ListTile(title: Text('Order $id'), onTap: open),
)

final router = FdrRouter(root: OrdersNavigator(), fromUrl: OrdersRoute.fromUrl);
MaterialApp.router(routerConfig: router.config);
```

In-app pops go back in the browser history instead of adding entries, and a URL that does not parse shows its longest part that does with a not-found page on top. Also included:

- `NestedNavigator` for child navigators with their own route type, and `TabsPage` for tabs that keep their stacks;
- `FutureNavigator`, which loads data by id and hands the model to the child navigator, while deep links into the loaded levels keep working;
- `DialogPage` for dialogs without a URL, and `CustomPage` for sheets or custom transitions;
- `open(route)` on a navigator state, and `router.open(route)` from outside the tree (e.g. a push notification);
- `watch(listenable)` and `listen(stream)` to rebuild a navigator when app state owned elsewhere changes (e.g. a bloc).

See [doc/url-routing.md](doc/url-routing.md) for the design, and `example/lib/main_url_routing.dart` for a runnable demo (`flutter run -d chrome -t lib/main_url_routing.dart` in `example/`).
