// A small shop with URLs: tabs (orders, settings), orders and their items
// loaded asynchronously, a sorted and filtered order list, real links, and an
// error dialog that has no URL.
//
//   /orders?sorting=name&status=open   order list, sorted and filtered
//   /orders/42                         order 42, loaded by id
//   /orders/42/items/3                 item 3 of order 42, loaded by id
//   /orders/42/items/3/reviews         its reviews
//   /settings, /settings/profile
//   /order/42                          an older spelling, shown as /orders/42
//
// Navigators below a loaded level receive the loaded model, never an id.
import 'dart:async';

import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';

// --- data ---------------------------------------------------------------------

class Order {
  const Order(this.id, {this.version = 1});
  final int id;
  final int version;
  String get title => 'Order #$id';
  String get status => id % 3 == 0 ? 'open' : 'shipped';
  List<int> get items => const [1, 2, 3];
}

class Item {
  const Item(this.orderId, this.id);
  final int orderId;
  final int id;
  String get name => 'Item $id of order #$orderId';
}

/// A fake backend; order 13 fails on its first load to show the error page.
class ShopApi {
  ShopApi({this.delay = const Duration(milliseconds: 600)});

  final Duration delay;
  final _failedOnce = <int>{};
  var _version = 0;

  List<Order> orders(OrderFilter filter) {
    final orders = [
      for (var id = 1; id <= 40; id++)
        if (filter.status == null || Order(id).status == filter.status)
          Order(id),
    ];
    return switch (filter.sort) {
      Sort.date => orders,
      Sort.name => orders..sort((a, b) => a.title.compareTo(b.title)),
    };
  }

  Future<Order> order(int id) async {
    await Future<void>.delayed(delay);
    if (id == 13 && _failedOnce.add(id)) {
      throw StateError('Order 13 could not be loaded, try again');
    }
    return Order(id, version: ++_version);
  }

  Future<Item> item(int orderId, int id) async {
    await Future<void>.delayed(delay);
    return Item(orderId, id);
  }

  Future<void> cancel(Order order) async {
    await Future<void>.delayed(delay);
    throw StateError('${order.title} has already been shipped');
  }
}

// --- routes: one sealed type per navigator, each with its own URL part -------

sealed class ShopRoute extends NavRoute {
  const ShopRoute();

  static ShopRoute fromUrl(Url url) => switch (url.segments) {
    [] => const OrdersTab(),
    // 'order' is the spelling of an older release
    ['orders' || 'order', ...] => OrdersTab(OrdersRoute.fromUrl(url.rest(1))),
    ['settings', ...] => SettingsTab(SettingsRoute.fromUrl(url.rest(1))),
    _ => throw NotFound(url),
  };

  @override
  Url toUrl() => switch (this) {
    OrdersTab(:final route) => const Url(['orders']) + route.toUrl(),
    SettingsTab(:final route) => const Url(['settings']) + route.toUrl(),
  };
}

final class const OrdersTab([final OrdersRoute route = const OrderList()])
    extends ShopRoute;

final class const SettingsTab([
  final SettingsRoute route = const SettingsHome(),
]) extends ShopRoute;

enum Sort { date, name }

final class const OrderFilter({
  final Sort sort = Sort.date,
  final String? status,
});

sealed class OrdersRoute extends NavRoute {
  const OrdersRoute();

  static OrdersRoute fromUrl(Url url) => switch (url.segments) {
    [] => OrderList(
      OrderFilter(
        // 'sort' is the query name of an older release
        sort:
            Sort.values.asNameMap()[url['sorting'] ?? url['sort']] ?? Sort.date,
        status: url['status'],
      ),
    ),
    [final int id, ...] => OrderAt(id, OrderRoute.fromUrl(url.rest(1))),
    _ => throw NotFound(url),
  };

  @override
  Url toUrl() => switch (this) {
    OrderList(:final filter) => Url(
      [],
      query: {
        if (filter.sort != Sort.date) 'sorting': [filter.sort.name],
        if (filter.status case final status?) 'status': [status],
      },
    ),
    OrderAt(:final id, :final route) => Url([id]) + route.toUrl(),
  };
}

