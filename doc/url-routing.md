# Type-safe URL routing for fdr

Status: implemented in `lib/`, verified on Flutter 3.47.5 by widget tests (`test/`, worked examples in `test/routing/`), compile-time checks (`dart run tool/check_typing.dart`) and a scripted run of the URL demo in headless Chrome against the real engine history (`tool/browser_probe.sh`); CI runs all three. The runnable demo is `example/lib/main_url_routing.dart` (`flutter run -d chrome -t lib/main_url_routing.dart` in `example/`).

## 1. Changes to the core

These came out of 14 scratch tests against fdr 0.0.5 and are needed regardless of URLs:

| fdr 0.0.5 defect | Status |
|---|---|
| State reuse by index + `item is T` keeps a parent-type state when a subtype is swapped in; `StatelessNavigator`'s raw-typed state crashes on a Stateless→Stateful swap | Fixed: reuse when `runtimeType` and `key` match (Flutter's `Widget.canUpdate` rule) |
| Pages are unkeyed, and the forked pages cannot take a key | Fixed: library-derived keys (section 6) |
| `onPop!()` crashes on imperative `Navigator.pop` of a non-poppable page | Fixed: the pop contract moved to `onDidRemovePage`, misuse is reported (section 6) |
| `.popup()` ignores `onPop`: a barrier tap desyncs state and the popup comes back on the next rebuild | Fixed: barrier and back go through the same contract |
| `onDidRemovePage` is a `debugPrint` | Fixed: it is now the pop contract |
| Platform chosen by `defaultTargetPlatform == android`: web and desktop get Cupertino routes and swipe-back | Fixed: `FDRPage` chooses its route from the Theme platform (section 12) |
| Rebuild cascade: a leaf `setState` at depth 3 runs 4 leaf builds and spurious `didUpdateNavigator` calls | Open: `identical()` short-circuit and a `setState` phase guard |

## 2. The idea in one paragraph

The URL is a **typed projection of the navigator tree**. Every navigator that takes part in URLs declares a sealed route type. A parent's route embeds its child's route (`HomeAt(OrdersAt(OrderDetail(42)))`), so the sealed hierarchy mirrors the navigator tree. Each navigator declares **one bidirectional codec** built from small combinators; one declaration yields both parse and print, so they cannot drift. Only the root ever touches a `Uri`. Pages say which route addresses them (`.page(route: OrderDetail(id))`), and mounted children are lifted into the parent's route type. The URL is therefore the route of the top-most routed page, i.e. it follows exactly the chain that produced what is on screen. An incoming URL is parsed completely and purely into a typed route first. It is then applied top-down: each navigator sets its own fields in `applyRoute` *before* its build, and hands the unwrapped child route to the retained child state. No code generation, hot-reload friendly.

## 3. API at a glance (from `test/routing/example_app.dart`)

### Routes: one sealed type per navigator

```dart
sealed class AppRoute {}
final class LoginRoute extends AppRoute { const LoginRoute({this.next}); final HomeRoute? next; }
final class HomeAt extends AppRoute { const HomeAt(this.child); final HomeRoute child; }
final class NotFoundRoute extends AppRoute { const NotFoundRoute(this.uri); final Uri uri; }

sealed class HomeRoute {}
final class OrdersAt extends HomeRoute { const OrdersAt(this.child); final OrdersRoute child; }
final class SettingsAt extends HomeRoute { const SettingsAt(this.child); final SettingsRoute child; }

sealed class OrdersRoute {}
final class OrderList extends OrdersRoute { const OrderList(); }
final class OrderDetail extends OrdersRoute { const OrderDetail(this.id); final int id; }
final class OrderItem extends OrdersRoute { const OrderItem(this.id, this.item); final int id, item; }
```

### Codecs: composed bottom-up, the child codec knows nothing about its prefix

