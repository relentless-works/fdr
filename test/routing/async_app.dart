// Async loading example: /orders/:id loads an order, /orders/:id/items/:item
// loads an item of it, /orders/:id/items/:item/reviews shows its reviews.
// Every navigator below a loaded level receives the domain model.
import 'dart:async';

import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';

// --- models and a fake API whose loads the tests complete by hand ----------

final class Order {
  const Order(this.id, {this.version = 1});
  final int id;
  final int version;
  String get title => 'Order #$id v$version';
}

final class Item {
  const Item(this.orderId, this.id);
  final int orderId;
  final int id;
  String get name => 'Item $id of order $orderId';
}

final class FakeApi {
  final orderLoads = <int, List<Completer<Order>>>{};
  final itemLoads = <int, List<Completer<Item>>>{};
  final releasedOrders = <String>[];

  Future<Order> order(int id) {
    final c = Completer<Order>();
    orderLoads.putIfAbsent(id, () => []).add(c);
    return c.future;
  }

  Future<Item> item(int orderId, int id) {
    final c = Completer<Item>();
    itemLoads.putIfAbsent(id, () => []).add(c);
    return c.future;
  }

  void completeOrder(int id, {int version = 1}) =>
      orderLoads[id]!.last.complete(Order(id, version: version));

  void failOrder(int id) =>
      orderLoads[id]!.last.completeError(StateError('offline'));

  void completeItem(int orderId, int id) =>
      itemLoads[id]!.last.complete(Item(orderId, id));
}

var api = FakeApi();

// --- routes -------------------------------------------------------------------

sealed class ShopRoute extends NavRoute {
  const ShopRoute();

  static ShopRoute fromUrl(Url url) => switch (url.segments) {
    [] || ['orders'] => const OrderListRoute(),
    ['orders', final int id, ...] => OrderAt(
      id,
      OrderRoute.fromUrl(url.rest(2)),
    ),
    _ => throw NotFound(url),
  };

  @override
  Url toUrl() => switch (this) {
    OrderListRoute() => const Url(['orders']),
    OrderAt(:final id, :final child) => Url(['orders', id]) + child.toUrl(),
  };
}

final class OrderListRoute extends ShopRoute {
  const OrderListRoute();
}

final class OrderAt extends ShopRoute {
  const OrderAt(this.id, [this.child = const OrderOverview()]);
  final int id;
  final OrderRoute child;
}

sealed class OrderRoute extends NavRoute {
  const OrderRoute();

  static OrderRoute fromUrl(Url url) => switch (url.segments) {
    [] => const OrderOverview(),
    ['items', final int item, ...] => ItemAt(
      item,
      ItemRoute.fromUrl(url.rest(2)),
    ),
    _ => throw NotFound(url),
  };

  @override
  Url toUrl() => switch (this) {
    OrderOverview() => const Url([]),
    ItemAt(:final item, :final child) => Url(['items', item]) + child.toUrl(),
  };
}

final class OrderOverview extends OrderRoute {
  const OrderOverview();
}

final class ItemAt extends OrderRoute {
  const ItemAt(this.item, [this.child = const ItemOverview()]);
  final int item;
  final ItemRoute child;
}

sealed class ItemRoute extends NavRoute {
  const ItemRoute();

  static ItemRoute fromUrl(Url url) => switch (url.segments) {
    [] => const ItemOverview(),
    ['reviews'] => const ItemReviews(),
    _ => throw NotFound(url),
  };

  @override
  Url toUrl() => switch (this) {
    ItemOverview() => const Url([]),
    ItemReviews() => const Url(['reviews']),
  };
}

final class ItemOverview extends ItemRoute {
  const ItemOverview();
}

final class ItemReviews extends ItemRoute {
  const ItemReviews();
}

// --- navigators --------------------------------------------------------------

class ShopNavigator extends StatefulNavigator<ShopRoute> {
  const ShopNavigator();

  @override
  ShopNavigatorState createState() => ShopNavigatorState();
}

class ShopNavigatorState
    extends StatefulNavigatorState<ShopNavigator, ShopRoute> {
  int? selected;
  OrderRoute? orderRoute;
  Order? preloaded;

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
    if (preloaded?.id != selected) preloaded = null;
  }

  @override
  List<NavEntry<ShopRoute>> build() => [
    NavPage(
      route: const OrderListRoute(),
      child: OrderListPage(
        onOpen: (id) => open(OrderAt(id)),
        onOpenLoaded: (order) {
          preloaded = order;
          open(OrderAt(order.id));
        },
      ),
    ),
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
          initialData: preloaded,
          onDispose: (order) => api.releasedOrders.add(order.title),
          loading: const LoadingView('Loading order'),
          error: (error, retry) => ErrorView(error: error, retry: retry),
          builder: (order, reload) =>
              OrderNavigator(order: order, reload: reload),
        ),
      ),
  ];
}

