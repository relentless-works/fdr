## 0.1.0-dev.1

* Add type-safe URL routing: a sealed route type per navigator, bidirectional URL codecs, `FdrRouter` for `MaterialApp.router` (see `doc/url-routing.md`)
* In-app pops go back in the browser history instead of adding entries; navigation while such a traversal is in flight is reported after it
* **Breaking**: `DeclarativeNavigatable<R>`, `StatefulNavigator<R>`, `StatefulNavigatorState<N, R>` and `StatelessNavigator<R>` take a route type (`Never` for navigators without URLs)
* **Breaking**: the pop contract moved to `Navigator.onDidRemovePage`, so `onPop` no longer runs when the state itself removed a page; `PageBuilder` now takes `canPop` and `key`; `FDRPage` is removed
* Reuse navigator states when runtime type and key match (instead of index and type check), and give every page a stable key
* Report an imperative `Navigator.pop` of a page without `onPop` instead of crashing; popup barrier taps go through `onPop`
* Android back on the bottom page leaves the app unless a `PopScope` vetoes
* Add `shell(...)`: a persistent page with one nested navigator per branch (e.g. tabs behind a bottom bar), each branch keeping its own stack; the URL follows the active branch
* Add `AsyncNavigator` and `initialRoute` on mounts: children receive loaded data instead of ids, deep links into separately loaded levels keep their URL while loading
* Restore a page's non-URL history state and in-app back traversal after a browser reload
* Add `FdrRouterDelegate.navigate` for typed links from outside the navigator tree (e.g. push notifications)
* Add `watch` on navigator states to rebuild when app state owned elsewhere changes, and `mounted`
* `.page()` picks a Material or Cupertino route from the Theme platform when the route is created (Material on the web, following the app's `pageTransitionsTheme`)
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
