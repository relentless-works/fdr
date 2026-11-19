# URL routing for fdr

Status: implemented in `lib/`. Checked by:

- widget tests (`test/`, with worked examples in `test/routing/` and regression tests in `test/regressions/`);
- compile-time checks (`dart run tool/check_typing.dart`);
- a scripted run of the URL demo in headless Chrome against the real engine history (`tool/browser_probe.sh`; `FLUTTER` and `CHROME` pick the SDK and the browser).

CI runs all three on Flutter 3.47.5, also before a tag is published. Tests and tools are in the repository, not in the published package. The runnable demo is `example/lib/main_url_routing.dart` (`flutter run -d chrome -t lib/main_url_routing.dart` in `example/`).

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

- **`Url.segments`** are the path segments left for this level. A segment that is an integer in canonical form, within ±(2^53 − 1), becomes an `int`, so patterns read `[final int id, ...]`. `042`, `+42`, `0x2A` and larger integers stay strings, the same on every platform. Each page therefore has exactly one spelling. For string ids that may look like numbers there is `url.rawSegments`. A `toUrl` prints only `int`s and `String`s.
- **`url.rest(n)`** hands the rest to the next level, with the query. A URL with fewer than `n` segments throws `NotFound`, like any other unknown URL.
- **`url['name']`** is the first value of a query parameter, like the browser's `URLSearchParams.get`; `url.all('name')` returns all values. Query parameters are shared by all levels: every level reads the whole query and prints only the names it owns. A parsed `Url` cannot be changed, like a const one: copy a list before sorting it.
- **Parsing** reads path and query only; scheme, authority and fragment are ignored. Dot segments are resolved (`../x` is `/x`), and percent-encoding that is not UTF-8 (`%E9` from an old Latin-1 link) is read as Latin-1. Two `Url`s are equal when they print the same path and the same values per query name: `Url(['42'])` equals `Url([42])`.
- **Production evolution** stays in plain code: old spellings (`'orders' || 'order'`), renamed query parameters (`url['sorting'] ?? url['sort']`) and defaults the URL omits. An old URL is parsed, and the next report replaces it with the canonical form in place.

Why two switches and not one bidirectional declaration: Dart has no case paths, so a single declaration needs combinators (the previous iteration of this PR) or code generation. The two switches are the code anyone writes for `fromJson`/`toJson`. The debug round-trip check (section 7) catches them drifting apart.

## 4. Navigators

The orders navigator of the demo:

```dart
class _OrdersNavigatorState extends StatefulNavigatorState<OrdersNavigator, OrdersRoute> {
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
    // null: the entry was written while scroll was 0
    scroll = switch (state) {
      {'scroll': final num offset} => offset.toDouble(),
      _ => 0,
    };
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
          onFilter: (filter) =>
              setState(() => this.filter = filter, history: HistoryAction.replace),
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
```

- **`applyRoute`** runs for every incoming route: deep links, address-bar edits, browser back and forward, links, `open`, state restoration. It runs before the next build, so the default page never flashes. It sets only this navigator's state, and does not call `super.applyRoute` (the base only asserts that it was overridden). For a child navigator, it stores the child's part, which `build` passes on as `NestedNavigator.route`.
- **Between URLs the navigator owns its state.** `setState` changes it, and the URL follows. The history action comes from how the page stack changed (section 10), or is given explicitly (`history: HistoryAction.replace` for a filter change).
- **`NestedNavigator`** shows a child navigator with its own route type:
  - `at` places a child route in the parent's type: the parent route that contains it. It prints the child's URLs and resolves the child's links. Without `at`, the child must have the parent's route type; a `NestedNavigator` that needs `at` and has none is a `FlutterError` when it is first built, in every build mode.
  - `route` is applied when the child is created, and whenever an incoming route **addresses** the child, i.e. when `at(route)` prints the same URL as the route the parent just received. So `at` has to rebuild the parent's whole route, including query parameters the parent owns. A rebuild of the parent never resets the child. A tab the URL does not address keeps its stack, even though the parent still holds that tab's last route. A child created later by a plain `setState` starts at the stored route too, so the parent clears it when it removes the child (`orderRoute = null` above).
  - `onPop` decides what popping the child's first page does.
