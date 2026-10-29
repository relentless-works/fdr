// Worked example: root (login/home) -> home (tabs) -> orders (list/detail
// + dialog) and settings (root/profile). Every navigator owns a sealed route
// type with fromUrl/toUrl for its own level; a parent route contains the
// child's.
import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';

// --- routes ---------------------------------------------------------------

sealed class AppRoute extends NavRoute {
  const AppRoute();

  static AppRoute fromUrl(Url url) => switch (url.segments) {
    ['login'] => LoginRoute(next: _next(url['next'])),
    [] => const HomeAt(OrdersAt(OrderList())),
    // the order page's URL of an older release
    ['order', final int id] => HomeAt(OrdersAt(OrderDetail(id))),
    _ => HomeAt(HomeRoute.fromUrl(url)),
  };

  @override
  Url toUrl() => switch (this) {
    LoginRoute(:final next) => Url(
      ['login'],
      query: {
        if (next != null) 'next': ['${next.toUrl()}'],
      },
    ),
    HomeAt(:final child) => child.toUrl(),
  };

  // a return target that no longer exists is dropped, not an error
  static HomeRoute? _next(String? next) {
    if (next == null) return null;
    try {
      return HomeRoute.fromUrl(Url.parse(Uri.parse(next)));
    } on NotFound {
      return null;
    }
  }
}

final class LoginRoute extends AppRoute {
  const LoginRoute({this.next});
  final HomeRoute? next;
}

final class HomeAt extends AppRoute {
  const HomeAt(this.child);
  final HomeRoute child;
}

sealed class HomeRoute extends NavRoute {
  const HomeRoute();

  static HomeRoute fromUrl(Url url) => switch (url.segments) {
    ['orders', ...] => OrdersAt(OrdersRoute.fromUrl(url.rest(1))),
    ['settings', ...] => SettingsAt(SettingsRoute.fromUrl(url.rest(1))),
    _ => throw NotFound(url),
  };

  @override
  Url toUrl() => switch (this) {
    OrdersAt(:final child) => const Url(['orders']) + child.toUrl(),
    SettingsAt(:final child) => const Url(['settings']) + child.toUrl(),
  };
}

final class OrdersAt extends HomeRoute {
  const OrdersAt(this.child);
  final OrdersRoute child;
}

final class SettingsAt extends HomeRoute {
  const SettingsAt(this.child);
  final SettingsRoute child;
}

sealed class OrdersRoute extends NavRoute {
  const OrdersRoute();

  static OrdersRoute fromUrl(Url url) => switch (url.segments) {
    [] => const OrderList(),
    [final int id] => OrderDetail(id),
    [final int id, 'items', final int item] => OrderItem(id, item),
    _ => throw NotFound(url),
  };

  @override
  Url toUrl() => switch (this) {
    OrderList() => const Url([]),
    OrderDetail(:final id) => Url([id]),
    OrderItem(:final id, :final item) => Url([id, 'items', item]),
  };
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

sealed class SettingsRoute extends NavRoute {
  const SettingsRoute();

  static SettingsRoute fromUrl(Url url) => switch (url.segments) {
    [] => const SettingsRoot(),
    ['profile'] => const SettingsProfile(),
    _ => throw NotFound(url),
  };

