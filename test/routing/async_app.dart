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

// --- routes and codecs -------------------------------------------------------

sealed class ShopRoute {
  const ShopRoute();
}

final class OrderListRoute extends ShopRoute {
  const OrderListRoute();
}

final class OrderAt extends ShopRoute {
  const OrderAt(this.id, this.child);
  final int id;
  final OrderRoute child;
}

sealed class OrderRoute {
  const OrderRoute();
}

final class OrderOverview extends OrderRoute {
  const OrderOverview();
}

final class ItemAt extends OrderRoute {
  const ItemAt(this.item, this.child);
  final int item;
  final ItemRoute child;
}

sealed class ItemRoute {
  const ItemRoute();
}

final class ItemOverview extends ItemRoute {
  const ItemOverview();
}

final class ItemReviews extends ItemRoute {
  const ItemReviews();
}

final itemOverview = Case<ItemRoute, ItemOverview>(
  end.iso(to: (_) => const ItemOverview(), from: (_) => ()),
);
final itemReviews = Case<ItemRoute, ItemReviews>(
  lit('reviews').then(end).iso(to: (_) => const ItemReviews(), from: (_) => ()),
);
final itemCodec = SumCodec<ItemRoute>(
  cases: [itemOverview, itemReviews],
  select: (r) => switch (r) {
    final ItemOverview o => itemOverview.bind(o),
    final ItemReviews v => itemReviews.bind(v),
  },
);

final orderOverview = Case<OrderRoute, OrderOverview>(
  end.iso(to: (_) => const OrderOverview(), from: (_) => ()),
);
final itemAt = Case<OrderRoute, ItemAt>(
  lit('items')
      .then(Seg.int.and(itemCodec))
      .iso(to: (r) => ItemAt(r.$1, r.$2), from: (r) => (r.item, r.child)),
);
final orderCodec = SumCodec<OrderRoute>(
  cases: [orderOverview, itemAt],
  select: (r) => switch (r) {
    final OrderOverview o => orderOverview.bind(o),
    final ItemAt i => itemAt.bind(i),
  },
);

final orderList = Case<ShopRoute, OrderListRoute>(
  lit('orders')
      .then(end)
      .iso(to: (_) => const OrderListRoute(), from: (_) => ()),
);
final orderAt = Case<ShopRoute, OrderAt>(
  lit('orders')
      .then(Seg.int.and(orderCodec))
      .iso(to: (r) => OrderAt(r.$1, r.$2), from: (r) => (r.id, r.child)),
);
final shopCodec = SumCodec<ShopRoute>(
  cases: [orderList, orderAt, alias(end, (_) => const OrderListRoute())],
  select: (r) => switch (r) {
    final OrderListRoute l => orderList.bind(l),
    final OrderAt o => orderAt.bind(o),
  },
);

// --- navigators --------------------------------------------------------------

class ShopNavigator extends StatefulNavigator<ShopRoute> {
  const ShopNavigator();

  @override
  ShopNavigatorState createState() => ShopNavigatorState();
}

class ShopNavigatorState
    extends StatefulNavigatorState<ShopNavigator, ShopRoute> {
  int? selected;
  Order? preloaded;

  @override
  void applyRoute(ShopRoute route) {
    selected = switch (route) {
      OrderListRoute() => null,
      OrderAt(:final id) => id,
    };
    if (preloaded?.id != selected) preloaded = null;
  }

  @override
  List<DeclarativeNavigatable<ShopRoute>> build() => [
    OrderListPage(
      onOpen: (id) => navigate(OrderAt(id, const OrderOverview())),
      onOpenLoaded: (order) {
        preloaded = order;
        navigate(OrderAt(order.id, const OrderOverview()));
      },
    ).page(onPop: null, route: const OrderListRoute()),
    if (selected case final id?)
      AsyncNavigator<Order, OrderRoute>(
            key: ValueKey(id),
            load: () => api.order(id),
            initialData: preloaded,
            onDispose: (order) => api.releasedOrders.add(order.title),
            loading: const LoadingView('Loading order'),
            failed: (error, retry) => ErrorView(error: error, retry: retry),
            builder: (order, reload) =>
                OrderNavigator(order: order, reload: reload),
          )
          .mount(
            embed: (child) => OrderAt(id, child),
            unwrap: (route) => switch (route) {
              OrderAt(id: final routeId, :final child) when routeId == id =>
                child,
              _ => null,
            },
          )
          .poppable(onPop: () => setState(() => selected = null)),
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

  @override
  void initState() {
    super.initState();
    created++;
  }

  @override
  void applyRoute(OrderRoute route) {
    selectedItem = switch (route) {
      OrderOverview() => null,
      ItemAt(:final item) => item,
    };
  }

  @override
  List<DeclarativeNavigatable<OrderRoute>> build() {
    final order = navigator.order;
    return [
      OrderPage(
        order: order,
        onItem: (item) => navigate(ItemAt(item, const ItemOverview())),
        onRefresh: navigator.reload,
      ).page(onPop: null, route: const OrderOverview()),
      if (selectedItem case final item?)
        AsyncNavigator<Item, ItemRoute>(
              key: ValueKey(item),
              load: () => api.item(order.id, item),
              loading: const LoadingView('Loading item'),
              failed: (error, retry) => ErrorView(error: error, retry: retry),
              builder: (item, _) => ItemNavigator(item: item),
            )
            .mount(
              embed: (child) => ItemAt(item, child),
              unwrap: (route) => switch (route) {
                ItemAt(item: final routeItem, :final child)
                    when routeItem == item =>
                  child,
                _ => null,
              },
            )
            .poppable(onPop: () => setState(() => selectedItem = null)),
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
  List<DeclarativeNavigatable<ItemRoute>> build() => [
    ItemPage(
      item: navigator.item,
      onReviews: () => navigate(const ItemReviews()),
    ).page(onPop: null, route: const ItemOverview()),
    if (reviews)
      ReviewsPage(item: navigator.item).page(
        onPop: () => setState(() => reviews = false),
        route: const ItemReviews(),
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