- **A navigator placed directly** in the list (same route type) receives every route the parent receives that its type takes; one without routes (`Never`) receives none.
- **Matching.** Like widgets, a keyed child navigator or `TabsPage` keeps its state when it moves in the list; unkeyed ones are matched by position (`TabsPage`s among themselves, in order). One whose key changes starts over.
- **Updates do not nest.** A `setState` or `open()` called while navigators update never re-enters the update:
  - a `setState` in a navigator's own `initState`, `didUpdateNavigator` or `applyRoute` only runs its callback; the build that follows shows the change;
  - a `setState` on any other navigator (an ancestor, a sibling, also through `watch` and `listen`) rebuilds it once the outermost update is done;
  - an `open()` runs after that, on the settled tree.
- **Redirects.** So a redirect in `applyRoute` is simply `open(target, history: HistoryAction.replace)`. The replace is for the redirecting route, which was never reported: a link to it still adds one entry, and a route the platform delivered is replaced in place. An `open()` in `initState` or `build` while the router is created is a redirect too, so the platform's initial route is still applied after it; a redirect that must survive incoming URLs belongs in `applyRoute`. After 5 redirects in a row, each opened by the update of the one before, the next one is not opened but reported as a `FlutterError` that lists the chain, and the app stays on the last route applied.
- **Errors.** If `initState`, `applyRoute` or `build` of a navigator throws, its parent keeps the entries and child states it had (states created in that update are disposed), and the exception reaches the caller of `setState` or `open`; on hot reload it is reported instead, so the rest of the app still reloads. A redirect requested in that update is dropped. What an `applyRoute` set before the throw stays set. A `dispose` that throws is reported, and the update that removed the navigator stands. For routes the platform delivers, see section 6.
- **External state.** The navigator can delegate to a store instead of fields. `applyRoute` calls `cubit.show(route)`, `build` reads `cubit.state`, `initState` calls `listen(cubit.stream)`, and `onPop`s are the cubit's methods. The URL still follows from the pages' routes, so whatever changes the store (a view model replacing the order it shows, a push message) updates the URL too. `watch` and `listen` return a callback that ends the subscription early, e.g. in `didUpdateNavigator` when the navigator brings another listenable. Stream errors go to `listen(onError:)`; without it they are unhandled, as with `Stream.listen`.

## 5. Links and `open`

```dart
RouteLink(
  route: OrderAt(order.id),
  builder: (context, open) => ListTile(title: Text(order.title), onTap: open),
)
```

- **Lookup by type.** `RouteLink` takes a `NavRoute`. Each page is wrapped in an inherited scope of the navigator that built it. The link walks up to the nearest navigator whose route type the route belongs to, as `context.read<T>()` does in provider. `ItemAt(3)` resolves in the order navigator and `SettingsTab(Profile())` at the root. The route's type says whether a link is local or global. A route type with no navigator above it is a descriptive error that lists the navigators found.
- **One mapping.** The route is lifted through the parents' `at` closures and printed by the root's `toUrl`, the same code that writes the address bar.
- **Real links.** Under a router, `RouteLink` wraps the builder in url_launcher's `Link`, so on the web the page has a real `<a href>`. The browser can show it on hover and open it from the context menu. A plain tap calls `open`; url_launcher prevents the browser's own navigation. A click with the new-tab key (cmd on macOS and iOS, ctrl elsewhere) or with shift calls `Link`'s `followLink`, which leaves it to the browser (new tab or window). The probe checks that the anchor exists in Chrome; which key does what is tested per platform (`test/routing/route_link_tap_test.dart`), the clicks themselves are not probed. Without a router (`DeclarativeNavigator`), there is no href and a tap still opens.
- **`open(route)`** on a navigator state is the same navigation without a widget. `router.open(rootRoute)` is the same from outside the tree, e.g. a push notification handler. All three lift the route to the root and apply it from the root down, exactly like an incoming URL. The history action follows from the stack change: deeper is a push, shallower a back. A route opened before the router has its first URL (the notification that launched the app) wins over the platform's initial route, and over a route restored after process death.
- **Lookup scope.** Sheets, dialogs, popup menus and dropdowns opened from a page with Flutter's helpers (`showModalBottomSheet`, `showDialog`, `showMenu`/`PopupMenuButton`, `DropdownButton`) capture the page's inherited themes, and the scope is one of them: their links resolve like links in the page. Routes that capture no themes (`Navigator.push` of a route of your own, `showGeneralDialog`, `showCupertinoDialog`, `showCupertinoModalPopup`) resolve their links at the navigator that owns the `Navigator`. A link outside any page (`MaterialApp.router(builder:)`) is an error. A `DeclarativeNavigator` inside a page resolves links of the enclosing tree's route types there.
- **On the web** the link's `href` is absolute (URL strategy prefix and base included), so url_launcher never pushes it into the app itself, which would bypass fdr's history tracking. Alt-click opens in the app (the browser would download the page), and so does a meta-click off Apple platforms (the browser would follow it in the current tab). Ctrl-click on macOS is the context menu.