```dart
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
  // exhaustive switch: a new OrdersRoute subtype is a compile error here;
  // bind() only accepts the case's own subtype, so swapped branches don't compile
  select: (r) => switch (r) {
    final OrderDetail d => orderDetail.bind(d),
    final OrderItem i => orderItem.bind(i),
    final OrderList l => orderList.bind(l),
  },
);

// declared once, used by the parent codec AND the parent's build list
const ordersLens = RouteLens<HomeRoute, OrdersRoute>(embed: OrdersAt.new, unwrap: _ordersOf);
final ordersAt = lit('orders').then(ordersCodec).embedded(ordersLens);

final login = Case<AppRoute, LoginRoute>(
  lit('login').then(Query.route('next', homeCodec).optional).atEnd   // /login?next=%2Forders%2F42
      .iso(to: (next) => LoginRoute(next: next), from: (r) => r.next),
);
final legacyOrder = alias<AppRoute, int>(                             // parse-only: /order/42
  lit('order').then(Seg.int).atEnd, (id) => HomeAt(OrdersAt(OrderDetail(id))),
);
```

### Navigators: same feel as today, plus `applyRoute` and `route:`

```dart
class OrdersNavigatorState extends StatefulNavigatorState<OrdersNavigator, OrdersRoute> {
  int? selectedId;
  int? selectedItem;
  bool showPopup = false;
  int counter = 0; // non-URL state: survives every URL change

  @override
  void applyRoute(OrdersRoute route) {          // only this navigator's own fields
    showPopup = false;
    final (id, item) = switch (route) {
      OrderList() => (null, null),
      OrderDetail(:final id) => (id, null),
      OrderItem(:final id, :final item) => (id, item),
    };
    (selectedId, selectedItem) = (id, item);
  }

  @override
  List<DeclarativeNavigatable<OrdersRoute>> build() => [
    OrderListPage(onOpen: (id) => navigate(OrderDetail(id)))     // typed in-app link
        .page(onPop: null, route: const OrderList()),
    if (selectedId case final id?)
      OrderDetailPage(id: id, onDone: () => setState(() => selectedId = null))
          .page(onPop: () => setState(() => selectedId = null), route: OrderDetail(id)),
    if (showPopup)
      const PopupContent().popup(onPop: () => setState(() => showPopup = false)), // no URL
  ];
}

// in HomeNavigatorState.build: both tabs stay in the list, the inactive one builds [],
// so its state (and stack) survives tab switches
OrdersNavigator(active: tab == HomeTab.orders).mountWith(ordersLens),
```

### Wiring

```dart
final router = FdrRouter<AppRoute>(
  root: const AppNavigator(loggedIn: false),
  codec: appCodec,
  notFound: NotFoundRoute.new,   // typed 404 that prints the typed-in URL back
);
runApp(MaterialApp.router(routerConfig: router.config, restorationScopeId: 'app'));
```

## 4. The two directions

**State → URL.** The mapper already flattens the tree. Each page carries `route` in its own navigator's type, and when a child's pages are appended to the parent's list they are re-typed through the mount's `embed`. After flattening, every page holds a root-typed route or null. `currentConfiguration` is the route of the top-most routed page plus a JSON tree of non-URL `historyState` per navigator. The Router reads it after every rebuild and reports once, post-frame, so intermediate states inside one event never reach the address bar and there is no URL flicker during transitions.

With several child navigators and several pages in one `build()` list, nothing needs to be declared: the page list *is* the chain. A popup on top keeps the URL of the page below. A not-found page the root puts on top prints the typed URL.

**URL → state.** `parseRouteInformation` runs `codec.decode(uri) ?? notFound(uri)`. This is pure and total, so a URL that fails at any level is rejected *before* any navigator is touched. One reviewer showed that the "page segments" design created and disposed states along a half-matching prefix; that cannot happen here.

`setNewRoutePath` is idempotent: if the incoming route prints to the current URL, nothing is touched. Otherwise `updatePages([root], incomingRoute: route)` walks the tree. For each mounted child, `unwrap` extracts its part; a `null` means "not addressed", so an inactive tab keeps its stack. A retained state gets `didUpdateNavigator`, then `applyRoute(childRoute)`, then its build. A new state gets `initState`, then `applyRoute`, then its *first* build, so the default page never flashes.

