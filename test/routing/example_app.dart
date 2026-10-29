// Worked example: root (login/home) -> home (tabs) -> orders (list/detail
// + popup) and settings (root/profile). Every navigator owns a sealed route
// type and a codec; the parent's route embeds the child's.
import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';

// --- routes ---------------------------------------------------------------

sealed class AppRoute {
  const AppRoute();
}

final class LoginRoute extends AppRoute {
  const LoginRoute({this.next});
  final HomeRoute? next;
}

final class HomeAt extends AppRoute {
  const HomeAt(this.child);
  final HomeRoute child;
}

final class NotFoundRoute extends AppRoute {
  const NotFoundRoute(this.uri);
  final Uri uri;
}

sealed class HomeRoute {
  const HomeRoute();
}

final class OrdersAt extends HomeRoute {
  const OrdersAt(this.child);
  final OrdersRoute child;
}

final class SettingsAt extends HomeRoute {
  const SettingsAt(this.child);
  final SettingsRoute child;
}

sealed class OrdersRoute {
  const OrdersRoute();
}

final class OrderList extends OrdersRoute {
  const OrderList();
}

final class OrderDetail extends OrdersRoute {
  const OrderDetail(this.id);
  final int id;
}

final class OrderItem extends OrdersRoute {
  const OrderItem(this.id, this.item);
  final int id;
  final int item;
}

sealed class SettingsRoute {
  const SettingsRoute();
}

final class SettingsRoot extends SettingsRoute {
  const SettingsRoot();
}

final class SettingsProfile extends SettingsRoute {
  const SettingsProfile();
}

// --- codecs: one per navigator, composed bottom-up ------------------------

final orderDetail = Case<OrdersRoute, OrderDetail>(
  Seg.int.atEnd.iso(to: OrderDetail.new, from: (r) => r.id),
);
final orderItem = Case<OrdersRoute, OrderItem>(
  Seg.int.and(lit('items').then(Seg.int)).atEnd
      .iso(to: (r) => OrderItem(r.$1, r.$2), from: (r) => (r.id, r.item)),
);
final orderList = Case<OrdersRoute, OrderList>(
  end.iso(to: (_) => const OrderList(), from: (_) => ()),
);
final ordersCodec = SumCodec<OrdersRoute>(
  cases: [orderDetail, orderItem, orderList],
  select: (r) => switch (r) {
    final OrderDetail d => orderDetail.bind(d),
    final OrderItem i => orderItem.bind(i),
    final OrderList l => orderList.bind(l),
  },
);

final settingsProfile = Case<SettingsRoute, SettingsProfile>(
  lit('profile')
      .then(end)
      .iso(to: (_) => const SettingsProfile(), from: (_) => ()),
);
final settingsRoot = Case<SettingsRoute, SettingsRoot>(
  end.iso(to: (_) => const SettingsRoot(), from: (_) => ()),
);
final settingsCodec = SumCodec<SettingsRoute>(
  cases: [settingsProfile, settingsRoot],
  select: (r) => switch (r) {
    final SettingsProfile p => settingsProfile.bind(p),
    final SettingsRoot r => settingsRoot.bind(r),
  },
);

// the orders embedding is declared once (lens) and used by the codec below and
// by HomeNavigatorState.build; settings shows the explicit closure form
const ordersLens = RouteLens<HomeRoute, OrdersRoute>(
  embed: OrdersAt.new,
  unwrap: _ordersOf,
);

OrdersRoute? _ordersOf(HomeRoute r) => switch (r) {
  OrdersAt(:final child) => child,
  SettingsAt() => null,
};

final ordersAt = lit('orders').then(ordersCodec).embedded(ordersLens);
final settingsAt = Case<HomeRoute, SettingsAt>(
  lit('settings')
      .then(settingsCodec)
      .iso(to: SettingsAt.new, from: (r) => r.child),
);
final homeCodec = SumCodec<HomeRoute>(
  cases: [ordersAt, settingsAt],
  select: (r) => switch (r) {
    OrdersAt(:final child) => ordersAt.bind(child),
    final SettingsAt s => settingsAt.bind(s),
  },
);