## 6. URLs that do not parse

A level that does not know its rest throws `NotFound(url)`. Dart's exhaustiveness already forces a catch-all case in every switch over a list, so a level writes `_ => throw NotFound(url)` and needs no route case, state or page for it. The parser then looks for the longest prefix of the URL that parses, first without the query, then one segment less at a time. That route is shown with the not-found page on top, and the address bar keeps the whole URL, not the prefix's, as `Url.parse` read it and printed the canonical way (`/orders/42/./nope/` as `/orders/42/nope`, a Latin-1 `%E9` as UTF-8 `%C3%A9`, `?q=a%20b` as `?q=a+b`). In the demo:

| URL | Shown | Back goes to |
|---|---|---|
| `/orders/42/nope` | order 42, not-found page on top | `/orders/42` |
| `/orders/abc` | order list, not-found page on top | `/orders` |
| `/nope` | what `/` parses to (the order list), not-found page on top | `/orders` |

There is one not-found page for the app: `FdrRouter(notFound: (url) => NotFoundPage(url: url))`, with a plain default. It lives until it is popped or something navigates. If the nearest page's `applyRoute` redirects, the not-found page stays on top of the redirect's target, at the URL that did not parse. A level that wants its own handling can still return a route case for unknown rests and show its own page.

The other kinds of failure:

- **Bad query values** are lenient. `?sort=bogus` falls back to the default, and the next report writes the canonical URL in place.
- **Missing data** (`/orders/999` when the API answers 404) is not a parse error. It is the `FutureNavigator`'s error page, in context, with retry.
- **Bugs in `fromUrl`.** A `fromUrl` that throws anything other than `NotFound` is reported with `FlutterError.reportError`. No shorter prefix is tried: the not-found page is shown over what the root shows (its default state at a cold start).
- **Bugs in navigators.** An `applyRoute` or `build` that throws while a route from the platform is applied (a typed URL, back and forward, a deep link, the cold start) is reported with `FlutterError.reportError`, not thrown. The navigators keep their last good pages (section 4), and the browser entry is replaced with the URL of what they show. An `open()` from the app throws to its caller.

## 7. Debug checks and what the type system catches

**Debug checks.**

- **Round trip.** Every URL the app reports is parsed and printed again; a difference is reported with both URLs: "`_Start` prints /start, which parses to a route that prints /other".
- **Query collisions.** `Url +` asserts when two levels print the same query parameter with different values. A name without values prints nothing, so it neither collides nor wins. In release the later level wins.
- **Router type.** `FdrRouter` asserts that `fromUrl` returns the root's route type. Dart would otherwise infer the router's type parameter as a common supertype of both.
- **Navigators.** A `NestedNavigator` without a needed `at`, and a `createState()` that returns the state of another navigator, are `FlutterError`s in every build mode when first built. An `applyRoute` that calls `super.applyRoute` asserts. `setState` and `open` after `dispose` assert, and do nothing in release.
- **Pages.** A `CustomPage` builder that does not pass `key` and `canPop` on asserts. A tree that shows no page is a `FlutterError` naming the host (in release it shows nothing). Printing a `Url` with a segment that is neither an `int` nor a `String` asserts.
- **History state** that is not JSON is reported once per navigator, with its type, and left out of the entry (section 13).

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

