# fdr examples

Demos of [fdr](../README.md). Like the package, they need Flutter 3.47 or newer. Run the commands in this directory.

## Small examples: `lib/main.dart`

```sh
flutter run
```

A list of navigators without URLs (route type `Never`). Each one opens as a child navigator:

- **List Detail**: a list of numbers. Picking one shows its detail page, and 7 shows a dialog (`DialogPage`).
- **Dynamic back behavior**: a switch turns the page's `onPop` on and off, and with it the back button and back swipe.
- **Stateful Navigator** and **Stateless Navigator**: a ticking `StatefulNavigator` and a `StatelessNavigator` to try hot reload with.
- **Overlay Portal**: an `OverlayPortal` on a navigator page.
- **Tab shell**: `TabsPage` with two tabs behind a persistent bottom bar. Each tab keeps its own stack.

## URL routing: `lib/main_url_routing.dart`

```sh
flutter run -d chrome -t lib/main_url_routing.dart
```

A small shop (`lib/url_routing/shop.dart`) with typed routes. It is best tried in a browser, where the address bar, reload, back and forward and the links work. It has:

- tabs for orders and settings;
- orders and items loaded by id with `FutureNavigator`;
- a sorted and filtered order list;
- `RouteLink`s;
- an error dialog without a URL;
- a not-found page for URLs that do not parse.

The file's header lists the URLs. [doc/url-routing.md](../doc/url-routing.md) explains the design.

## Browser check: `lib/main_browser_probe.dart`

This entry point drives the shop through the real browser history and checks the app's URL, the address bar and the number of history entries after every step. It is not meant to be run by hand. CI runs it in headless Chrome with `tool/browser_probe.sh` from the repository root.

## Tests

```sh
flutter test
```