final class const OrderList([final OrderFilter filter = const OrderFilter()])
    extends OrdersRoute;

final class const OrderAt(
  final int id, [
  final OrderRoute route = const OrderOverview(),
]) extends OrdersRoute;

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
    ItemAt(:final item, :final route) => Url(['items', item]) + route.toUrl(),
  };
}

final class const OrderOverview() extends OrderRoute;

final class const ItemAt(
  final int item, [
  final ItemRoute route = const ItemOverview(),
]) extends OrderRoute;

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

final class const ItemOverview() extends ItemRoute;

final class const ItemReviews() extends ItemRoute;

sealed class SettingsRoute extends NavRoute {
  const SettingsRoute();

  static SettingsRoute fromUrl(Url url) => switch (url.segments) {
    [] => const SettingsHome(),
    ['profile'] => const Profile(),
    _ => throw NotFound(url),
  };

  @override
  Url toUrl() => switch (this) {
    SettingsHome() => const Url([]),
    Profile() => const Url(['profile']),
  };
}

final class const SettingsHome() extends SettingsRoute;

final class const Profile() extends SettingsRoute;

FdrRouter<ShopRoute> createShopRouter(ShopApi api) {
  return FdrRouter(
    root: ShopNavigator(api: api),
    fromUrl: ShopRoute.fromUrl,
    notFound: (url) => NotFoundPage(url: url),
  );
}

// --- navigators ---------------------------------------------------------------

class ShopNavigator extends StatefulNavigator<ShopRoute> {
  const ShopNavigator({required this.api});
  final ShopApi api;

  @override
  StatefulNavigatorState<ShopNavigator, ShopRoute> createState() =>
      _ShopNavigatorState();
}