- **`NavPage`** picks its route when the Navigator creates it, from `Theme.of(context).platform`: a Cupertino route with swipe back on iOS and macOS, a Material route elsewhere. On the web it is always the Material route, so the app's `pageTransitionsTheme` decides. `NavPage.material` and `NavPage.cupertino` choose explicitly. Both forked routes forward the pop contract to the `AppBar`/`CupertinoNavigationBar` back button (section 11). A page the state removes while the user swipes it back finishes its exit when the finger lifts.
- **`DialogPage`** is Material's dialog route, with no URL. Its child, `onPop` and `barrierDismissible` follow each build. Barrier taps, back and `Navigator.pop(context)` from inside the dialog (an OK button) go through its `onPop`.
- **`CustomPage(builder: (key, canPop, child) => …)`** is the escape hatch for any other Flutter `Page`: a modal bottom sheet, a custom transition. It can have a `route`, and `onPop` works as for every page. The builder has to pass `key` and `canPop` on. A route the app writes itself reads the child from its current `settings` (`ModalRoute.settingsOf(context)`), so it follows rebuilds. On `MaterialPage` or `CupertinoPage`, a page without `onPop` still shows an `AppBar` back button that does nothing; `NavPage` does not have this problem.
- **`DeclarativeNavigator`** handles system back itself, so Android back pops its pages before it leaves the app: through `NavigatorPopHandler` inside a route, and through the binding outside one (`MaterialApp.builder`, directly under `runApp`).
- **`TabsPage(index:, tabs:, builder:)`** is one page with a stable key whose body hosts one nested Navigator per tab. Pages pushed inside a tab animate inside it; the chrome around it never moves.
  - **URL:** the URL is the active tab's.
  - **Incoming routes:** an incoming route is offered to every tab, and each tab's `NestedNavigator` takes it only if it addresses that tab.
  - **History:** the page-stack diff looks into the active tab, so a pop inside a tab is a browser back.
  - **Back:** Android back reaches the active tab's Navigator through `NavigatorPopHandler`. At the active tab's root it bubbles to the owner, also when another tab has pages on its stack.
  - **Per tab:** each tab gets its own `HeroController`, and inactive tabs are muted with `TickerMode`. `index` has to be a valid tab index (asserted in debug).

## 9. Loading: `FutureNavigator`

A child navigator receives a domain model (an `Order`), not an id. It never deals with loading or errors of its own input, and deep links into nested, separately loaded levels still work. Route resolution stays synchronous; loading is navigator state:

- **The pending route.** While loading, or after a failure, the loading or error page is addressed by the route the `FutureNavigator` was given, the `NestedNavigator.route` around it. The URL stays where the user is going, and finishing the load replaces the entry rather than adding one. So open it with a route: `open(OrderAt(id))`, a `RouteLink`, or a `setState` that sets `orderRoute` together with the id. Without one, the loading and error pages have no URL: the URL stays at the page below, and the loaded child's first page adds the entry.
- **Handing over.** The child is created with that route as its first route. It is handed over once: a child the builder creates later (another navigator class or key after a reload) starts at its own first page.
- **Identity by key.** What is loaded is identified by the key. A different key is a different state, so a load still in flight for the old key is ignored. `onDispose` releases each value `load` returned once it is no longer shown, and each instance once: when a reload replaces it, when the navigator goes, and for a superseded load once the newest load completes, which may return the same instance (a repository deduplicating requests). A reload that returns the instance on screen does not release it.
- **`initialData`** shows data the app already has without loading. It stays the app's and is never passed to `onDispose`. `reload` keeps the data on screen and hands new data to the same child state; if it fails, the data stays and `reload` completes with the error. A reload superseded by a later one completes normally.

A deep link to `/orders/42/items/3/reviews` shows the order's loading page, then the order with the item's loading page on top, then the reviews. All of it happens at the same URL and in one history entry, and back then walks the stack the link implied (`test/routing/async_test.dart`).

## 10. Browser history: no more [A, B, A]

Flutter's default turns an in-app pop into a *new* entry, so browser back resurrects the popped page. This is the top complaint across go_router (#164969, #116440), beamer (#646) and the Flutter docs. fdr fixes it in three ways:

