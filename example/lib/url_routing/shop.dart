// A small shop with URLs: a persistent tab bar (orders, settings), orders and
// their items loaded asynchronously, and a not-found page.
//
//   /orders                         order list (scroll offset kept in history)
//   /orders/42                      order 42, loaded by id
//   /orders/42/items/3              item 3 of order 42, loaded by id
//   /orders/42/items/3/reviews      its reviews
//   /settings, /settings/profile
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
}

// --- routes -------------------------------------------------------------------

sealed class ShopRoute {
  const ShopRoute();
}

final class OrdersTab extends ShopRoute {
  const OrdersTab([this.child = const OrderList()]);
  final OrdersRoute child;
}

final class SettingsTab extends ShopRoute {
  const SettingsTab([this.child = const SettingsHome()]);
  final SettingsRoute child;
}

final class NotFound extends ShopRoute {
  const NotFound(this.uri);
  final Uri uri;
}

sealed class OrdersRoute {
  const OrdersRoute();
}

final class OrderList extends OrdersRoute {
  const OrderList();
}

final class OrderAt extends OrdersRoute {
  const OrderAt(this.id, [this.child = const OrderOverview()]);
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
  const ItemAt(this.item, [this.child = const ItemOverview()]);
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

sealed class SettingsRoute {
  const SettingsRoute();
}

final class SettingsHome extends SettingsRoute {
  const SettingsHome();
}

final class Profile extends SettingsRoute {
  const Profile();
}

// --- codecs: one per navigator, each unaware of where it is mounted ------------

final _itemOverview = Case<ItemRoute, ItemOverview>(
  end.iso(to: (_) => const ItemOverview(), from: (_) => ()),
);
final _itemReviews = Case<ItemRoute, ItemReviews>(
  lit('reviews').then(end).iso(to: (_) => const ItemReviews(), from: (_) => ()),
);
final itemCodec = SumCodec<ItemRoute>(
  cases: [_itemOverview, _itemReviews],
  select: (route) => switch (route) {
    final ItemOverview r => _itemOverview.bind(r),
    final ItemReviews r => _itemReviews.bind(r),
  },
);

final _orderOverview = Case<OrderRoute, OrderOverview>(
  end.iso(to: (_) => const OrderOverview(), from: (_) => ()),
);
final _itemAt = Case<OrderRoute, ItemAt>(
  lit('items').then(Seg.int.and(itemCodec)).iso(
        to: (r) => ItemAt(r.$1, r.$2),
        from: (r) => (r.item, r.child),
      ),
);
final orderCodec = SumCodec<OrderRoute>(
  cases: [_orderOverview, _itemAt],
  select: (route) => switch (route) {
    final OrderOverview r => _orderOverview.bind(r),
    final ItemAt r => _itemAt.bind(r),
  },
);

final _orderList = Case<OrdersRoute, OrderList>(
  end.iso(to: (_) => const OrderList(), from: (_) => ()),
);
final _orderAt = Case<OrdersRoute, OrderAt>(
  Seg.int.and(orderCodec).iso(
    to: (r) => OrderAt(r.$1, r.$2),
    from: (r) => (r.id, r.child),
  ),
);
final ordersCodec = SumCodec<OrdersRoute>(
  cases: [_orderList, _orderAt],
  select: (route) => switch (route) {
    final OrderList r => _orderList.bind(r),
    final OrderAt r => _orderAt.bind(r),
  },
);

final _settingsHome = Case<SettingsRoute, SettingsHome>(
  end.iso(to: (_) => const SettingsHome(), from: (_) => ()),
);
final _profile = Case<SettingsRoute, Profile>(
  lit('profile').then(end).iso(to: (_) => const Profile(), from: (_) => ()),
);
final settingsCodec = SumCodec<SettingsRoute>(
  cases: [_settingsHome, _profile],
  select: (route) => switch (route) {
    final SettingsHome r => _settingsHome.bind(r),
    final Profile r => _profile.bind(r),
  },
);

final _ordersTab = Case<ShopRoute, OrdersTab>(
  lit('orders').then(ordersCodec).iso(to: OrdersTab.new, from: (r) => r.child),
);
final _settingsTab = Case<ShopRoute, SettingsTab>(
  lit('settings')
      .then(settingsCodec)
      .iso(to: SettingsTab.new, from: (r) => r.child),
);
final _notFound = Case<ShopRoute, NotFound>(
  const Rest().iso(to: NotFound.new, from: (r) => r.uri),
);
final shopCodec = SumCodec<ShopRoute>(
  cases: [_ordersTab, _settingsTab, alias(end, (_) => const OrdersTab())],
  select: (route) => switch (route) {
    final OrdersTab r => _ordersTab.bind(r),
    final SettingsTab r => _settingsTab.bind(r),
    final NotFound r => _notFound.bind(r),
  },
);

FdrRouter<ShopRoute> createShopRouter(ShopApi api) {
  return FdrRouter<ShopRoute>(
    root: ShopNavigator(api: api),
    codec: shopCodec,
    notFound: NotFound.new,
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
  Uri? notFound;

  @override
  void applyRoute(ShopRoute route) {
    switch (route) {
      case OrdersTab():
        tab = 0;
        notFound = null;
      case SettingsTab():
        tab = 1;
        notFound = null;
      case NotFound(:final uri):
        notFound = uri;
    }
  }

  void _select(int next) {
    if (next != tab) setState(() => tab = next, history: HistoryAction.push);
  }

  @override
  List<DeclarativeNavigatable<ShopRoute>> build() {
    return [
      shell(
        active: tab,
        branches: [
          OrdersNavigator(api: navigator.api).mount(
            embed: OrdersTab.new,
            unwrap: (route) => switch (route) {
              OrdersTab(:final child) => child,
              _ => null,
            },
          ),
          const SettingsNavigator().mount(
            embed: SettingsTab.new,
            unwrap: (route) => switch (route) {
              SettingsTab(:final child) => child,
              _ => null,
            },
          ),
        ],
        builder: (context, branches, active) => Scaffold(
          body: IndexedStack(index: active, children: branches),
          bottomNavigationBar: NavigationBar(
            selectedIndex: active,
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
      if (notFound case final uri?)
        NotFoundPage(uri: uri).page(
          onPop: () => setState(() => notFound = null),
          route: NotFound(uri),
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
  int? selected;

  // not part of the URL, but kept in the browser history entry
  double scroll = 0;

  @override
  void applyRoute(OrdersRoute route) {
    selected = switch (route) {
      OrderList() => null,
      OrderAt(:final id) => id,
    };
  }

  @override
  Object? get historyState => scroll == 0 ? null : {'scroll': scroll};

  @override
  void restoreHistoryState(Object? state) {
    if (state case {'scroll': final num offset}) scroll = offset.toDouble();
  }

  @override
  List<DeclarativeNavigatable<OrdersRoute>> build() {
    final api = navigator.api;
    return [
      OrderListPage(
        initialScroll: scroll,
        onScroll: (offset) => scroll = offset,
        onOpen: (id) => navigate(OrderAt(id)),
      ).page(onPop: null, route: const OrderList()),
      if (selected case final id?)
        AsyncNavigator<Order, OrderRoute>(
          key: ValueKey(id),
          load: () => api.order(id),
          loading: const LoadingPage(title: 'Order'),
          failed: (error, retry) => ErrorPage(error: error, retry: retry),
          builder: (order, reload) =>
              OrderNavigator(api: api, order: order, reload: reload),
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

  @override
  void applyRoute(OrderRoute route) {
    item = switch (route) {
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
        onItem: (item) => navigate(ItemAt(item)),
        onRefresh: navigator.reload,
      ).page(onPop: null, route: const OrderOverview()),
      if (item case final id?)
        AsyncNavigator<Item, ItemRoute>(
          key: ValueKey(id),
          load: () => navigator.api.item(order.id, id),
          loading: const LoadingPage(title: 'Item'),
          failed: (error, retry) => ErrorPage(error: error, retry: retry),
          builder: (item, _) => ItemNavigator(item: item),
        )
            .mount(
              embed: (child) => ItemAt(id, child),
              unwrap: (route) => switch (route) {
                ItemAt(item: final routeItem, :final child)
                    when routeItem == id =>
                  child,
                _ => null,
              },
            )
            .poppable(onPop: () => setState(() => item = null)),
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
  List<DeclarativeNavigatable<ItemRoute>> build() {
    return [
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
  List<DeclarativeNavigatable<SettingsRoute>> build() {
    return [
      SettingsPage(onProfile: () => navigate(const Profile()))
          .page(onPop: null, route: const SettingsHome()),
      if (profile)
        const ProfilePage().page(
          onPop: () => setState(() => profile = false),
          route: const Profile(),
        ),
    ];
  }
}

// --- pages --------------------------------------------------------------------

class OrderListPage extends StatefulWidget {
  const OrderListPage({
    super.key,
    required this.initialScroll,
    required this.onScroll,
    required this.onOpen,
  });
  final double initialScroll;
  final ValueChanged<double> onScroll;
  final ValueChanged<int> onOpen;

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
    return Scaffold(
      appBar: AppBar(title: const Text('Orders')),
      body: ListView.builder(
        controller: _controller,
        itemCount: 40,
        itemBuilder: (context, index) {
          final id = index + 1;
          return ListTile(
            title: Text('Order #$id'),
            subtitle: id == 13 ? const Text('fails on first load') : null,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => widget.onOpen(id),
          );
        },
      ),
    );
  }
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${order.title} (v${order.version})')),
      body: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          children: [
            for (final item in order.items)
              ListTile(
                title: Text('Item $item'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onItem(item),
              ),
          ],
        ),
      ),
    );
  }
}

class ItemPage extends StatelessWidget {
  const ItemPage({super.key, required this.item, required this.onReviews});
  final Item item;
  final VoidCallback onReviews;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(item.name)),
      body: Center(
        child: FilledButton(
          onPressed: onReviews,
          child: const Text('Reviews'),
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
  const SettingsPage({super.key, required this.onProfile});
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListTile(
        title: const Text('Profile'),
        trailing: const Icon(Icons.chevron_right),
        onTap: onProfile,
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
      body: const Center(child: Text('Profile')),
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

class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key, required this.uri});
  final Uri uri;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Not found')),
      body: Center(child: Text('Nothing at $uri')),
    );
  }
}