The parser is a list-of-successes parser: every combinator yields all matches lazily and `decode` takes the first one that consumed the whole path. Reordering `cases` cannot turn a valid URL into a 404, because a prefix match no longer hides a later full match. The snapshot-first review found exactly this bug in the ordered, non-backtracking variant.

**Verified engine facts this rests on (Flutter 3.47.5 source).**

- Browser back and forward send the *same* `pushRouteInformation{location, state}`; the engine strips its serial count, so `setNewRoutePath` must be a pure "set the tree to this" (`engine/.../navigation/history.dart:181-205`).
- `RouteInformation.state` must be JSON (the navigation channel uses `JSONMethodCodec`). It round-trips through `history.state` on back/forward and through the restoration bucket, but **not on reload**: after a reload only the path arrives (`platform_dispatcher.dart:1486-1490`). Whatever must survive a reload belongs in the URL.
- `PlatformRouteInformationProvider` decides push vs replace by comparing path, fragment and query only, never state (`router.dart:1519-1542`).

## 5. Browser history: no more [A, B, A]

Flutter's default turns an in-app pop into a *new* entry, so browser back resurrects the popped page. This is the top complaint across go_router (#164969, #116440), beamer (#646) and the Flutter docs. The design fixes it with three pieces.

1. **The intent comes from the page-stack diff, not from which callback fired.** The delegate compares the keys of the routed pages at each report with the previous report. Pages only removed from the top means a pop of depth *k*. Pages only added on top means a push. Anything else pushes if the URL changed and replaces otherwise. An explicit `setState(fn, history: HistoryAction.replace)` (wizard steps, login) or `.push` (logout, tab switch) wins over the diff. This also covers state-driven removals (a Done button, a deleted order), which never go through `onPop`.
2. **A pop becomes a real traversal.** The provider keeps a shadow of the entries this session created. Entries carry `{fdr: 1, s: sessionId, i: serial, h: historyState, b: [[serial, url], …]}`: the session id, the entry's serial, the non-URL state, and the entries before it (up to 32), which lets a reloaded page continue the session (section 11). If one of the previous *k* entries has the new URL, the provider calls `window.history.go(-steps)` instead of reporting. When the engine delivers that entry, it is absorbed: no apply, no report.
3. **Reports during a traversal are deferred** until the awaited entry arrives, then sent as one report, kept a push if any deferred change was a push. An entry that does not match the awaited serial means the user moved through the history on their own, and the browser wins. Without this, a tab switch between `history.back()` and its `popstate` was undone; the snapshot-first review reproduced that.

The fallback when traversal is impossible is Flutter's push: no matching entry, for example after a cold start on a deep link, or not on the web. It is configurable to replace. A route delivered by the platform is always reported back as a replace, which canonicalises `/order/42` to `/orders/42` and `/login` while logged in to `/` in place. The first report replaces the engine's initial entry.

**Real-browser check.** `tool/browser_probe.sh` builds `example/lib/main_browser_probe.dart` and runs it in headless Chrome (also a CI job). The probe drives the URL demo through the real engine history and checks the app's URL, the address bar and the number of history entries after each of 18 steps:

- opening an order and an item, both loaded asynchronously;
- a state-driven pop, a system back inside a tab, browser forward and back;
- opening three levels in one go, then closing them in one change (`history.go(-2)`);
- a real page reload, after which an in-app back still traverses and forward still works;
- a tab switch, browser back into the other tab;
- an unknown URL typed into the address bar, and browser back from it.

Forward only works if the pops before it were real traversals, so a pop that pushed instead would fail the following step.

## 6. The pop contract and page keys

**Use `onDidRemovePage`, not `Page.onPopInvoked`.** When the pages list drops a page, the Navigator still calls `Page.onPopInvoked(true)` on it (`DefaultTransitionDelegate` → `markForPop` → `handlePop`, `navigator.dart:3587-3604, 3357-3379`). fdr's `onPopInvoked: onPop!()` therefore re-runs `onPop` after state-driven removals, during the build phase. `onDidRemovePage` fires *only* for imperative removals: back button, iOS swipe commit, Android back via `maybePop`, popup barrier tap, `Navigator.pop`. The library looks up the removed page **by key** in the *current* page list and runs that page's current `onPop`.