1. **The intent comes from the page-stack diff, not from which callback fired.** The delegate compares the keys of the routed pages at each report with the previous report:
   - pages only removed from the top is a pop of depth *k*;
   - pages only added on top is a push;
   - anything else pushes if the URL changed and replaces otherwise.

   An explicit `history:` on `setState` or `open` wins over the diff; the depth of an explicit pop still comes from the diff (*k*, at least one). This also covers state-driven removals (a Done button, a deleted order), which never go through `onPop`.
2. **A pop becomes a real traversal.** The provider keeps a shadow of the entries this session created, at most 64 before the current one. Each entry carries:
   - the session id;
   - the entry's serial;
   - the non-URL state;
   - up to 32 of the entries before it.

   If one of the previous *k* entries has the new URL, the provider calls `window.history.go(-steps)` instead of reporting. When the engine delivers that entry, it is absorbed: nothing is applied and nothing is reported. An older entry the browser returns to is learned again, as after a reload.
3. **Reports during a traversal are deferred** until the awaited entry arrives, and then sent as one report:
   - it is a push if any deferred change was a push, except that a deferred pop back to the awaited entry's URL (a page opened and closed again) makes it a replace;
   - a further in-app back drops what was deferred, since the state is then that entry's;
   - an entry that does not match the awaited serial means the user moved through the history on their own: the browser wins, and the deferred report is dropped;
   - if the awaited entry does not arrive within a second (`history.go` past the first entry delivers nothing), the provider continues at the entry the browser is on and reports the app's URL there. The browser may only be late: for another second, the entry of that traversal (the one asked for, or the one as many steps before the current entry) is still recognised when it arrives. The app keeps its state, also what was opened since, and the provider sends the browser back to the app's entry with `history.go`. A browser back by the user to one of these entries within that second is taken for it and undone. After that, or once another entry arrived, an entry counts as the user's own traversal. The report at the timeout stays: a pushed entry remains in the history, and with `popFallback: replace` the entry that was left is overwritten.

The fallback when traversal is impossible is Flutter's push, configurable to replace (`FdrRouter(popFallback:)`). Traversal is impossible after a cold start on a deep link, or off the web. A route delivered by the platform is always reported back as a replace, which canonicalises old spellings in place. A URL typed into the address bar while the app runs is a new entry after the current one; the entries before it stay available to in-app backs. A report that would write the same URL and state into the current entry again is not sent.

**Real browser.** `tool/browser_probe.sh` runs the shop demo in headless Chrome, with the hash URL strategy over `file://`. After each of 19 steps it checks the app's URL, the address bar and the number of history entries, and at the end that a `RouteLink` is rendered as an `<a href>`. The steps cover:

- loads two levels deep;
- a state-driven pop, a system back inside a tab, browser forward and back;
- two levels opened in one change, and three closed in one change;
- a real page reload, after which an in-app back still traverses;
- a tab switch;
- an unknown URL typed into the bar.

Sequences the probe does not drive (a reload on an earlier entry followed by forward and a push, two backs without settling in between, a back followed at once by an `open`) are tested against a model of the browser history (`test/regressions/browser_history_test.dart`).

**Engine facts this rests on (Flutter 3.47.5).**