  @override
  Url toUrl() => switch (this) {
    SettingsRoot() => const Url([]),
    SettingsProfile() => const Url(['profile']),
  };
}

final class SettingsRoot extends SettingsRoute {
  const SettingsRoot();
}

final class SettingsProfile extends SettingsRoute {
  const SettingsProfile();
}

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
  HomeRoute? home;
  HomeRoute? pendingNext;

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
        // a logged-in user opening /login stays where they are (URL replaced)
        if (!loggedIn) pendingNext = next;
      case HomeAt(:final child):
        home = child;
        // the typed return target of the login page
        if (!loggedIn) pendingNext = child;
    }
  }

  void login() {
    loggedIn = true;
    final target = pendingNext ?? const OrdersAt(OrderList());
    pendingNext = null;
    open(HomeAt(target), history: HistoryAction.replace);
  }

  void logout() {
    loggedIn = false;
    open(const LoginRoute(), history: HistoryAction.push);
  }

  @override
  List<NavEntry<AppRoute>> build() => [
    if (!loggedIn)
      NavPage(
        route: LoginRoute(next: pendingNext),
        child: LoginPage(onLogin: login),
      )
    else
      NestedNavigator(
        at: HomeAt.new,
        route: home,
        child: HomeNavigator(onLogout: logout),
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
  OrdersRoute? orders;
  SettingsRoute? settings;

  @override
  void initState() {
    super.initState();
    created++;
  }

  @override
  void applyRoute(HomeRoute route) {
    switch (route) {
      case OrdersAt(:final child):
        tab = HomeTab.orders;
        orders = child;
      case SettingsAt(:final child):
        tab = HomeTab.settings;
        settings = child;
    }
  }

  void switchTab(HomeTab next) {
    if (next == tab) return;
    setState(() => tab = next, history: HistoryAction.push);
  }

  // a persistent tab bar: each tab is a nested navigator with its own stack
  @override
  List<NavEntry<HomeRoute>> build() => [
    TabsPage(
      index: tab.index,
      tabs: [
        NestedNavigator(
          at: OrdersAt.new,
          route: orders,
          child: OrdersNavigator(
            onSwitchTab: switchTab,
            onLogout: navigator.onLogout,
          ),
        ),
        NestedNavigator(
          at: SettingsAt.new,
          route: settings,
          child: SettingsNavigator(onSwitchTab: switchTab),
        ),
      ],
      builder: (context, tabs) => HomeChrome(
        tabs: tabs,
        active: tab.index,
        onSelect: (i) => switchTab(HomeTab.values[i]),
      ),
    ),
  ];
}

class HomeChrome extends StatefulWidget {
  const HomeChrome({
    super.key,
    required this.tabs,
    required this.active,
    required this.onSelect,
  });
  final List<Widget> tabs;
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
    body: IndexedStack(index: widget.active, children: widget.tabs),
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
  List<NavEntry<OrdersRoute>> build() {
    builds++;
    return [
      NavPage(
        route: const OrderList(),
        child: OrderListPage(
          counter: counter,
          scroll: scroll,
          onOpen: (id) => open(OrderDetail(id)),
          onBump: () => setState(() => counter++),
          onScroll: (value) => scroll = value,
          onSwitchTab: navigator.onSwitchTab,
        ),
      ),
      if (selectedId case final id?)
        NavPage(
          route: OrderDetail(id),
          onPop: () {
            detailPops++;
            setState(() => selectedId = null);
          },
          child: OrderDetailPage(
            id: id,
            counter: counter,
            onBump: () => setState(() => counter++),
            onPopup: () => setState(() => showPopup = true),
            onItem: (item) => open(OrderItem(id, item)),
            onDone: () => setState(() => selectedId = null),
            onSwitchTab: navigator.onSwitchTab,
            onLogout: navigator.onLogout,
          ),
        ),
      if ((selectedId, selectedItem) case (final id?, final item?))
        NavPage(
          route: OrderItem(id, item),
          onPop: () => setState(() => selectedItem = null),
          child: ItemPage(
            id: id,
            item: item,
            onDone: () => setState(() => selectedItem = null),
          ),
        ),
      if (showPopup)
        DialogPage(
          onPop: () => setState(() => showPopup = false),
          child: const PopupContent(),
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
  List<NavEntry<SettingsRoute>> build() {
    return [
      NavPage(
        route: const SettingsRoot(),
        child: SettingsPage(
          onProfile: () => open(const SettingsProfile()),
          onSwitchTab: navigator.onSwitchTab,
        ),
      ),
      if (profile)
        NavPage(
          route: const SettingsProfile(),
          onPop: () => setState(() => profile = false),
          child: const ProfilePage(),
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
  const NotFoundPage({super.key, required this.url});
  final Url url;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Not found')),
    body: Text('No page at $url'),
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
        // a link of this navigator's route type, and one of the root's
        RouteLink(
          route: OrderItem(id, 7),
          builder: (context, open) => TextButton(
            key: const Key('link-item-7'),
            onPressed: open,
            child: const Text('item 7'),
          ),
        ),
        RouteLink(
          route: const HomeAt(SettingsAt(SettingsProfile())),
          builder: (context, open) => TextButton(
            key: const Key('link-profile'),
            onPressed: open,
            child: const Text('profile'),
          ),
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
  Widget build(BuildContext context) => SizedBox(
    height: 100,
    child: Column(
      children: [
        const Text('Popup content'),
        TextButton(
          key: const Key('close-popup'),
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );
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
  List<NavEntry<FixedRoute>> build() => [
    NavPage(
      route: const FixedTop(),
      child: PopScope<Object?>(
        canPop: !navigator.guarded,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) vetoes++;
        },
        child: const Text('guarded root'),
      ),
    ),
  ];
}

// --- a navigator with two non-poppable pages, for the imperative-pop guard --

sealed class FixedRoute extends NavRoute {
  const FixedRoute();

  static FixedRoute fromUrl(Url url) => switch (url.segments) {
    [] => const FixedTop(),
    _ => throw NotFound(url),
  };

  @override
  Url toUrl() => const Url([]);
}

final class FixedTop extends FixedRoute {
  const FixedTop();
}

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
  List<NavEntry<FixedRoute>> build() => [
    const NavPage(child: Text('bottom')),
    const NavPage(route: FixedTop(), child: Text('top')),
  ];
}