| Situation | Outcome |
|---|---|
| Page no longer in the list | The state already removed it; nothing to do |
| `onPop == null` | Misuse; reported with `FlutterError.reportError`, never thrown, because a throw inside the Navigator's locked update bricks it in debug mode (the snapshot-first review reproduced this) |
| Page still built after `onPop` ran | Reported |

Lookup by key instead of object identity fixes a pop being swallowed when it races an unrelated rebuild in the same frame. Two reviews found that swallowing in identity-based guards.

**Keys.**

- A routed page gets a `ValueKey` of its printed **path without query**. So `/orders?page=2` → `?page=3` updates the list page in place, while `/orders/42` → `/orders/43` is a new route with a transition and fresh widget state. Duplicates get `#n`.
- A page without a route gets the key of the routed page below it plus its offset.
- An explicit `key:` wins.
- Navigator states are reused on `runtimeType` + `key`.

This is your point about Flutter list semantics: the Navigator's matching stays as is, and the library just always hands it keys.

**Root back.** The bottom page is built with `Page.canPop = true`, so `maybePop` *bubbles* and Android back leaves the app. A `PopScope(canPop: false)` on the root page still vetoes, and predictive back works, because the Navigator then reports `canHandlePop = false`. The forked Material/Cupertino routes now use `super.canPop && page.canPop` for the back button, so the bottom page still shows none. Short-circuiting on `!navigator.canPop()` instead would skip the root page's `PopScope`. The forks themselves are still required on 3.47.5: the SDK's page routes ignore `Page.canPop` for `impliesAppBarDismissal` (`routes.dart:2250, 2258`).

## 7. What the type system catches

`tool/typing/mistakes.dart.fixture` holds deliberate mistakes; `dart run tool/check_typing.dart` (a CI step) checks that each fails to compile with the expected diagnostic and that nothing else fails:

| Mistake | Caught |
|---|---|
| New route subtype without a printer | compile: `non_exhaustive_switch_expression` |
| `select` hands a value to the wrong case (swapped branches) | compile: `argument_type_not_assignable` (`bind(S)`) |
| Route field retyped `int` → `String` | compile: in the codec's `iso` (both directions) |
| A page addressed by another navigator's route type | compile: `argument_type_not_assignable` |
| A typed link (`navigate`) to another navigator's route | compile: `argument_type_not_assignable` |
| A pending `initialRoute` of the wrong route type | compile: `argument_type_not_assignable` |
| An `AsyncNavigator` building a child of another route type | compile: `return_of_invalid_type_from_closure` |
| Renamed or removed route class | compile: plain name resolution |
| Typed link to a non-existent route | impossible: links are route values printed by the codec |
| Literal segment renamed (`'orders'` → `'order'`) | **test**: golden URL table |
| Two cases that can parse the same URL | **test**: round-trip of every row |
| A navigator mounted but its route never reachable | **test**: round-trip of the derived URL of each fixture state |

The contract test you ship with an app is a golden table of `(route, url)` rows. For each row, `encode(route) == url` and `encode(decode(url)) == url`, plus a list of URLs that must be rejected. "C10 golden URL table and round trips" in `test/routing/url_routing_test.dart` is the template.

**Code generation is not needed.** The codegen design (evaluated, not built) found it buys only the `:id` ↔ constructor mapping (about 3 lines per route), `==`/`hashCode`, and a route table for tooling. It costs build_runner in the hot-reload loop and generated-file churn, and it *weakens* one guarantee: a retyped field silently regenerates a different public URL instead of failing to compile. If anything, publish a generator later as an optional, ejectable package.

## 8. Mobile parity