- Browser back and forward send the same `pushRouteInformation{location, state}`.
- `RouteInformation.state` must be JSON. It round-trips through `history.state` on back and forward, but after a reload only the path arrives (flutter/flutter#108697). The provider reads the rest through `BrowserHistory.currentState` (section 13).
- `PlatformRouteInformationProvider` decides push vs replace by comparing path, fragment and query, never state.

## 11. The pop contract and page keys

**`onDidRemovePage`, not `Page.onPopInvoked`.** When the pages list drops a page, the Navigator still calls `Page.onPopInvoked(true)` on it, so `onPop` would run again after state-driven removals. `onDidRemovePage` fires *only* for imperative removals: the back button, an iOS swipe, Android back, a barrier tap and `Navigator.pop`. The library looks up the removed page **by key** in the *current* page list and runs that page's current `onPop`:

| Situation | Outcome |
|---|---|
| Page no longer in the list | The state already removed it; nothing to do |
| `onPop == null` | Misuse; reported with `FlutterError.reportError`, never thrown, because a throw inside the Navigator's locked update breaks it. The page is gone until that navigator builds again |
| Page still built after `onPop` ran | Reported, after the microtasks, so a store whose stream delivers asynchronously (a bloc) has rebuilt the navigator by then. Only the same kind of page with a child of the same type and key counts: another page that `onPop` puts at that key (a dialog after a form) is not reported |

**Keys.**

- **Routed pages:** a routed page gets a `ValueKey` of its printed path without the query. `/orders?sorting=name` → `?sorting=date` therefore updates the list page in place, while `/orders/42` → `/orders/43` is a new page with a transition. Duplicates get `#n`, counted from the bottom.
- **Pages without a route:** a page without a route gets the key of the routed page below it plus `+n` for its offset. A printed path contains neither `#` nor `+`, so no derived key is a route's key.
- **Explicit keys:** an explicit `key:` wins. Pages without a route and duplicates are matched by order, so give them a `key:` when pages can be inserted or removed below them.
- **Navigator states:** states are reused on `runtimeType` + `key`, as Flutter does for widgets.

**Root back.** The bottom page is built with `Page.canPop = true`, so `maybePop` bubbles and Android back leaves the app. A `PopScope(canPop: false)` on the root page still vetoes. The forked Material/Cupertino routes use `super.canPop && page.canPop` for the back button, because the SDK's page routes ignore `Page.canPop` for `impliesAppBarDismissal`.

## 12. Mobile parity

- **Android back:** `RootBackButtonDispatcher` → `popRoute` → `maybePop` → `Page.canPop` / `PopScope` → `onDidRemovePage` → `onPop`. One path for the back arrow, swipe, system back and barrier tap.
- **OS deep links:** these arrive like browser navigation. The parser keeps path and query: `https://shop.example/orders/7` → `/orders/7`. For custom schemes the host is the first segment (`myapp://orders/42` → `/orders/42`), lowercased like every host. The same for a host without a scheme, which is a path typed with two slashes (`//orders/42` → `/orders/42`); a protocol-relative `//other.host/x` is then `/other.host/x`, usually the not-found page. An http(s) link with its route in the fragment (`https://shop.example/#/orders/42`, shared from a hash-strategy web build) is routed by the fragment. `FdrRouter(rewriteUri:)` rewrites each incoming URI before these rules, e.g. for a real host on a custom scheme or universal links under a path prefix. If it throws, the error is reported and the link shows the not-found page, as for a `fromUrl` that throws.
- **Start without a deep link:** the platform's initial route is `/`, applied like any route. With `FdrRouter(keepStateWithoutDeepLink: true)`, the navigators keep the state they were created with (a hydrated store) and the URL follows from it. Not on the web, where `/` is a URL the user opened.
- **Process death:** `MaterialApp.router(restorationScopeId: ...)` persists URL and history state and replays them through `setRestoredRoutePath`. A route the app opened before the router started wins over the restored one.
- **A Router mounted again:** a `MaterialApp.router` that is removed and shown again, or whose key changes, with the same `FdrRouter` applies nothing: the navigators keep their state, also the non-URL state, and a route opened in between is reported like any other.
- **Auth with a pending deep link:** there is no redirect function. The root's `applyRoute` keeps the target while logged out, and the login page prints it (`/login?next=%2Forders%2F42`), which survives a reload. `login()` calls `open(HomeAt(target), history: HistoryAction.replace)` (`test/routing/example_app.dart`).

## 13. History state and reloads

A navigator keeps non-URL state in the history entry by overriding `historyState` and `restoreHistoryState` (section 4):

- **What is stored.** JSON only: null, bool, finite numbers, String, and List and Map (with String keys) of these. A value that is not JSON is reported with the navigator's type and left out of the entry.
- **Where.** By the navigator's position in its parent's build list and its `restorationType`, the runtime type name by default. Minified web builds and renames change that name, so override it with a stable string.
- **When it comes back.** `restoreHistoryState` runs on back and forward, reloads and state restoration, before the next build. It gets null for an entry written while `historyState` was null, if it is not null now: null stands for the default. The entry may come from an earlier build of the app (a tab left open over a deployment); an error thrown there is reported, and that navigator keeps its state while the others are restored.
- **Navigators created later.** A navigator that does not exist yet when the entry is restored (below a `FutureNavigator` that is still loading) gets its part when it is created. Until then the entry keeps it; an incoming route that reaches its parent drops it.

After a reload the engine passes only the path to the framework, but the browser still has the entry's state. The provider reads it at startup through `BrowserHistory.currentState` (`window.history.state`). If the entry was written by this app, the provider continues that session:

- the entry's non-URL state is applied with the initial route;
- the recorded earlier entries let an in-app back still go back in the browser history.

Entries after the current one are learned when the browser delivers them.

## 14. Open problems

**API and design.**

1. **Optional `at`.** A `NestedNavigator` without `at` around a child of another route type compiles, and fails with a `FlutterError` when it is first built. A required `at` with a separate same-type variant would make it a compile error.
2. **Navigator/state pairing.** `createState()` returning the state of another navigator with the same route type compiles; the first build fails with a `FlutterError` that names both.
3. **Widget-side navigation by route.** `RouteLink` resolves any ancestor's route type, but a state's `open` takes only its own; a `BuildContext`-based `open`/`href` (for a `BlocListener`, a "copy link" button) is missing. The same API would serve links outside any page (a side bar in `MaterialApp.router(builder:)`), which are an error today.
4. **Testing without rendering.** The planned `NavigatorTester` would take a URL in and give out the page stack, the URL and the pages' constructor arguments, with callbacks callable directly. It is not built yet. Today navigators are tested with widget tests (`test/routing/`), and stores like a Cubit are tested as plain Dart.
5. **Lazy tabs.** `TabsPage` creates every tab's navigator up front, which also starts their loads.
6. **Rebuild cascade.** A parent's rebuild rebuilds every child navigator, and hot reload relies on that. Options: keep it as intended, or skip a child whose configuration is `identical()` (a const navigator), with a forced update for hot reload; a child that reads state owned elsewhere without `watch` or `listen` would then stop updating. Independently, a re-flatten that yields the same pages could skip notifying.
7. **Stored child route.** `NestedNavigator.route` is applied whenever the child is created, also by a plain `setState`, so the parent has to clear it when it removes the child (section 4). Options: keep and document it; consume it once, which is breaking and needs another way for `FutureNavigator` to hand over its route; or rename it.
8. **`at` and the parent's query.** A child is addressed only if `at(route)` prints the incoming URL including its query, so an `at` that drops a query parameter the parent owns makes the child ignore every incoming route, silently. Options: a debug report when the path matches but the query does not; compare the path and only the query names the child prints; or keep it documented.
9. **Pages without a route are matched by order** (section 11), so inserting or removing one below another moves its widget state to the wrong page unless it has a `key:`. Options: keep and document it; a key from the child's type and key (helps only when the types differ, and adds a transition when a page's child type changes); keys kept across builds and matched like `Element.updateChildren`; or a debug warning.
10. **Imperative pop without `onPop`.** `Navigator.pop` of a page without `onPop`, or with an `onPop` whose store has not rebuilt yet, removes the page until the navigator's next build, which may be an unrelated one; a slow store can show it twice. Options: show the pages again at once (the page flickers back), keep the popped key out of the Navigator until the state drops it (a second source of truth and a timeout), or document it.
11. **Two history actions in one frame.** An explicit `history:` applies to everything that changes before the next report, so a `setState(history: HistoryAction.replace)` followed in the same frame by a change that opens a page reports one replace, and the page gets no entry. Options: document it; record each change with its own stack diff and merge per frame (a replace and then a push is a push); or let only an explicit push win over a later replace.
12. **Reserved member names.** `StatefulNavigatorState` defines `open`, `watch`, `listen`, `navigator`, `mounted`, `setState`, `historyState` and more, so a state field called `open` does not compile (the analyzer says why). Options: list the names in the docs; rename `open` (breaking); or move navigation to a separate object.
13. **`FdrRouter` internals.** `delegate`, `parser` and `provider` are public, but their types are not exported. The tests read the shadow history and the navigator key through them, and `delegate.scope` exposes the routing scope's mutable callbacks. Options: make them private and expose what is meant to be public (the navigator key, a test view of the history), or export the types and hide their internals.

