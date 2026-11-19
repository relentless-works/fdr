## 0.1.0-dev.1

* **Breaking**: a navigator's `build()` returns entries, `Iterable<NavEntry<R>>` (a list literal or a `sync*` body): `NavPage`, `DialogPage`, `CustomPage`, `NestedNavigator`, `TabsPage` and child navigators. Their `onPop:` replaces `.poppable(onPop:)`, `NavPage` replaces `.page()`, and `DialogPage` or `CustomPage` replace `.popup()`. Removed: `DeclarativeNavigatable`, `DeclarativeNavigatablePage`, `PageBuilder`, `Poppable`, `PopOverwriteNavigatable`, `DisposableNavigatable`, `FDRPage` and the `DeclarativeNavigatableFromWidget` extension
* **Breaking**: `StatefulNavigator<R>`, `StatefulNavigatorState<N, R>` and `StatelessNavigator<R>` take a route type (`Never` for navigators without URLs) and an optional `key`. `StatefulNavigatorState.navigator` is read-only; `pages`, `updatePages()` and `isForNavigator()` are removed. `DeclarativeNavigator.navigator` is a `NavEntry`, and `DeclarativeNavigator.hotReload` is removed
* **Breaking**: the pop contract moved to `Navigator.onDidRemovePage`, so `onPop` runs for imperative pops only (back button, swipe, system back, barrier tap, `Navigator.pop`), not when the state itself removed a page. An imperative pop of a page without `onPop` is reported instead of crashing
* **Breaking**: navigator states are reused when runtime type and key match, so a keyed navigator keeps its state when it moves in the build list; unkeyed ones are matched by position. Every page gets a key: the path of its route, its `key:`, or, without a route, its offset above the routed page below it
* A `setState` while navigators update no longer builds at once: in a navigator's own `initState`, `didUpdateNavigator` or `applyRoute` it only runs its callback, and on any other navigator it rebuilds once the update is done. `setState` and `open` after `dispose` assert, and do nothing in release
* If a navigator's `initState`, `applyRoute` or `build` throws, its parent keeps the child states and pages it had, and the exception reaches the caller
* Hot reload builds each navigator once, from the root, and calls `didUpdateNavigator`; an error thrown by a navigator in it is reported and the rest of the app still reloads
* Android back on the bottom page leaves the app unless a `PopScope` vetoes. `DeclarativeNavigator` handles system back, also outside a route (`MaterialApp.builder`, directly under `runApp`), so Android back pops its pages first
* Add URL routing: a sealed route type per navigator extending `NavRoute`, with a static `fromUrl` and a `toUrl` for its own part of the URL, `applyRoute` on navigator states, and `FdrRouter` for `MaterialApp.router` (see `doc/url-routing.md`). `FdrRouter` takes `notFound:`, `popFallback:`, `browserHistory:` (`BrowserHistory`, `NoBrowserHistory`), `initialRouteInformation:`, `keepStateWithoutDeepLink:` (keep the navigators' state on a start without a deep link) and `rewriteUri:` (map other deep link forms), and has `open`, `currentUrl` and `dispose`. Creating it does not install the widgets binding; that happens on first use of `config` or `provider`
* Add `Url` and `NotFound`. A segment is an `int` in canonical form within ±(2^53 − 1), on every platform; `rest(n)` past the end throws `NotFound`; parsing resolves dot segments, reads percent-encoding that is not UTF-8 as Latin-1 and ignores the fragment; a parsed `Url` cannot be changed; `Url`s that print the same path and query values are equal
* A URL that does not parse completely shows its longest prefix that does, with a not-found page on top, at the URL as typed (printed canonically). A route from the platform whose `applyRoute` or `build` throws is reported, and the address bar shows what the app shows
* Add `open` on navigator states and `FdrRouter.open` for typed navigation, also from outside the navigator tree (e.g. push notifications). An `open` during an update (a redirect in `applyRoute`, `initState` or `build`) runs after it; its replace does not replace the entry a link came from, and more than 5 redirects in a row are reported as a loop. A route opened before the router starts wins over the platform's initial route and over a restored one
* Add `NavPage`, which picks a Material or Cupertino route from the Theme platform when the route is created (Material on the web, following the app's `pageTransitionsTheme`); `NavPage.material` and `NavPage.cupertino` choose one. A page the state removes during an iOS swipe back finishes its exit
* Add `DialogPage`, Material's dialog route without a URL; its child, `onPop` and barrier follow rebuilds
* Add `CustomPage` for any other Flutter `Page` (bottom sheets, custom transitions) with the pop contract; its builder has to pass `key` and `canPop` on (asserted in debug)
* Add `NestedNavigator`: a child navigator with its own route type, placed in the parent's by `at`; its `route` is applied when it is created and when an incoming route addresses it. A needed `at` that is missing is a `FlutterError` in every build mode
* Add `TabsPage`: a persistent page with one nested navigator per tab, each keeping its own stack, matched by key like a navigator; the URL follows the active tab, and at the active tab's root Android back goes to the owner, even if another tab could pop
* Add `FutureNavigator`: children receive loaded data instead of ids, and deep links into separately loaded levels keep their URL while loading. `onDispose` releases loaded values once they are no longer shown, never `initialData`
* Add `RouteLink`: a link to a route of the navigator that shows it or of a parent, resolved by the route's type, also in sheets, dialogs and menus a page opens. On the web it is a real `<a href>` (url_launcher's `Link`): the platform's new-tab key or shift opens a new tab or window, ctrl-click on macOS shows the context menu, and other clicks open in the app
* In-app pops go back in the browser history instead of adding entries. `HistoryAction` and `history:` on `setState`, `open`, `watch` and `listen` set the action explicitly. Navigation while a back is in flight is reported after it, also when the browser does not deliver it; a back the browser carries out late does not change what the app shows; a URL typed into the address bar keeps the entries before it; unchanged entries are not written again
* Add `historyState`, `restoreHistoryState` and `restorationType` on navigator states: non-URL state kept in the browser history entry and restored on back and forward, after a reload and after process death (`null` when the entry had none), also into navigators created later, such as below a loading `FutureNavigator`. A state that is not JSON, or that cannot be restored, is reported with its navigator
* Add `watch` and `listen` on navigator states to rebuild when app state owned elsewhere changes (a `Listenable`, a bloc's stream); both return a callback that cancels, and `listen` takes `onError`. Add `mounted`
* Debug checks: a `toUrl` whose URL parses to another URL, a query parameter printed by two levels, a `fromUrl` that does not return the root's route type, and a navigator tree without pages. A `createState()` that returns another navigator's state is a `FlutterError` naming both
* Depend on `url_launcher` and `web`
* Require Flutter 3.47 and Dart 3.13
* The published package no longer contains the tests and their goldens

## 0.0.5

* Support hot reload for all built-in navigators
* Add `StatelessNavigator`, akin to `StatelessWidget` for when the child pages are determined just from the arguments
* Remove `MappedNavigatableSource`, as a stateful instance (unlike the managed `NavigatorState`) just seems to easy to use wrongly (not retaining the instance, and thus recreating it over and over)

## 0.0.4

* Add `StatefulNavigator`, akin to `StatefulWidget`
  * Where the library takes care of managing the associated state object's lifecycle

## 0.0.3

* Add CI
* Publish tags automatically from GitHub
* Stricter analysis options

## 0.0.2

* Switch to new Flutter 3.24.0 Navigator API: `onDidRemovePage`
  * Make use of `Page.canPop` and `Page.onPopInvoke` to tell the framework which pages can be popped.  
    This can be configured / changed during the page's display, e.g. to prevent back swipes once a form contains changes.

## 0.0.1

* Initial release with basic page and navigtable source ("bloc for routing") support
