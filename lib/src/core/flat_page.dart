part of 'core.dart';

/// Builds the Flutter [Page] of a flattened page.
///
/// The pop contract is enforced by the navigator that renders the pages
/// (through `Navigator.onDidRemovePage`), so the page itself only needs to
/// know whether it may be popped and which key it has.
typedef FlatPageBuilder = Page<Object?> Function(LocalKey key, bool canPop);

/// A page of a navigator's flattened page list: its own pages and those of
/// its child navigators, with routes in the navigator's route type.
final class FlatPage {
  FlatPage({
    required FlatPageBuilder builder,
    required this.onPop,
    this.route,
    this.key,
    this.keyBase,
    this.nestedPages,
  }) : _builder = builder; // ignore: prefer_initializing_formals

  final FlatPageBuilder _builder;

  /// `null` means the page cannot be popped (also blocks system back).
  final VoidCallback? onPop;

  /// The page's route, or `null` for pages without a URL.
  final Object? route;

  final LocalKey? key;

  /// Identity of the page instead of its route, e.g. for tabs whose route
  /// follows the active tab; repeats get `#n` like routes.
  final String? keyBase;

  /// For a tabs page: the keyed pages of the active tab, which the router's
  /// history logic looks into (a pop inside a tab is a pop).
  final List<KeyedPage> Function()? nestedPages;

  /// [forceCanPop] is set for the bottom page: `Navigator.maybePop` then
  /// bubbles (Android back leaves the app) instead of being vetoed, while a
  /// `PopScope` inside the page can still veto.
  Page<Object?> buildPage({
    required LocalKey defaultKey,
    bool forceCanPop = false,
  }) {
    return _builder(key ?? defaultKey, forceCanPop || onPop != null);
  }

  FlatPage withOnPop(VoidCallback? onPop) => FlatPage(
    builder: _builder,
    onPop: onPop,
    route: route,
    key: key,
    keyBase: keyBase,
    nestedPages: nestedPages,
  );

  FlatPage withRoute(Object? route) => FlatPage(
    builder: _builder,
    onPop: onPop,
    route: route,
    key: key,
    keyBase: keyBase,
    nestedPages: nestedPages,
  );
}