**Known limitations.**

14. **The entry being left.** On a push, the entry being left is written once more with the history state after the change. Going back to it restores that state rather than the one it was left with, and navigators the push removed lose their part.
15. **The `onPop` check and state above the tree.** State held above the navigator tree (a `ValueListenableBuilder` that builds the `DeclarativeNavigator`) rebuilds it in the next frame, after the check, so a correct `onPop` is reported as a misuse. State in a navigator, or in a store it watches, is not affected.
16. **Entries without fdr's state.** A state-less entry delivered while the app runs is taken as a new entry after the current one, which is right for a typed URL but not for an old entry reached with back or forward. Another session's entry, or one delivered while a back is in flight, starts a new shadow history, after which in-app pops use the fallback (a push by default) instead of going back.
17. **Path URL strategy** (`usePathUrlStrategy`) needs a `<base href>` and server rewrites. The router prints absolute paths that work with both strategies, but only the hash strategy runs in Chrome; reloads, traversal and links under the path strategy, where a typed URL is a full page load, are untested.
18. **No fragment.** A `Url` has a path and a query. The fragment of a deep link (`/orders/7#reviews`), or of a web URL under the path strategy, is dropped and removed by the next report.
19. **Deep links the parser cannot recover.** A custom scheme's host arrives lowercased (`myapp://AbC123` is `/abc123`, also for `rewriteUri`); ids that need their case use the path form `myapp:///AbC123`. The same for the first segment after two slashes (`//AbC123`). Option: document it.