class _ShopNavigatorState
    extends StatefulNavigatorState<ShopNavigator, ShopRoute> {
  int tab = 0;
  OrdersRoute? orders;
  SettingsRoute? settings;

  @override
  void applyRoute(ShopRoute route) {
    switch (route) {
      case OrdersTab(:final route):
        tab = 0;
        orders = route;
      case SettingsTab(:final route):
        tab = 1;
        settings = route;
    }
  }

  void _select(int next) {
    if (next != tab) setState(() => tab = next, history: HistoryAction.push);
  }

  @override
  List<NavEntry<ShopRoute>> build() {
    return [
      TabsPage(
        index: tab,
        tabs: [
          NestedNavigator(
            at: OrdersTab.new,
            route: orders,
            child: OrdersNavigator(api: navigator.api),
          ),
          NestedNavigator(
            at: SettingsTab.new,
            route: settings,
            child: const SettingsNavigator(),
          ),
        ],
        builder: (context, tabs) => Scaffold(
          body: IndexedStack(index: tab, children: tabs),
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: _select,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.receipt_long),
                label: 'Orders',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    ];
  }
}

class OrdersNavigator extends StatefulNavigator<OrdersRoute> {
  const OrdersNavigator({required this.api});
  final ShopApi api;

  @override
  StatefulNavigatorState<OrdersNavigator, OrdersRoute> createState() =>
      _OrdersNavigatorState();
}

class _OrdersNavigatorState
    extends StatefulNavigatorState<OrdersNavigator, OrdersRoute> {
  OrderFilter filter = const OrderFilter();
  int? selected;
  OrderRoute? orderRoute;

  // not part of the URL, but kept in the browser history entry
  double scroll = 0;

  @override
  void applyRoute(OrdersRoute route) {
    switch (route) {
      case OrderList(:final filter):
        this.filter = filter;
        selected = null;
        orderRoute = null;
      case OrderAt(:final id, :final route):
        selected = id;
        orderRoute = route;
    }
  }

  @override
  Object? get historyState => scroll == 0 ? null : {'scroll': scroll};

  @override
  void restoreHistoryState(Object? state) {
    if (state case {'scroll': final num offset}) scroll = offset.toDouble();
  }

  @override
  List<NavEntry<OrdersRoute>> build() {
    final api = navigator.api;
    return [
      NavPage(
        route: OrderList(filter),
        child: OrderListPage(
          orders: api.orders(filter),
          filter: filter,
          // a new filter replaces the URL instead of adding history entries
          onFilter: (filter) => setState(
            () => this.filter = filter,
            history: HistoryAction.replace,
          ),
          initialScroll: scroll,
          onScroll: (offset) => scroll = offset,
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
          child: FutureNavigator(
            key: ValueKey(id),
            load: () => api.order(id),
            loading: const LoadingPage(title: 'Order'),
            error: (error, retry) => ErrorPage(error: error, retry: retry),
            builder: (order, reload) =>
                OrderNavigator(api: api, order: order, reload: reload),
          ),
        ),
    ];
  }
}

class OrderNavigator extends StatefulNavigator<OrderRoute> {
  const OrderNavigator({
    required this.api,
    required this.order,
    required this.reload,
  });
  final ShopApi api;
  final Order order;
  final Future<void> Function() reload;

  @override
  StatefulNavigatorState<OrderNavigator, OrderRoute> createState() =>
      _OrderNavigatorState();
}

class _OrderNavigatorState
    extends StatefulNavigatorState<OrderNavigator, OrderRoute> {
  int? item;
  ItemRoute? itemRoute;

  // in memory only: neither in the URL nor in the history entry
  Object? cancelError;

  @override
  void applyRoute(OrderRoute route) {
    switch (route) {
      case OrderOverview():
        item = null;
        itemRoute = null;
      case ItemAt(:final item, :final route):
        this.item = item;
        itemRoute = route;
    }
  }

  Future<void> _cancel() async {
    try {
      await navigator.api.cancel(navigator.order);
    } on Object catch (error) {
      if (mounted) setState(() => cancelError = error);
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
          onRefresh: navigator.reload,
          onCancel: _cancel,
        ),
      ),
      if (item case final id?)
        NestedNavigator(
          at: (route) => ItemAt(id, route),
          route: itemRoute,
          onPop: () => setState(() {
            item = null;
            itemRoute = null;
          }),
          child: FutureNavigator(
            key: ValueKey(id),
            load: () => navigator.api.item(order.id, id),
            loading: const LoadingPage(title: 'Item'),
            error: (error, retry) => ErrorPage(error: error, retry: retry),
            builder: (item, _) => ItemNavigator(item: item),
          ),
        ),
      if (cancelError case final error?)
        DialogPage(
          onPop: () => setState(() => cancelError = null),
          child: ErrorDialog(title: 'Could not cancel', error: error),
        ),
    ];
  }
}

class ItemNavigator extends StatefulNavigator<ItemRoute> {
  const ItemNavigator({required this.item});
  final Item item;

  @override
  StatefulNavigatorState<ItemNavigator, ItemRoute> createState() =>
      _ItemNavigatorState();
}

class _ItemNavigatorState
    extends StatefulNavigatorState<ItemNavigator, ItemRoute> {
  bool reviews = false;

  @override
  void applyRoute(ItemRoute route) => reviews = route is ItemReviews;

  @override
  List<NavEntry<ItemRoute>> build() {
    return [
      NavPage(
        route: const ItemOverview(),
        child: ItemPage(item: navigator.item),
      ),
      if (reviews)
        NavPage(
          route: const ItemReviews(),
          onPop: () => setState(() => reviews = false),
          child: ReviewsPage(item: navigator.item),
        ),
    ];
  }
}

class SettingsNavigator extends StatefulNavigator<SettingsRoute> {
  const SettingsNavigator();

  @override
  StatefulNavigatorState<SettingsNavigator, SettingsRoute> createState() =>
      _SettingsNavigatorState();
}

class _SettingsNavigatorState
    extends StatefulNavigatorState<SettingsNavigator, SettingsRoute> {
  bool profile = false;

  @override
  void applyRoute(SettingsRoute route) => profile = route is Profile;

  @override
  List<NavEntry<SettingsRoute>> build() {
    return [
      const NavPage(route: SettingsHome(), child: SettingsPage()),
      if (profile)
        NavPage(
          route: const Profile(),
          onPop: () => setState(() => profile = false),
          child: const ProfilePage(),
        ),
    ];
  }
}