class OrderNavigator extends StatefulNavigator<OrderRoute> {
  const OrderNavigator({required this.order, required this.reload});
  final Order order;
  final Future<void> Function() reload;

  @override
  OrderNavigatorState createState() => OrderNavigatorState();
}

class OrderNavigatorState
    extends StatefulNavigatorState<OrderNavigator, OrderRoute> {
  static int created = 0;
  int? selectedItem;
  ItemRoute? itemRoute;

  @override
  void initState() {
    super.initState();
    created++;
  }

  @override
  void applyRoute(OrderRoute route) {
    switch (route) {
      case OrderOverview():
        selectedItem = null;
        itemRoute = null;
      case ItemAt(:final item, :final child):
        selectedItem = item;
        itemRoute = child;
    }
  }

  @override
  List<NavEntry<OrderRoute>> build() {
    final order = navigator.order;
    return [
      NavPage(
        route: const OrderOverview(),
        child: OrderPage(
          order: order,
          onItem: (item) => open(ItemAt(item)),
          onRefresh: navigator.reload,
        ),
      ),
      if (selectedItem case final item?)
        NestedNavigator(
          at: (route) => ItemAt(item, route),
          route: itemRoute,
          onPop: () => setState(() {
            selectedItem = null;
            itemRoute = null;
          }),
          child: FutureNavigator<Item, ItemRoute>(
            key: ValueKey(item),
            load: () => api.item(order.id, item),
            loading: const LoadingView('Loading item'),
            error: (error, retry) => ErrorView(error: error, retry: retry),
            builder: (item, _) => ItemNavigator(item: item),
          ),
        ),
    ];
  }
}

class ItemNavigator extends StatefulNavigator<ItemRoute> {
  const ItemNavigator({required this.item});
  final Item item;

  @override
  ItemNavigatorState createState() => ItemNavigatorState();
}

class ItemNavigatorState
    extends StatefulNavigatorState<ItemNavigator, ItemRoute> {
  bool reviews = false;

  @override
  void applyRoute(ItemRoute route) => reviews = route is ItemReviews;

  @override
  List<NavEntry<ItemRoute>> build() => [
    NavPage(
      route: const ItemOverview(),
      child: ItemPage(
        item: navigator.item,
        onReviews: () => open(const ItemReviews()),
      ),
    ),
    if (reviews)
      NavPage(
        route: const ItemReviews(),
        onPop: () => setState(() => reviews = false),
        child: ReviewsPage(item: navigator.item),
      ),
  ];
}

// --- widgets -----------------------------------------------------------------

class OrderListPage extends StatelessWidget {
  const OrderListPage({
    super.key,
    required this.onOpen,
    required this.onOpenLoaded,
  });
  final ValueChanged<int> onOpen;
  final ValueChanged<Order> onOpenLoaded;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Orders')),
    body: Column(
      children: [
        TextButton(
          key: const Key('open-42'),
          onPressed: () => onOpen(42),
          child: const Text('42'),
        ),
        TextButton(
          key: const Key('open-loaded-7'),
          onPressed: () => onOpenLoaded(const Order(7)),
          child: const Text('7'),
        ),
      ],
    ),
  );
}

class LoadingView extends StatelessWidget {
  const LoadingView(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(label)),
    body: const SizedBox.shrink(),
  );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, required this.retry});
  final Object error;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Failed: $error')),
    body: TextButton(
      key: const Key('retry'),
      onPressed: retry,
      child: const Text('retry'),
    ),
  );
}

class OrderPage extends StatelessWidget {
  const OrderPage({
    super.key,
    required this.order,
    required this.onItem,
    required this.onRefresh,
  });
  final Order order;
  final ValueChanged<int> onItem;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(order.title)),
    body: Column(
      children: [
        TextButton(
          key: const Key('item-3'),
          onPressed: () => onItem(3),
          child: const Text('item 3'),
        ),
        TextButton(
          key: const Key('refresh'),
          onPressed: () => unawaited(onRefresh()),
          child: const Text('refresh'),
        ),
      ],
    ),
  );
}

class ItemPage extends StatelessWidget {
  const ItemPage({super.key, required this.item, required this.onReviews});
  final Item item;
  final VoidCallback onReviews;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(item.name)),
    body: TextButton(
      key: const Key('reviews'),
      onPressed: onReviews,
      child: const Text('reviews'),
    ),
  );
}

class ReviewsPage extends StatelessWidget {
  const ReviewsPage({super.key, required this.item});
  final Item item;

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: Text('Reviews of ${item.name}')));
}