**Dependencies and toolchain.**

20. **url_launcher.** Real links come from url_launcher's `Link`, which adds five native plugins to every app, although off the web `Link` only calls the builder. A plain click relies on url_launcher_web 2.4.1 or later to stop the browser's own navigation, which `url_launcher: ^6.3.2` does not guarantee. Options: depend on `url_launcher_web` and `url_launcher_platform_interface` instead (no native code), or an inlined `<a>` platform view (estimated at about 100 lines on the PR), which has to pair the browser's click with the Flutter tap that led to it, as url_launcher does, also for clicks through the semantics tree.
21. **Links on the web.** Link semantics come only from url_launcher, on the web under a router, where the builder's result is merged into one semantics node and placed in a `Stack`; a builder that returns `Expanded`, `Flexible` or `Positioned` therefore fails only there. Options: one semantics wrapper on every path (it would merge a nested button into the link on mobile too), a plain `Semantics(link: true)` off the web (no effect around a `TextButton`), or document that the builder returns one tappable box. Separately, url_launcher's anchor sits above whatever Flutter paints over the link, so hover, the context menu and middle-click may reach a link under a dialog (from url_launcher's source; not checked in a browser).
22. **package:material_ui.** `NavPage` picks its route from `package:flutter/material`'s `Theme`, and `DialogPage` reads its `MaterialLocalizations`. Under material_ui's `MaterialApp`, fdr ignores material_ui's theme (its platform and `pageTransitionsTheme`) and labels the barrier in English. Options: document it (`NavPage.material`/`.cupertino` or a `CustomPage` there); pick the route from `defaultTargetPlatform`; let the app supply the route; or migrate fdr to material_ui and cupertino_ui (`package:flutter/material.dart` is deprecated on Flutter 3.50).
23. **Flutter version.** CI and publishing pin Flutter 3.47.5, where `flutter analyze` is clean. On 3.50, analyze fails on the deprecated `material.dart` and `cupertino.dart` imports (info level), and the committed lockfiles do not resolve with `--enforce-lockfile`. Options: develop on 3.47.5 too (a committed `.fvmrc`); move the three pins and both lockfiles to 3.50 together with item 22 or `--no-fatal-infos`; or stop committing the package's lockfile.
24. **Goldens.** The tests start through golden_toolkit, which is discontinued. Replacing it takes about 40 lines of plain `flutter_test` plus its Roboto font (or regenerated Android goldens), or another package. The goldens run only on macOS and compare exactly outside CI (0.05% on CI).

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
