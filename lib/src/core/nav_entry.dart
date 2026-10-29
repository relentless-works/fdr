part of 'core.dart';

/// An item of a navigator's [StatefulNavigatorState.build] list: a page, a
/// dialog, tabs, or a child navigator.
///
/// [R] is the route type of the navigator whose list the item belongs to.
/// Items without a URL ([DialogPage], navigators with route type `Never`)
/// fit into every list.
sealed class NavEntry<R> {}

enum _PageStyle { adaptive, material, cupertino }

/// A full-screen page.
///
/// [route] is the page's address in its navigator's route type: the URL while
/// it is the top page, and its identity (page key, history). A page without a
/// route has no URL of its own; the URL stays at the page below.
///
/// [onPop] changes the state so that the page is gone on the next build; it
/// runs for the back button, system back and swipe back. Without it the page
/// cannot be popped.
///
/// `NavPage()` uses a Cupertino route (swipe back) on iOS and macOS and a
/// Material route elsewhere, picked from the surrounding [Theme]'s platform;
/// on the web it is always the Material route, so the app's
/// `pageTransitionsTheme` decides. [NavPage.material] and [NavPage.cupertino]
/// pick one explicitly.
final class NavPage<R> implements NavEntry<R> {
  const NavPage({
    this.key,
    this.route,
    this.onPop,
    this.title,
    this.fullscreenDialog = false,
    this.maintainState = true,
    required this.child,
  }) : _style = _PageStyle.adaptive;

  const NavPage.material({
    this.key,
    this.route,
    this.onPop,
    this.fullscreenDialog = false,
    this.maintainState = true,
    required this.child,
  }) : title = null,
       _style = _PageStyle.material;

  const NavPage.cupertino({
    this.key,
    this.route,
    this.onPop,
    this.title,
    this.fullscreenDialog = false,
    this.maintainState = true,
    required this.child,
  }) : _style = _PageStyle.cupertino;

  /// Explicit page key; by default the key is derived from [route].
  final LocalKey? key;

  final R? route;
  final VoidCallback? onPop;

  /// For Cupertino routes: the navigation bar title and the next page's back
  /// label.
  final String? title;

  final bool fullscreenDialog;
  final bool maintainState;
  final Widget child;
  final _PageStyle _style;
}

/// A modal dialog. It has no URL: the URL stays at the page below, so a
/// reload or a shared link does not show it.
///
/// Barrier taps, the back button and `Navigator.pop(context)` (e.g. an OK
/// button in the dialog) all go through [onPop].
final class DialogPage implements NavEntry<Never> {
  const DialogPage({
    this.key,
    this.onPop,
    this.barrierDismissible = true,
    required this.child,
  });

  final LocalKey? key;
  final VoidCallback? onPop;
  final bool barrierDismissible;
  final Widget child;
}

/// A child navigator with its own route type [C], shown inside a navigator
/// with route type [P].
///
/// [at] places a child route in the parent's route type: the parent route
/// that contains it. It is used to print the child's URLs and to resolve
/// links from inside the child. Without [at], the child has the parent's
/// route type (or none, `Never`).
///
/// [route] is the child's part of the last route this navigator received:
/// the parent stores it in [StatefulNavigatorState.applyRoute] and passes it
/// here. The child receives it when it is created, and whenever an incoming
/// route (a URL, a link, `open`) addresses it, i.e. when `at(route)` prints
/// the same URL as the route the parent just received. So [at] has to
/// rebuild the parent's whole route, including query parameters the parent
/// owns. Between those, the child owns its state: rebuilding the parent does
/// not reset it. When the parent removes the child, it should clear the
/// stored route too, or a child created later by a plain `setState` starts
/// there.
///
/// [onPop] decides what popping the child's first page does, typically
/// removing the child.
final class NestedNavigator<P, C> implements NavEntry<P> {
  const NestedNavigator({this.at, this.route, this.onPop, required this.child});

  final P Function(C route)? at;
  final C? route;
  final VoidCallback? onPop;
  final StatefulNavigator<C> child;

  // The mapper only sees `NestedNavigator<Object?, Object?>`; reading [at]
  // through that view fails Dart's covariance check, so it is called here,
  // where P and C are known.
  Object? _lift(Object? route) {
    final at = this.at;
    return at == null ? route as P : at(route as C);
  }

  bool get _debugLiftsWithoutAt => at != null || <C>[] is List<P>;
}

/// Builds the persistent chrome around the tabs, e.g. a `Scaffold` with a
/// `NavigationBar`. Put [tabs] into an `IndexedStack` (or anything else that
/// keeps them mounted) so inactive tabs keep their pages and widget state.
typedef TabsBuilder = Widget Function(BuildContext context, List<Widget> tabs);

/// A page with one nested navigator per tab, e.g. behind a bottom navigation
/// bar.
///
/// Each tab keeps its own page stack; the chrome does not animate when pages
/// are pushed inside a tab. The URL is the active tab's. An incoming route is
/// offered to every tab; a tab's [NestedNavigator] takes it if it addresses
/// that tab.
///
/// The page keeps its identity while the tab or the route inside a tab
/// changes; an explicit [key] has to do the same.
final class TabsPage<R> implements NavEntry<R> {
  const TabsPage({
    this.key,
    required this.index,
    required this.tabs,
    required this.builder,
    this.onPop,
  });

  final LocalKey? key;
  final int index;
  final List<NavEntry<R>> tabs;
  final TabsBuilder builder;
  final VoidCallback? onPop;
}

/// Builds the Flutter [Page] of a [CustomPage]. It has to pass [key] and
/// [canPop] on to the page (`Page.key`, `Page.canPop`), and show [child].
typedef CustomPageBuilder = Page<Object?> Function(
  LocalKey key,
  bool canPop,
  Widget child,
);

/// A page whose Flutter [Page] the app builds, e.g. a modal bottom sheet or a
/// custom transition. Otherwise like [NavPage]: [route] gives it a URL, and
/// [onPop] runs for back, swipe, barrier taps and `Navigator.pop`.
///
/// ```dart
/// CustomPage(
///   onPop: () => setState(() => filtering = false),
///   builder: (key, canPop, child) => SheetPage(key: key, canPop: canPop, child: child),
///   child: FilterSheet(...),
/// )
/// ```
final class CustomPage<R> implements NavEntry<R> {
  const CustomPage({
    this.key,
    this.route,
    this.onPop,
    required this.builder,
    required this.child,
  });

  final LocalKey? key;
  final R? route;
  final VoidCallback? onPop;
  final CustomPageBuilder builder;
  final Widget child;
}