// the home navigator is mounted at the root without a prefix (shell)
final homeAt = Case<AppRoute, HomeAt>(
  homeCodec.iso(to: HomeAt.new, from: (r) => r.child),
);
final login = Case<AppRoute, LoginRoute>(
  lit('login')
      .then(Query.route('next', homeCodec).optional)
      .atEnd
      .iso(
        to: (next) => LoginRoute(next: next),
        from: (r) => r.next,
      ),
);
// parse-only aliases: '/' and the legacy '/order/:id'
final rootAlias = alias<AppRoute, Unit>(
  end,
  (_) => const HomeAt(OrdersAt(OrderList())),
);
final legacyOrder = alias<AppRoute, int>(
  lit('order').then(Seg.int).atEnd,
  (id) => HomeAt(OrdersAt(OrderDetail(id))),
);
// print-only: keeps whatever the user typed in the address bar
final notFound = Case<AppRoute, NotFoundRoute>(
  const Rest().iso(to: NotFoundRoute.new, from: (r) => r.uri),
);
final appCodec = SumCodec<AppRoute>(
  cases: [login, rootAlias, legacyOrder, homeAt],
  select: (r) => switch (r) {
    final LoginRoute l => login.bind(l),
    final HomeAt h => homeAt.bind(h),
    final NotFoundRoute n => notFound.bind(n),
  },
);

// --- navigators -----------------------------------------------------------

class AppNavigator extends StatefulNavigator<AppRoute> {
  const AppNavigator({required this.loggedIn});
  final bool loggedIn;

  @override
  AppNavigatorState createState() => AppNavigatorState();
}

class AppNavigatorState extends StatefulNavigatorState<AppNavigator, AppRoute> {
  static int applied = 0;

  late bool loggedIn;
  HomeRoute? pendingNext;
  Uri? notFoundUri;

  @override
  void initState() {
    super.initState();
    loggedIn = navigator.loggedIn;
  }

  @override
  void applyRoute(AppRoute route) {
    applied++;
    switch (route) {
      case LoginRoute(:final next):
        notFoundUri = null;
        // a logged-in user opening /login is redirected home (URL replaced)
        if (!loggedIn) pendingNext = next;
      case HomeAt(:final child):
        notFoundUri = null;
        // the child part is only distributed while home is mounted; keep it
        // as the typed return target of the login page otherwise
        if (!loggedIn) pendingNext = child;
      case NotFoundRoute(:final uri):
        notFoundUri = uri;
    }
  }

  void login() {
    loggedIn = true;
    final target = pendingNext ?? const OrdersAt(OrderList());
    pendingNext = null;
    navigate(HomeAt(target), history: HistoryAction.replace);
  }

  void logout() {
    loggedIn = false;
    navigate(const LoginRoute(), history: HistoryAction.push);
  }

  @override
  List<DeclarativeNavigatable<AppRoute>> build() => [
    if (!loggedIn)
      LoginPage(onLogin: login)
          .page(onPop: null, route: LoginRoute(next: pendingNext))
    else
      HomeNavigator(onLogout: logout).mount(
        embed: HomeAt.new,
        unwrap: (r) => switch (r) {
          HomeAt(:final child) => child,
          LoginRoute() || NotFoundRoute() => null,
        },
      ),
    if (notFoundUri case final uri?)
      NotFoundPage(uri: uri).page(
        onPop: () => setState(() => notFoundUri = null),
        route: NotFoundRoute(uri),
      ),
  ];
}

enum HomeTab { orders, settings }

class HomeNavigator extends StatefulNavigator<HomeRoute> {
  const HomeNavigator({required this.onLogout});
  final VoidCallback onLogout;

  @override
  HomeNavigatorState createState() => HomeNavigatorState();
}

