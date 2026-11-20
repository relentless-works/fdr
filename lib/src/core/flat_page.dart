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
    this.identity,
    this.owner,
    this.slot,
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

  /// What [Widget.canUpdate] compares, for a page: the kind of entry (with
  /// what selects its Route class) and its child's type and key. Part of the
  /// key of a page without a route, and tells a page from another one that
  /// has its route or `key:` after its `onPop`.
  final Object? identity;

  /// The navigator state (or host) whose build list the page is from, or
  /// the one that gave it its [slot].
  final Object? owner;

  /// Set for a page that stands for one page of [owner] whatever it shows:
  /// part of the key of a page without a route in place of [identity].
  final Object? slot;

  /// [forceCanPop] is set for the bottom page: `Navigator.maybePop` then
  /// bubbles (Android back leaves the app) instead of being vetoed, while a
  /// `PopScope` inside the page can still veto.
  Page<Object?> buildPage({
    required LocalKey defaultKey,
    bool forceCanPop = false,
  }) {
    final key = this.key ?? defaultKey;
    final canPop = forceCanPop || onPop != null;
    final page = _builder(key, canPop);
    // the builder of a CustomPage is the app's, which has to pass both on
    assert(
      page.key == key,
      'A CustomPage builder has to pass `key` on to its Page (got '
      '${page.key}, expected $key): a pop of the page is found by its key, '
      'so without it onPop does not run.',
    );
    assert(
      canPop || !page.canPop,
      'A CustomPage builder has to pass `canPop` on to its Page: the page '
      'has no onPop, but its Page can be popped.',
    );
    return page;
  }

  FlatPage withOnPop(VoidCallback? onPop) => FlatPage(
    builder: _builder,
    onPop: onPop,
    route: route,
    key: key,
    keyBase: keyBase,
    nestedPages: nestedPages,
    identity: identity,
    owner: owner,
    slot: slot,
  );

  FlatPage withRoute(Object? route) => FlatPage(
    builder: _builder,
    onPop: onPop,
    route: route,
    key: key,
    keyBase: keyBase,
    nestedPages: nestedPages,
    identity: identity,
    owner: owner,
    slot: slot,
  );

  /// The page as the page [slot] of [owner], for its key without a route.
  FlatPage inSlot(Object owner, Object slot) => FlatPage(
    builder: _builder,
    onPop: onPop,
    route: route,
    key: key,
    keyBase: keyBase,
    nestedPages: nestedPages,
    identity: identity,
    owner: owner,
    slot: slot,
  );
}

/// Implemented by a navigator state whose first page is one page in every
/// build, whichever navigator builds it and whatever its child is: the
/// loading page of a `FutureNavigator`, its error page and the first page of
/// the loaded child. Without a route, that page is then keyed as the first
/// page of this state, so it is updated in place like a routed page whose
/// path stays. Not exported from the package.
abstract interface class KeepsFirstPage {}