// --- pages --------------------------------------------------------------------

class OrderListPage extends StatefulWidget {
  const OrderListPage({
    super.key,
    required this.orders,
    required this.filter,
    required this.onFilter,
    required this.initialScroll,
    required this.onScroll,
  });
  final List<Order> orders;
  final OrderFilter filter;
  final ValueChanged<OrderFilter> onFilter;
  final double initialScroll;
  final ValueChanged<double> onScroll;

  @override
  State<OrderListPage> createState() => _OrderListPageState();
}

class _OrderListPageState extends State<OrderListPage> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController(initialScrollOffset: widget.initialScroll)
      ..addListener(() => widget.onScroll(_controller.offset));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = widget.filter;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders'),
        actions: [
          IconButton(
            tooltip: 'Sort by ${filter.sort == Sort.date ? 'name' : 'date'}',
            icon: Icon(
              filter.sort == Sort.date ? Icons.sort_by_alpha : Icons.event,
            ),
            onPressed: () => widget.onFilter(
              OrderFilter(
                sort: filter.sort == Sort.date ? Sort.name : Sort.date,
                status: filter.status,
              ),
            ),
          ),
          FilterChip(
            label: const Text('Open only'),
            selected: filter.status == 'open',
            onSelected: (open) => widget.onFilter(
              OrderFilter(sort: filter.sort, status: open ? 'open' : null),
            ),
          ),
        ],
      ),
      body: ListView(
        controller: _controller,
        children: [
          for (final order in widget.orders)
            RouteLink(
              route: OrderAt(order.id),
              builder: (context, open) => ListTile(
                title: Text(order.title),
                subtitle: Text(
                  order.id == 13
                      ? '${order.status}, fails on first load'
                      : order.status,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: open,
              ),
            ),
        ],
      ),
    );
  }
}

class OrderPage extends StatelessWidget {
  const OrderPage({
    super.key,
    required this.order,
    required this.onRefresh,
    required this.onCancel,
  });
  final Order order;
  final Future<void> Function() onRefresh;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${order.title} (v${order.version})')),
      body: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          children: [
            for (final item in order.items)
              RouteLink(
                route: ItemAt(item),
                builder: (context, open) => ListTile(
                  title: Text('Item $item'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: open,
                ),
              ),
            ListTile(
              title: const Text('Cancel order'),
              leading: const Icon(Icons.cancel_outlined),
              onTap: onCancel,
            ),
          ],
        ),
      ),
    );
  }
}

class ItemPage extends StatelessWidget {
  const ItemPage({super.key, required this.item});
  final Item item;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(item.name)),
      body: Center(
        child: RouteLink(
          route: const ItemReviews(),
          builder: (context, open) =>
              FilledButton(onPressed: open, child: const Text('Reviews')),
        ),
      ),
    );
  }
}

class ReviewsPage extends StatelessWidget {
  const ReviewsPage({super.key, required this.item});
  final Item item;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Reviews of ${item.name}')),
      body: const Center(child: Text('★★★★☆')),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: RouteLink(
        route: const Profile(),
        builder: (context, open) => ListTile(
          title: const Text('Profile'),
          trailing: const Icon(Icons.chevron_right),
          onTap: open,
        ),
      ),
    );
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Center(
        // a route of the root: leads into the orders tab
        child: RouteLink(
          route: const OrdersTab(OrderAt(42)),
          builder: (context, open) =>
              TextButton(onPressed: open, child: const Text('Your last order')),
        ),
      ),
    );
  }
}

class LoadingPage extends StatelessWidget {
  const LoadingPage({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}

class ErrorPage extends StatelessWidget {
  const ErrorPage({super.key, required this.error, required this.retry});
  final Object error;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Something went wrong')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$error'),
            const SizedBox(height: 16),
            FilledButton(onPressed: retry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class ErrorDialog extends StatelessWidget {
  const ErrorDialog({super.key, required this.title, required this.error});
  final String title;
  final Object error;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Text('$error'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key, required this.url});
  final Url url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Not found')),
      body: Center(child: Text('Nothing at $url')),
    );
  }
}