class HomeNavigatorState
    extends StatefulNavigatorState<HomeNavigator, HomeRoute> {
  static int created = 0;

  HomeTab tab = HomeTab.orders;

  @override
  void initState() {
    super.initState();
    created++;
  }

  @override
  void applyRoute(HomeRoute route) {
    tab = switch (route) {
      OrdersAt() => HomeTab.orders,
      SettingsAt() => HomeTab.settings,
    };
  }

  void switchTab(HomeTab next) {
    if (next == tab) return;
    setState(() => tab = next, history: HistoryAction.push);
  }

  // a persistent tab bar: each tab is a nested navigator with its own stack
  @override
  List<DeclarativeNavigatable<HomeRoute>> build() => [
    shell(
      active: tab.index,
      branches: [
        OrdersNavigator(
          onSwitchTab: switchTab,
          onLogout: navigator.onLogout,
        ).mountWith(ordersLens),
        SettingsNavigator(onSwitchTab: switchTab).mount(
          embed: SettingsAt.new,
          unwrap: (r) => switch (r) {
            SettingsAt(:final child) => child,
            OrdersAt() => null,
          },
        ),
      ],
      builder: (context, branches, active) => HomeChrome(
        branches: branches,
        active: active,
        onSelect: (i) => switchTab(HomeTab.values[i]),
      ),
    ),
  ];
}

class HomeChrome extends StatefulWidget {
  const HomeChrome({
    super.key,
    required this.branches,
    required this.active,
    required this.onSelect,
  });
  final List<Widget> branches;
  final int active;
  final ValueChanged<int> onSelect;

  @override
  State<HomeChrome> createState() => _HomeChromeState();
}

class _HomeChromeState extends State<HomeChrome> {
  static int created = 0;

  @override
  void initState() {
    super.initState();
    created++;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: widget.active, children: widget.branches),
    bottomNavigationBar: NavigationBar(
      selectedIndex: widget.active,
      onDestinationSelected: widget.onSelect,
      destinations: const [
        NavigationDestination(
          key: Key('nav-orders'),
          icon: Icon(Icons.list),
          label: 'Orders tab',
        ),
        NavigationDestination(
          key: Key('nav-settings'),
          icon: Icon(Icons.settings),
          label: 'Settings tab',
        ),
      ],
    ),
  );
}

/// How often the persistent chrome was created (stays 1 while it persists).
int get homeChromeCreated => _HomeChromeState.created;
set homeChromeCreated(int value) => _HomeChromeState.created = value;

class OrdersNavigator extends StatefulNavigator<OrdersRoute> {
  const OrdersNavigator({required this.onSwitchTab, required this.onLogout});
  final ValueChanged<HomeTab> onSwitchTab;
  final VoidCallback onLogout;

  @override
  OrdersNavigatorState createState() => OrdersNavigatorState();
}

class OrdersNavigatorState
    extends StatefulNavigatorState<OrdersNavigator, OrdersRoute> {
  static int created = 0;
  static int applied = 0;
  static int builds = 0;
  static int detailPops = 0;
  static OrdersNavigatorState? latest;

  int? selectedId;
  int? selectedItem;
  bool showPopup = false;
  // non-URL state: neither in the URL nor in the history state
  int counter = 0;
  // non-URL state kept in the history entry / restoration bucket
  double scroll = 0;

  @override
  void initState() {
    super.initState();
    created++;
    latest = this;
  }

  @override
  void applyRoute(OrdersRoute route) {
    applied++;
    showPopup = false;
    final (id, item) = switch (route) {
      OrderList() => (null, null),
      OrderDetail(:final id) => (id, null),
      OrderItem(:final id, :final item) => (id, item),
    };
    selectedId = id;
    selectedItem = item;
  }

  @override
  Object? get historyState => scroll == 0 ? null : {'scroll': scroll};

  @override
  void restoreHistoryState(Object? state) {
    if (state is Map) scroll = (state['scroll']! as num).toDouble();
  }

  @override
  List<DeclarativeNavigatable<OrdersRoute>> build() {
    builds++;
    return [
      OrderListPage(
        counter: counter,
        scroll: scroll,
        onOpen: (id) => navigate(OrderDetail(id)),
        onBump: () => setState(() => counter++),
        onScroll: (value) => scroll = value,
        onSwitchTab: navigator.onSwitchTab,
      ).page(onPop: null, route: const OrderList()),
      if (selectedId case final id?)
        OrderDetailPage(
          id: id,
          counter: counter,
          onBump: () => setState(() => counter++),
          onPopup: () => setState(() => showPopup = true),
          onItem: (item) => navigate(OrderItem(id, item)),
          onDone: () => setState(() => selectedId = null),
          onSwitchTab: navigator.onSwitchTab,
          onLogout: navigator.onLogout,
        ).page(
          onPop: () {
            detailPops++;
            setState(() => selectedId = null);
          },
          route: OrderDetail(id),
        ),
      if ((selectedId, selectedItem) case (final id?, final item?))
        ItemPage(
          id: id,
          item: item,
          onDone: () => setState(() => selectedItem = null),
        ).page(
          onPop: () => setState(() => selectedItem = null),
          route: OrderItem(id, item),
        ),
      if (showPopup)
        const PopupContent().popup(
          onPop: () => setState(() => showPopup = false),
        ),
    ];
  }
}