- **Android back.** `RootBackButtonDispatcher` → `popRoute` → `maybePop` → `Page.canPop` / `PopScope` → `onDidRemovePage` → `onPop`. One path for back arrow, swipe, system back and barrier tap.
- **OS deep links.** These arrive through the same `pushRouteInformation` as browser navigation. The parser normalises scheme and host, so `https://shop.example/orders/7` → `/orders/7`, and for custom schemes the host is the first segment: `myapp://orders/42` → `/orders/42`. A naive `uri.path` drops `orders` there; the page-segments review found it. The normaliser is configurable.
- **Process death.** `MaterialApp.router(restorationScopeId: ...)` makes the Router persist `restoreRouteInformation(currentConfiguration)` (URL + JSON history state) and replay it through `setRestoredRoutePath`. No page `restorationId`s are needed for the stack itself. The test uses `tester.restartAndRestore()`.
- **Auth guard with a pending deep link.** No redirect function. The root's `applyRoute` keeps the typed target (`pendingNext = child`) while logged out. The login page prints it as `/login?next=%2Forders%2F42`, which survives a reload. `login()` calls `navigate(HomeAt(target), history: HistoryAction.replace)`, so no login entry is left behind.

## 9. Persistent tab shell

A navigator's build list can contain one `shell(...)`: a single page with a stable key in the owner's stack, whose body hosts one nested Navigator per branch. Pages pushed inside a tab animate inside the tab; the chrome around it never moves. Each branch keeps its retained navigator states and its stack while another tab is shown.

```dart
@override
List<DeclarativeNavigatable<ShopRoute>> build() => [
  shell(
    active: tab,
    branches: [
      OrdersNavigator(api: api).mount(embed: OrdersTab.new, unwrap: ...),
      const SettingsNavigator().mount(embed: SettingsTab.new, unwrap: ...),
    ],
    builder: (context, branches, active) => Scaffold(
      body: IndexedStack(index: active, children: branches),
      bottomNavigationBar: NavigationBar(
        selectedIndex: active,
        onDestinationSelected: _select,
        destinations: const [...],
      ),
    ),
  ),
];
```

- **URL.** The shell page's route is the active branch's top route, so the URL follows the visible tab. An incoming route goes to every branch and the mounts decide which one it addresses, so `/settings/profile` selects the settings tab and opens the profile there while the orders tab keeps its detail page.
- **History.** The page-stack diff looks into the active branch, so a pop inside a tab is a browser back.
- **Back.** Android back reaches the active branch's Navigator through `NavigatorPopHandler`; at a branch's root it bubbles to the owner, so the app is left. A vetoed pop is announced to every `PopScope` of the shell's route, so inactive branches ignore it explicitly.
- **Per branch.** Each nested Navigator gets its own `HeroController`, and inactive branches are muted with `TickerMode`.
- **Without a Router.** The shell also works in a plain `DeclarativeNavigator` (`example/lib/src/examples/tab_shell_navigator.dart`).

## 10. Async data loading

The goal: a child navigator receives a domain model (an `Order`), not an id, and never deals with loading or errors of its own input; deep links into nested, separately loaded levels must still work. Making route resolution asynchronous would push that complexity into every level (cancellation, stale results, partial trees). Instead, resolution stays synchronous, and loading is ordinary navigator state:

- **The pending sub-route is data.** A navigator whose child needs loaded data keeps the incoming sub-route while it loads. `mount(..., initialRoute: pending)` hands it to the child when the child's state is created, before its first build.
- **The URL does not move.** While loading, or after a failure, the loading or error page is addressed by the pending route. The URL stays where the user is going, and finishing the load is a replace, not a new entry.
- **Identity by key.** What is loaded is identified by the navigator's key; a different key is a different state, so a load still in flight for the old key is ignored. Leaving releases the value.

`AsyncNavigator` packages this:

```dart
if (selected case final id?)
  AsyncNavigator<Order, OrderRoute>(
    key: ValueKey(id),
    load: () => api.order(id),
    initialData: alreadyLoaded,          // e.g. tapped in a list: no loading page
    onDispose: (order) => ...,           // release a controller built from it
    loading: const LoadingPage(title: 'Order'),
    failed: (error, retry) => ErrorPage(error: error, retry: retry),
    builder: (order, reload) => OrderNavigator(order: order, reload: reload),
  ).mount(
    embed: (child) => OrderAt(id, child),
    unwrap: (route) => switch (route) {
      OrderAt(id: final routeId, :final child) when routeId == id => child,
      _ => null,
    },
  ).poppable(onPop: () => setState(() => selected = null)),
```

