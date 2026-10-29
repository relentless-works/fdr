part of 'core.dart';

/// Builds the Flutter [Page] for a declarative page.
///
/// The pop contract is enforced by the navigator that renders the pages
/// (through `Navigator.onDidRemovePage`), so the page itself only needs to
/// know whether it may be popped and which key it has.
typedef PageBuilder = Page<Object?> Function({
  required bool canPop,
  LocalKey? key,
});

class DeclarativeNavigatablePage<R> implements DeclarativeNavigatable<R> {
  DeclarativeNavigatablePage({
    required PageBuilder builder,
    required this.onPop,
    this.route,
    this.key,
  }) : _builder = builder; // ignore: prefer_initializing_formals

  final PageBuilder _builder;

  /// Changes state such that this page is gone on the next build; `null`
  /// means the page cannot be popped (also blocks system back and swipe).
  final VoidCallback? onPop;

  /// The route this page is addressed by, in the route type of the navigator
  /// that built it. `null` for pages without a URL (popups, dialogs, ...):
  /// the URL then stays at the next routed page below.
  final R? route;

  /// Explicit page key; defaults to a key derived from [route] (or from the
  /// routed page below for pages without a route).
  final LocalKey? key;

  /// [forceCanPop] is set for the bottom page: `Navigator.maybePop` then
  /// bubbles (Android back leaves the app) instead of being vetoed, while a
  /// `PopScope` inside the page can still veto.
  Page<Object?> buildPage({LocalKey? defaultKey, bool forceCanPop = false}) {
    return _builder(
      canPop: forceCanPop || onPop != null,
      key: key ?? defaultKey,
    );
  }

  DeclarativeNavigatablePage<R> withOnPop({required VoidCallback? onPop}) {
    return DeclarativeNavigatablePage<R>(
      builder: _builder,
      onPop: onPop,
      route: route,
      key: key,
    );
  }

  /// Re-types the page for the parent navigator after embedding its route.
  DeclarativeNavigatablePage<P> withRoute<P>(P? route) {
    return DeclarativeNavigatablePage<P>(
      builder: _builder,
      onPop: onPop,
      route: route,
      key: key,
    );
  }
}