class SettingsNavigator extends StatefulNavigator<SettingsRoute> {
  const SettingsNavigator({required this.onSwitchTab});
  final ValueChanged<HomeTab> onSwitchTab;

  @override
  SettingsNavigatorState createState() => SettingsNavigatorState();
}

class SettingsNavigatorState
    extends StatefulNavigatorState<SettingsNavigator, SettingsRoute> {
  bool profile = false;

  @override
  void applyRoute(SettingsRoute route) {
    profile = switch (route) {
      SettingsProfile() => true,
      SettingsRoot() => false,
    };
  }

  @override
  List<DeclarativeNavigatable<SettingsRoute>> build() {
    return [
      SettingsPage(
        onProfile: () => navigate(const SettingsProfile()),
        onSwitchTab: navigator.onSwitchTab,
      ).page(onPop: null, route: const SettingsRoot()),
      if (profile)
        const ProfilePage().page(
          onPop: () => setState(() => profile = false),
          route: const SettingsProfile(),
        ),
    ];
  }
}

// --- widgets --------------------------------------------------------------

class LoginPage extends StatelessWidget {
  const LoginPage({super.key, required this.onLogin});
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Login')),
    body: TextButton(
      key: const Key('login'),
      onPressed: onLogin,
      child: const Text('Log in'),
    ),
  );
}

class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key, required this.uri});
  final Uri uri;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Not found')),
    body: Text('No page at $uri'),
  );
}

class OrderListPage extends StatelessWidget {
  const OrderListPage({
    super.key,
    required this.counter,
    required this.scroll,
    required this.onOpen,
    required this.onBump,
    required this.onScroll,
    required this.onSwitchTab,
  });
  final int counter;
  final double scroll;
  final ValueChanged<int> onOpen;
  final VoidCallback onBump;
  final ValueChanged<double> onScroll;
  final ValueChanged<HomeTab> onSwitchTab;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Orders')),
    body: Column(
      children: [
        Text('counter $counter'),
        Text('scroll $scroll'),
        TextButton(
          key: const Key('open-42'),
          onPressed: () => onOpen(42),
          child: const Text('42'),
        ),
        TextButton(
          key: const Key('open-7'),
          onPressed: () => onOpen(7),
          child: const Text('7'),
        ),
        TextButton(
          key: const Key('bump'),
          onPressed: onBump,
          child: const Text('bump'),
        ),
        TextButton(
          key: const Key('scroll'),
          onPressed: () => onScroll(120),
          child: const Text('scroll'),
        ),
        TextButton(
          key: const Key('tab-settings'),
          onPressed: () => onSwitchTab(HomeTab.settings),
          child: const Text('settings'),
        ),
      ],
    ),
  );
}