A deep link to `/orders/42/items/3/reviews` shows the order's loading page, then the order with the item's loading page on top, then the reviews, always at the same URL and in one history entry. Back then walks the stack the link implied. `reload` keeps the data on screen and hands new data to the same child state (`didUpdateNavigator`). Covered by `test/routing/async_test.dart`: two levels, error and retry, a newer URL racing a slow load, leaving mid-load, already loaded data, reload, release.

Not covered by design: holding the old screen until data is ready (a "loader before commit", as in Remix). It would need asynchronous `applyRoute`, with cancellation and partial trees; the loading page is the fdr answer.

## 11. History across reloads

After a reload the engine passes only the path to the framework (flutter/flutter#108697), but the browser still has the entry's state. The provider reads it through `BrowserHistory.currentState` (`window.history.state`) when it starts. If the entry was written by this app, it continues that session: the entry's non-URL state is applied with the initial route, and the recorded earlier entries let an in-app back still go back in the browser history. Entries after the current one are learned when the browser delivers them.

## 12. Pages per platform

`.page()` builds an `FDRPage` that chooses its route when the Navigator creates it, from `Theme.of(context).platform`: a Cupertino route with swipe back on iOS and macOS, a Material route elsewhere. On the web it is always the Material route, so the app's `pageTransitionsTheme` decides the transition (a fade for web is one theme entry). Before, the choice was `defaultTargetPlatform == android`, made without a context, which gave desktop and web the iOS slide and swipe gesture and ignored Theme overrides.

## 13. Dependencies and app state

Dependencies flow down as constructor arguments, as with widgets, and navigators own the state their subtree needs: what a navigator state creates in `initState` it disposes in `dispose`, and `AsyncNavigator` owns loaded data the same way. Two additions:

- **`watch(listenable)`** in `initState` rebuilds a navigator whenever app state owned elsewhere changes (a session, a repository), and the subscription ends with the state. `build()` reads the current value directly, so navigation cannot drift from that state.
- **`router.delegate.navigate(route)`** applies a typed route from outside the tree, for example from a push notification handler. The history action follows from the stack change, like any in-app navigation.

## 14. Open problems

1. **Lazy branches.** A shell creates every branch's navigator up front; building a branch on first visit would save work for heavy tabs.
2. **Rebuild cascade and `setState` phase guard** (base fdr defects).
3. **Query parameters share one namespace along a chain.** Two levels declaring `?page` collide silently. Add a debug assert when printing.
4. **Hot reload of top-level `final` codecs needs a hot restart.** Navigator builds reload fine (`C9` test).
5. **Navigator/state pairing.** `createState()` returning a state of another navigator with the same route type compiles. Option: self-bound generics (`StatefulNavigator<Self, R>`), verified feasible by a reviewer, or a Flutter-style debug assert.
6. **Path URL strategy** (`usePathUrlStrategy`) needs a `<base href>` and server rewrites. The router prints absolute paths that work with both strategies; only the hash strategy was run in Chrome.
7. **An awaited `popstate` that never arrives** would defer reports forever. It cannot happen in multi-entry mode, which the provider always selects, but a timeout fallback would make it robust.
8. **Sheets and dialogs as pages.** Material bottom sheets and dialogs wired to the pop contract are still missing; `.popup()` is Cupertino only.

## 15. How this design was chosen

Four designs were prototyped independently and compared:

- **Typed tree** (this one).
- **Page segments:** `.page(path:)` plus per-navigator route tables. Print and parse were two unlinked declarations, so an app could print URLs it cannot parse back.
- **Snapshot first:** the whole tree as a JSON snapshot, with the URL as a projection. It contributed the `onDidRemovePage` contract and the rule that a platform-delivered route is reported back as a replace.
- **Code generation:** evaluated, see section 7.

Adversarial reviews of the alternatives found the issues fixed here: pop detection by object identity, intent derived from the pop callback, root back skipping `PopScope`, custom-scheme deep links, the non-backtracking parse, the unchecked `select`, and the traversal race.
