## 0.1.0-dev.1

* Add URL routing: a sealed route type per navigator extending `NavRoute`, with a static `fromUrl` and a `toUrl` for its own part of the URL (`Url`, `NotFound`), and `FdrRouter` for `MaterialApp.router` (see `doc/url-routing.md`)
* A URL that does not parse completely shows its longest prefix that does, with a not-found page on top; the address bar keeps the URL as typed
* In-app pops go back in the browser history instead of adding entries; navigation while such a traversal is in flight is reported after it
* **Breaking**: a navigator's `build()` returns constructor entries, `Iterable<NavEntry<R>>`: `NavPage`, `DialogPage`, `NestedNavigator`, `TabsPage` and child navigators. `DeclarativeNavigatable`, `DeclarativeNavigatablePage`, `PageBuilder`, `.page()`, `.popup()` and `FDRPage` are removed
* **Breaking**: `StatefulNavigator<R>`, `StatefulNavigatorState<N, R>` and `StatelessNavigator<R>` take a route type (`Never` for navigators without URLs)
* **Breaking**: the pop contract moved to `Navigator.onDidRemovePage`, so `onPop` no longer runs when the state itself removed a page
* Reuse navigator states when runtime type and key match (instead of index and type check), and give every page a stable key
* Report an imperative `Navigator.pop` of a page without `onPop` instead of crashing; dialog barrier taps go through `onPop`
* Android back on the bottom page leaves the app unless a `PopScope` vetoes
* Add `NestedNavigator`: a child navigator with its own route type, placed in the parent's by `at`; its `route` is applied when it is created and when an incoming route addresses it
* Add `TabsPage`: a persistent page with one nested navigator per tab, each keeping its own stack; the URL follows the active tab
* Add `FutureNavigator`: children receive loaded data instead of ids, deep links into separately loaded levels keep their URL while loading
* Add `RouteLink`: a link to a route of the navigator that shows it or of a parent, resolved by the route's type, with a real `<a href>` on the web (url_launcher's `Link`)
* Add `open` on navigator states and `FdrRouter.open` for typed navigation, also from outside the navigator tree (e.g. push notifications); an `open` during an update (a redirect in `applyRoute`) runs after it
* Add `CustomPage` for any other Flutter `Page` (bottom sheets, custom transitions) with the pop contract, and `FdrRouter.dispose`
* `DeclarativeNavigator` handles system back, so Android back pops its pages before leaving the app; keyed child navigators keep their state when they move in the build list
* Restore a page's non-URL history state and in-app back traversal after a browser reload
* Add `watch` and `listen` on navigator states to rebuild when app state owned elsewhere changes (a `Listenable`, a bloc's stream), and `mounted`
* `NavPage` picks a Material or Cupertino route from the Theme platform when the route is created (Material on the web, following the app's `pageTransitionsTheme`); `NavPage.material` and `NavPage.cupertino` choose one
* Debug checks: a `toUrl` whose URL parses to another URL, a query parameter printed by two levels, and a `fromUrl` that does not return the root's route type
* Depend on `url_launcher`
* Require Flutter 3.47

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