class OrderDetailPage extends StatelessWidget {
  const OrderDetailPage({
    super.key,
    required this.id,
    required this.counter,
    required this.onBump,
    required this.onPopup,
    required this.onItem,
    required this.onDone,
    required this.onSwitchTab,
    required this.onLogout,
  });
  final int id;
  final int counter;
  final VoidCallback onBump;
  final VoidCallback onPopup;
  final ValueChanged<int> onItem;
  final VoidCallback onDone;
  final ValueChanged<HomeTab> onSwitchTab;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Order $id')),
    body: Column(
      children: [
        Text('counter $counter'),
        TextButton(
          key: const Key('bump'),
          onPressed: onBump,
          child: const Text('bump'),
        ),
        TextButton(
          key: const Key('popup'),
          onPressed: onPopup,
          child: const Text('popup'),
        ),
        TextButton(
          key: const Key('item-3'),
          onPressed: () => onItem(3),
          child: const Text('item 3'),
        ),
        TextButton(
          key: const Key('done'),
          onPressed: onDone,
          child: const Text('done'),
        ),
        TextButton(
          key: const Key('tab-settings'),
          onPressed: () => onSwitchTab(HomeTab.settings),
          child: const Text('settings'),
        ),
        TextButton(
          key: const Key('logout'),
          onPressed: onLogout,
          child: const Text('logout'),
        ),
      ],
    ),
  );
}

class ItemPage extends StatelessWidget {
  const ItemPage({
    super.key,
    required this.id,
    required this.item,
    required this.onDone,
  });
  final int id;
  final int item;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Item $item of $id')),
    body: TextButton(
      key: const Key('done'),
      onPressed: onDone,
      child: const Text('done'),
    ),
  );
}

class PopupContent extends StatelessWidget {
  const PopupContent({super.key});

  @override
  Widget build(BuildContext context) =>
      const SizedBox(height: 100, child: Text('Popup content'));
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.onProfile,
    required this.onSwitchTab,
  });
  final VoidCallback onProfile;
  final ValueChanged<HomeTab> onSwitchTab;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: Column(
      children: [
        TextButton(
          key: const Key('profile'),
          onPressed: onProfile,
          child: const Text('profile'),
        ),
        TextButton(
          key: const Key('tab-orders'),
          onPressed: () => onSwitchTab(HomeTab.orders),
          child: const Text('orders'),
        ),
      ],
    ),
  );
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Profile')),
    body: const Text('Profile body'),
  );
}

// --- a single root page, optionally guarded by a PopScope -------------------

class GuardedNavigator extends StatefulNavigator<FixedRoute> {
  const GuardedNavigator({required this.guarded});
  final bool guarded;

  @override
  GuardedNavigatorState createState() => GuardedNavigatorState();
}

class GuardedNavigatorState
    extends StatefulNavigatorState<GuardedNavigator, FixedRoute> {
  static int vetoes = 0;

  @override
  void applyRoute(FixedRoute route) {}

  @override
  List<DeclarativeNavigatable<FixedRoute>> build() => [
    PopScope<Object?>(
      canPop: !navigator.guarded,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) vetoes++;
      },
      child: const Text('guarded root'),
    ).page(onPop: null, route: const FixedTop()),
  ];
}

// --- a navigator with two non-poppable pages, for the imperative-pop guard --

sealed class FixedRoute {
  const FixedRoute();
}

final class FixedTop extends FixedRoute {
  const FixedTop();
}

final fixedTop = Case<FixedRoute, FixedTop>(
  end.iso(to: (_) => const FixedTop(), from: (_) => ()),
);
final fixedCodec = SumCodec<FixedRoute>(
  cases: [fixedTop],
  select: (r) => switch (r) {
    final FixedTop t => fixedTop.bind(t),
  },
);

class FixedNavigator extends StatefulNavigator<FixedRoute> {
  const FixedNavigator();

  @override
  FixedNavigatorState createState() => FixedNavigatorState();
}

class FixedNavigatorState
    extends StatefulNavigatorState<FixedNavigator, FixedRoute> {
  @override
  void applyRoute(FixedRoute route) {}

  @override
  List<DeclarativeNavigatable<FixedRoute>> build() => [
    const Text('bottom').page(onPop: null),
    const Text('top').page(onPop: null, route: const FixedTop()),
  ];
}
