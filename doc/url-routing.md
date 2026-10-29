# URL routing for fdr

Status: implemented in `lib/`. Verified on Flutter 3.47.5 by:

- widget tests (`test/`, with worked examples in `test/routing/`);
- compile-time checks (`dart run tool/check_typing.dart`);
- a scripted run of the URL demo in headless Chrome against the real engine history (`tool/browser_probe.sh`).

CI runs all three. The runnable demo is `example/lib/main_url_routing.dart` (`flutter run -d chrome -t lib/main_url_routing.dart` in `example/`).

## 1. The idea

State is the source of truth; the URL is a lossy projection of it. What a navigator shows lives in three tiers:

| Tier | Example | Survives |
|---|---|---|
| URL | `/orders/42?sorting=name` | links, bookmarks, reloads, new tabs |
| History entry | the order list's scroll offset (`historyState`) | back and forward, reloads of that entry |
| Memory only | an error dialog (`DialogPage`) | nothing; gone on reload |

Each navigator has a sealed route type. Like `fromJson`/`toJson`, the type maps **its own part** of the URL in plain Dart: a static `fromUrl` and a `toUrl`. A parent's route contains the child's route (`OrdersTab(OrderAt(42, ItemAt(3)))`), and the parent composes the child's mapping explicitly. There are no annotations on model classes, no central table and no code generation.

The two directions work like this:

- **State → URL.** Each page says which route it shows. The URL is the route of the top page, lifted through the parents to the root and printed by the root.
- **URL → state.** The root parses the URL into a route. Each navigator then sets its own state from its part in `applyRoute`, before its build, and passes the child's part on.

## 2. Leveling up

**A two-page app without URLs** needs no routes at all:

```dart
class OrdersNavigatorState extends StatefulNavigatorState<OrdersNavigator, Never> {
  int? selected;

  @override
  List<NavEntry<Never>> build() => [
    NavPage(child: OrderListPage(onOpen: (id) => setState(() => selected = id))),
    if (selected case final id?)
      NavPage(onPop: () => setState(() => selected = null), child: OrderPage(id: id)),
  ];
}

MaterialApp(home: DeclarativeNavigator(navigator: OrdersNavigator()));
```

`build` reads like a widget's `build`: constructors with named parameters, `child` last, collection-`if`s. It returns an `Iterable`, so a `sync*` body with `yield` works too, for a build that needs locals, loops or helper methods.

**URLs** add a route type with `fromUrl`/`toUrl`, an `applyRoute`, a `route:` per page and an `FdrRouter` (section 3).

**Further steps**, each one concept:

- a child navigator with its own route type: `NestedNavigator`;
- tabs: `TabsPage`;
- loading: `FutureNavigator`;
- links: `RouteLink`;
- dialogs without a URL: `DialogPage`;
- app state owned elsewhere: `watch` and `listen`.

## 3. Routes

From `example/lib/url_routing/shop.dart` (primary constructors, Dart 3.13):

```dart
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

final class const OrdersTab([final OrdersRoute route = const OrderList()]) extends ShopRoute;
final class const SettingsTab([final SettingsRoute route = const SettingsHome()]) extends ShopRoute;

sealed class OrdersRoute extends NavRoute {
  const OrdersRoute();

  static OrdersRoute fromUrl(Url url) => switch (url.segments) {
    [] => OrderList(OrderFilter(
      // 'sort' is the query name of an older release
      sort: Sort.values.asNameMap()[url['sorting'] ?? url['sort']] ?? Sort.date,
      status: url['status'],
    )),
    [final int id, ...] => OrderAt(id, OrderRoute.fromUrl(url.rest(1))),
    _ => throw NotFound(url),
  };

  @override
  Url toUrl() => switch (this) {
    OrderList(:final filter) => Url([], query: {
      if (filter.sort != Sort.date) 'sorting': [filter.sort.name],
      if (filter.status case final status?) 'status': [status],
    }),
    OrderAt(:final id, :final route) => Url([id]) + route.toUrl(),
  };
}
```

- **`Url.segments`** are the path segments left for this level. A segment that is an integer in canonical form becomes an `int`, so patterns read `[final int id, ...]`. `042`, `+42` and `0x2A` stay strings, and so do integers too large for the platform. Each page therefore has exactly one spelling. For string ids that may look like numbers there is `url.rawSegments`.
- **`url.rest(n)`** hands the rest to the next level, with the query.
- **`url['name']`** is the first value of a query parameter, like the browser's `URLSearchParams.get`; `url.all('name')` returns all values. Query parameters are shared by all levels: every level reads the whole query and prints only the names it owns.
- **Production evolution** stays in plain code: old spellings (`'orders' || 'order'`), renamed query parameters (`url['sorting'] ?? url['sort']`) and defaults the URL omits. An old URL is parsed, and the next report replaces it with the canonical form in place.

Why two switches and not one bidirectional declaration: Dart has no case paths, so a single declaration needs combinators (the previous iteration of this PR) or code generation. The two switches are the code anyone writes for `fromJson`/`toJson`. The debug round-trip check (section 7) catches them drifting apart.

## 4. Navigators

```dart
class _OrdersNavigatorState extends StatefulNavigatorState<OrdersNavigator, OrdersRoute> {
  OrderFilter filter = const OrderFilter();
  int? selected;
  OrderRoute? orderRoute;
  double scroll = 0; // kept in the history entry, see historyState

  @override
  void applyRoute(OrdersRoute route) {
    switch (route) {
      case OrderList(:final filter):
        this.filter = filter;
        selected = null;
      case OrderAt(:final id, :final route):
        selected = id;
        orderRoute = route;
    }
  }

  @override
  List<NavEntry<OrdersRoute>> build() => [
    NavPage(
      route: OrderList(filter),
      child: OrderListPage(
        orders: navigator.api.orders(filter),
        filter: filter,
        onFilter: (filter) =>
            setState(() => this.filter = filter, history: HistoryAction.replace),
      ),
    ),
    if (selected case final id?)
      NestedNavigator(
        at: (route) => OrderAt(id, route),
        route: orderRoute,
        onPop: () => setState(() => selected = null),
        child: FutureNavigator(
          key: ValueKey(id),
          load: () => navigator.api.order(id),
          loading: const LoadingPage(title: 'Order'),
          error: (error, retry) => ErrorPage(error: error, retry: retry),
          builder: (order, reload) => OrderNavigator(order: order, reload: reload),
        ),
      ),
  ];
}
```

- **`applyRoute`** runs for every incoming route: deep links, address-bar edits, browser back and forward, links, `open`, state restoration. It runs before the next build, so the default page never flashes. It sets only this navigator's state. For a child navigator, it stores the child's part, which `build` passes on as `NestedNavigator.route`.
- **Between URLs the navigator owns its state.** `setState` changes it, and the URL follows. The history action comes from how the page stack changed (section 10), or is given explicitly (`history: HistoryAction.replace` for a filter change).
- **`NestedNavigator`** shows a child navigator with its own route type:
  - `at` places a child route in the parent's type: the parent route that contains it. It prints the child's URLs and resolves the child's links. Without `at`, the child must have the parent's route type (checked in debug).
  - `route` is applied when the child is created, and whenever an incoming route **addresses** the child, i.e. when `at(route)` prints the same URL as the route the parent just received. A rebuild of the parent never resets the child. A tab the URL does not address keeps its stack, even though the parent still holds that tab's last route.
  - `onPop` decides what popping the child's first page does.
- **A navigator placed directly** in the list (same route type) receives every route the parent receives that its type takes; one without routes (`Never`) receives none.
- **Matching.** Like widgets, a keyed child navigator keeps its state when it moves in the list; unkeyed ones are matched by position.
- **Redirects.** `open()` (or an ancestor's `setState`) called during an update, from `applyRoute`, `initState` or `build`, runs once that update is done; it never re-enters it. So a redirect in `applyRoute` is simply `open(target, history: HistoryAction.replace)`.
- **External state.** The navigator can delegate to a store instead of fields. `applyRoute` calls `cubit.show(route)`, `build` reads `cubit.state`, `initState` calls `listen(cubit.stream)`, and `onPop`s are the cubit's methods. The URL still follows from the pages' routes, so whatever changes the store (a view model replacing the order it shows, a push message) updates the URL too.

## 5. Links and `open`

```dart
RouteLink(
  route: OrderAt(order.id),
  builder: (context, open) => ListTile(title: Text(order.title), onTap: open),
)
```

- **Lookup by type.** `RouteLink` takes a `NavRoute`. Each page is wrapped in an inherited scope of the navigator that built it. The link walks up to the nearest navigator whose route type the route belongs to, as `context.read<T>()` does in provider. `OrderItem(3)` resolves in the order navigator and `SettingsTab(Profile())` at the root. The route's type says whether a link is local or global. A route type with no navigator above it is a descriptive error that lists the navigators found.
- **One mapping.** The route is lifted through the parents' `at` closures and printed by the root's `toUrl`, the same code that writes the address bar.
- **Real links.** Under a router, `RouteLink` wraps the builder in url_launcher's `Link`, so on the web the page has a real `<a href>`. The browser can show it on hover and open it from the context menu. For cmd/ctrl/shift-click, `RouteLink` calls `Link`'s `followLink`, which leaves the click to the browser (new tab or window). A plain tap calls `open`; url_launcher prevents the browser's own navigation. The probe checks that the anchor exists in Chrome; the clicks themselves follow url_launcher's handling and are not probed. Without a router (`DeclarativeNavigator`), there is no href and a tap still opens.
- **`open(route)`** on a navigator state is the same navigation without a widget. `router.open(rootRoute)` is the same from outside the tree, e.g. a push notification handler. All three lift the route to the root and apply it from the root down, exactly like an incoming URL. The history action follows from the stack change: deeper is a push, shallower a back. A route opened before the router has its first URL (the notification that launched the app) wins over the platform's initial `/`.
- **Lookup scope.** Routes pushed outside the pages (`showModalBottomSheet`, menus) resolve their links at the navigator that owns the `Navigator`. A `DeclarativeNavigator` inside a page resolves links of the enclosing tree's route types there.
- **On the web** the link's `href` is absolute (URL strategy prefix and base included), so url_launcher never pushes it into the app itself, which would bypass fdr's history tracking. Alt-click opens in the app (the browser would download the page), and ctrl-click on macOS is the context menu.

## 6. URLs that do not parse

A level that does not know its rest throws `NotFound(url)`. Dart's exhaustiveness already forces a catch-all case in every switch over a list, so a level writes `_ => throw NotFound(url)` and needs no route case, state or page for it. The parser then looks for the longest prefix of the URL that parses, first without the query, then one segment less at a time. That route is shown with the not-found page on top, and the address bar keeps the URL as typed:

| URL | Shown | Back goes to |
|---|---|---|
| `/orders/42/nope` | order 42, not-found page on top | `/orders/42` |
| `/orders/abc` | order list, not-found page on top | `/orders` |
| `/nope` | home, not-found page on top | `/` |

There is one not-found page for the app: `FdrRouter(notFound: (url) => NotFoundPage(url: url))`, with a plain default. It lives until it is popped or something navigates. A level that wants its own handling can still return a route case for unknown rests and show its own page.

The other kinds of failure:

- **Bad query values** are lenient. `?sort=bogus` falls back to the default, and the next report writes the canonical URL in place.
- **Missing data** (`/orders/999` when the API answers 404) is not a parse error. It is the `FutureNavigator`'s error page, in context, with retry.
- **Bugs.** A `fromUrl` that throws anything other than `NotFound` is reported with `FlutterError.reportError` and then handled like a URL that does not parse.

## 7. Debug checks and what the type system catches

**Debug checks.**

- **Round trip.** Every URL the app reports is parsed and printed again; a difference is reported with both URLs: "`_Start` prints /start, which parses to a route that prints /other".
- **Query collisions.** `Url +` asserts when two levels print the same query parameter with different values. There is no silent winner.
- **Router type.** `FdrRouter` asserts that `fromUrl` returns the root's route type. Dart would otherwise infer the router's type parameter as a common supertype of both.

**Compile errors.** `tool/typing/mistakes.dart.fixture` holds deliberate mistakes; `dart run tool/check_typing.dart` (a CI step) checks that each fails with the expected diagnostic and nothing else fails:

| Mistake | Caught |
|---|---|
| New route subtype without a printer | `non_exhaustive_switch_expression` |
| Route field retyped `int` → `String` without updating `fromUrl` | `argument_type_not_assignable` |
| A page addressed by another navigator's route type | `argument_type_not_assignable` |
| `router.open` or a state's `open` with another navigator's route | `argument_type_not_assignable` |
| A `RouteLink` to something that is not a route | `argument_type_not_assignable` |
| A `NestedNavigator` whose `at` does not fit the child, or a child route of the wrong type | `could_not_infer` + `argument_type_not_assignable` |
| A `FutureNavigator` building a child of another route type | `return_of_invalid_type_from_closure` |

**Tests.** The contract test an app ships is a table of `(route, url)` rows: `route.toUrl()` prints `url`, and `fromUrl(url)` prints it back. Add the old spellings that must keep working and the URLs that must throw `NotFound`. "C10 golden URL table and round trips" in `test/routing/url_routing_test.dart` is the template.

## 8. Pages

- **`NavPage`** picks its route when the Navigator creates it, from `Theme.of(context).platform`: a Cupertino route with swipe back on iOS and macOS, a Material route elsewhere. On the web it is always the Material route, so the app's `pageTransitionsTheme` decides. `NavPage.material` and `NavPage.cupertino` choose explicitly. Both forked routes forward the pop contract to the `AppBar`/`CupertinoNavigationBar` back button (section 11).
- **`DialogPage`** is Material's dialog route, with no URL. Barrier taps, back and `Navigator.pop(context)` from inside the dialog (an OK button) go through its `onPop`.
- **`CustomPage(builder: (key, canPop, child) => …)`** is the escape hatch for any other Flutter `Page`: a modal bottom sheet, a custom transition. It can have a `route`, and `onPop` works as for every page.
- **`DeclarativeNavigator`** handles system back itself (`NavigatorPopHandler`), so Android back pops its pages before it leaves the app.
- **`TabsPage(index:, tabs:, builder:)`** is one page with a stable key whose body hosts one nested Navigator per tab. Pages pushed inside a tab animate inside it; the chrome around it never moves.
  - **URL:** the URL is the active tab's.
  - **Incoming routes:** an incoming route is offered to every tab, and each tab's `NestedNavigator` takes it only if it addresses that tab.
  - **History:** the page-stack diff looks into the active tab, so a pop inside a tab is a browser back.
  - **Back:** Android back reaches the active tab's Navigator through `NavigatorPopHandler`; at a tab's root it bubbles to the owner.
  - **Per tab:** each tab gets its own `HeroController`, and inactive tabs are muted with `TickerMode`.

## 9. Loading: `FutureNavigator`

A child navigator receives a domain model (an `Order`), not an id. It never deals with loading or errors of its own input, and deep links into nested, separately loaded levels still work. Route resolution stays synchronous; loading is navigator state:

- **The pending route.** While loading, or after a failure, the loading or error page is addressed by the route the `FutureNavigator` was given. The URL stays where the user is going, and finishing the load replaces the entry rather than adding one.
- **Handing over.** The child is created with that route as its first route.
- **Identity by key.** What is loaded is identified by the key. A different key is a different state, so a load still in flight for the old key is ignored. `onDispose` releases loaded values, including those of superseded loads.
- **`initialData`** shows data the app already has without loading. `reload` keeps the data on screen and hands new data to the same child state.

A deep link to `/orders/42/items/3/reviews` shows the order's loading page, then the order with the item's loading page on top, then the reviews. All of it happens at the same URL and in one history entry, and back then walks the stack the link implied (`test/routing/async_test.dart`).

## 10. Browser history: no more [A, B, A]

Flutter's default turns an in-app pop into a *new* entry, so browser back resurrects the popped page. This is the top complaint across go_router (#164969, #116440), beamer (#646) and the Flutter docs. fdr fixes it in three ways:

1. **The intent comes from the page-stack diff, not from which callback fired.** The delegate compares the keys of the routed pages at each report with the previous report:
   - pages only removed from the top is a pop of depth *k*;
   - pages only added on top is a push;
   - anything else pushes if the URL changed and replaces otherwise.

   An explicit `history:` on `setState` or `open` wins over the diff. This also covers state-driven removals (a Done button, a deleted order), which never go through `onPop`.
2. **A pop becomes a real traversal.** The provider keeps a shadow of the entries this session created. Each entry carries:
   - the session id;
   - the entry's serial;
   - the non-URL state;
   - up to 32 of the entries before it.

   If one of the previous *k* entries has the new URL, the provider calls `window.history.go(-steps)` instead of reporting. When the engine delivers that entry, it is absorbed: nothing is applied and nothing is reported.
3. **Reports during a traversal are deferred** until the awaited entry arrives, and then sent as one report. That report is a push if any deferred change was a push. An entry that does not match the awaited serial means the user moved through the history on their own, and the browser wins.

The fallback when traversal is impossible is Flutter's push, configurable to replace. Traversal is impossible after a cold start on a deep link, or off the web. A route delivered by the platform is always reported back as a replace, which canonicalises old spellings in place.

**Real browser.** `tool/browser_probe.sh` runs the shop demo in headless Chrome. After each of 20 steps it checks the app's URL, the address bar and the number of history entries. The steps cover:

- loads two levels deep;
- a state-driven pop, a system back inside a tab, browser forward and back;
- three levels opened and then closed in one change;
- a real page reload, after which an in-app back still traverses;
- a tab switch;
- an unknown URL typed into the bar;
- a `RouteLink` rendered as an `<a href>`.

**Engine facts this rests on (Flutter 3.47.5).**

- Browser back and forward send the same `pushRouteInformation{location, state}`.
- `RouteInformation.state` must be JSON. It round-trips through `history.state` on back and forward, but after a reload only the path arrives (flutter/flutter#108697). The provider reads the rest through `BrowserHistory.currentState` (section 13).
- `PlatformRouteInformationProvider` decides push vs replace by comparing path, fragment and query, never state.

## 11. The pop contract and page keys

**`onDidRemovePage`, not `Page.onPopInvoked`.** When the pages list drops a page, the Navigator still calls `Page.onPopInvoked(true)` on it, so `onPop` would run again after state-driven removals. `onDidRemovePage` fires *only* for imperative removals: the back button, an iOS swipe, Android back, a barrier tap and `Navigator.pop`. The library looks up the removed page **by key** in the *current* page list and runs that page's current `onPop`:

| Situation | Outcome |
|---|---|
| Page no longer in the list | The state already removed it; nothing to do |
| `onPop == null` | Misuse; reported with `FlutterError.reportError`, never thrown, because a throw inside the Navigator's locked update breaks it |
| Page still built after `onPop` ran | Reported, after the microtasks, so a store whose stream delivers asynchronously (a bloc) has rebuilt the navigator by then |

**Keys.**

- **Routed pages:** a routed page gets a `ValueKey` of its printed path without the query. `/orders?sorting=name` → `?sorting=date` therefore updates the list page in place, while `/orders/42` → `/orders/43` is a new page with a transition. Duplicates get `#n`.
- **Pages without a route:** a page without a route gets the key of the routed page below it plus its offset.
- **Explicit keys:** an explicit `key:` wins.
- **Navigator states:** states are reused on `runtimeType` + `key`, as Flutter does for widgets.

**Root back.** The bottom page is built with `Page.canPop = true`, so `maybePop` bubbles and Android back leaves the app. A `PopScope(canPop: false)` on the root page still vetoes. The forked Material/Cupertino routes use `super.canPop && page.canPop` for the back button, because the SDK's page routes ignore `Page.canPop` for `impliesAppBarDismissal`.

## 12. Mobile parity

- **Android back:** `RootBackButtonDispatcher` → `popRoute` → `maybePop` → `Page.canPop` / `PopScope` → `onDidRemovePage` → `onPop`. One path for the back arrow, swipe, system back and barrier tap.
- **OS deep links:** these arrive like browser navigation. The parser normalises scheme and host: `https://shop.example/orders/7` → `/orders/7`, and for custom schemes the host is the first segment (`myapp://orders/42` → `/orders/42`).
- **Process death:** `MaterialApp.router(restorationScopeId: ...)` persists URL and history state and replays them through `setRestoredRoutePath`.
- **Auth with a pending deep link:** there is no redirect function. The root's `applyRoute` keeps the target while logged out, and the login page prints it (`/login?next=%2Forders%2F42`), which survives a reload. `login()` calls `open(HomeAt(target), history: HistoryAction.replace)`.

## 13. History across reloads

After a reload the engine passes only the path to the framework, but the browser still has the entry's state. The provider reads it at startup through `BrowserHistory.currentState` (`window.history.state`). If the entry was written by this app, the provider continues that session:

- the entry's non-URL state is applied with the initial route;
- the recorded earlier entries let an in-app back still go back in the browser history.

Entries after the current one are learned when the browser delivers them.

## 14. Open problems

1. **Initial `/` on mobile.** A cold start without a deep link applies the platform's `/` as an incoming route, which overwrites navigation state the app restored before (a hydrated store). An option to treat that `/` as "no route" is missing.
2. **Foreign history entries.** An entry without fdr's state that arrives while the app runs (a hash typed into the address bar) clears the shadow history, so later in-app pops push instead of going back.
3. **Optional `at`.** A `NestedNavigator` without `at` around a child of another route type compiles, and fails only in debug, with an assert. A required `at` with a separate same-type variant would make it a compile error.
4. **Widget-side navigation by route.** `RouteLink` resolves any ancestor's route type, but a state's `open` takes only its own; a `BuildContext`-based `open`/`href` (for a `BlocListener`, a "copy link" button) is missing.
5. **Testing without rendering.** The planned `NavigatorTester` would take a URL in and give out the page stack, the URL and the pages' constructor arguments, with callbacks callable directly. It is not built yet. Today navigators are tested with widget tests (`test/routing/`), and stores like a Cubit are tested as plain Dart.
6. **url_launcher dependency.** Real links come from url_launcher's `Link`. A dependency-free `<a>` platform view is possible but is a project of its own.
7. **Lazy tabs.** `TabsPage` creates every tab's navigator up front.
8. **Rebuild cascade.** A parent's rebuild rebuilds every child navigator (a base fdr behaviour). An `identical()` short-circuit and a `setState` phase guard would fix it.
9. **Navigator/state pairing.** `createState()` returning a state of another navigator with the same route type compiles.
10. **Path URL strategy** (`usePathUrlStrategy`) needs a `<base href>` and server rewrites. The router prints absolute paths that work with both strategies; only the hash strategy runs in Chrome.
11. **An awaited `popstate` that never arrives** would defer reports forever. This cannot happen in multi-entry mode, which the provider always selects, but a timeout fallback would make it robust.

## 15. How this design was chosen

The previous iteration of this PR had:

- bidirectional combinator codecs (`SumCodec`, `Case.bind`, lenses);
- modifier chains on widgets and navigators (`.page()`, `.mount(embed:, unwrap:)`, `.poppable()`, `shell()`).

The codecs were type-safe, and parse and print could not drift. But nobody would come up with the combinators or the chains by themselves, and the pages had to repeat route plumbing.

These alternatives were explored and rejected:

| Alternative | Why it was rejected |
|---|---|
| Annotations on route or model classes | They couple the app's models to one URL scheme |
| A central URL table | Too URL-driven; the dynamic `build` with errors in context is the point |
| Destination trees | A second tree beside the navigators, declaring what `build` already says |
| Implicit hand-down of URL remainders | A child gets whatever its parent did not read, so no single place says which level owns which part |
| `at:` plus `childOf:` plumbing | Two functions per nesting; `at` alone is enough once the parent stores the child's route in `applyRoute` |

What remains is Flutter's own shape: constructors with named parameters, a `build` with collection-`if`s, `InheritedWidget` lookup for links, and `fromJson`/`toJson`-style mapping per level. Debug checks replace the guarantee the codecs gave by construction.
