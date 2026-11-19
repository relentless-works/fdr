part of 'core.dart';

/// What a state change should do to the (browser) history.
enum HistoryAction {
  /// Derived from how the routed page stack changed: pages only removed from
  /// the top is a [pop], pages only added on top is a [push], anything else
  /// pushes when the URL changes and replaces otherwise.
  auto,

  /// Always add a history entry, even if the URL did not change.
  push,

  /// Replace the current entry (redirects, wizard steps, canonicalisation).
  replace,

  /// Go back in the browser history if a previous entry is the new URL (as
  /// many entries back as routed pages were removed from the top, at least
  /// one), otherwise fall back to the router's `popFallback`.
  pop,
}

/// Shared by all navigator states of one root; carries the history action
/// requested by state changes to the router layer, and links to the root.
final class RoutingScope {
  HistoryAction _requested = HistoryAction.auto;

  /// Set by the host: applies a route of the root's type from the root down.
  void Function(Object? route, HistoryAction history)? openRoot;

  /// Set by the router: the URL of a route of the root's type, for links.
  String? Function(Object? route)? hrefOf;

  // navigator passes in progress; an open() during one (a redirect in
  // applyRoute, an open() in initState) runs once the outermost one is done
  int _passes = 0;
  (Object?, HistoryAction)? _queuedOpen;

  /// Opens [route] (of the root's type) through [openRoot], after the
  /// navigator updates in progress, if any.
  void open(Object? route, HistoryAction history) {
    if (_passes > 0) {
      _queuedOpen = (route, history);
      return;
    }
    openRoot?.call(route, history);
  }

  // States asked to rebuild while another navigator's pass was running.
  // They rebuild once the outermost pass is done: rebuilding at once could
  // remove the navigator whose pass it is.
  final _deferred = <_AnyState>[];
  bool _settling = false;

  void _defer(_AnyState state) {
    if (!_deferred.contains(state)) _deferred.add(state);
  }

  void _rebuildDeferred() {
    // the passes of these rebuilds end here too
    if (_settling) return;
    _settling = true;
    try {
      while (_deferred.isNotEmpty) {
        final state = _deferred.removeAt(0);
        if (state._mounted) state._rebuild();
      }
    } finally {
      _settling = false;
    }
  }

  /// What waited for the outermost pass: deferred rebuilds, then a queued
  /// [open], which applies to the settled tree.
  void _settle() {
    if (_settling) return;
    _rebuildDeferred();
    _openQueued();
  }

  // The outermost pass threw. The states that wait for it still show their
  // changes, but an open() asked for by an update that failed is dropped:
  // it would run after the next, unrelated update.
  void _abandon() {
    _queuedOpen = null;
    _PageMapper._guarded(_rebuildDeferred);
    _queuedOpen = null;
  }

  // The routes of queued opens in progress: each one runs at the end of the
  // update of the one before, so routes that redirect to each other would
  // go on until the stack overflows.
  final _redirects = <Object?>[];
  static const _maxRedirects = 5;

  /// Whether the open being run through [openRoot] was queued during an
  /// update: a redirect, not a navigation of its own.
  bool get redirecting => _redirects.isNotEmpty;

  void _openQueued() {
    final queued = _queuedOpen;
    if (queued == null) return;
    _queuedOpen = null;
    if (_redirects.length == _maxRedirects) {
      _reportRedirectLoop([..._redirects, queued.$1]);
      return;
    }
    _redirects.add(queued.$1);
    try {
      openRoot?.call(queued.$1, queued.$2);
    } finally {
      _redirects.removeLast();
    }
  }

  // reported, not thrown: the opens in progress still finish, so the app
  // stays on the last route applied and the router reports its URL
  void _reportRedirectLoop(List<Object?> routes) {
    final chain = routes.map((route) => hrefOf?.call(route) ?? '$route');
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: FlutterError.fromParts([
          ErrorSummary(
            'open() was called during an update ${routes.length} times in a '
            'row: ${chain.join(' -> ')}',
          ),
          ErrorDescription(
            'Each of these routes was opened while the one before was '
            'applied (in applyRoute, initState or build). The last one was '
            'not opened.',
          ),
          ErrorHint(
            'Check the redirects for routes that lead back to each other.',
          ),
        ]),
        library: 'fdr',
      ),
    );
  }

  /// Set by the router delegate: the action implied by how the routed page
  /// stack changed since the previous report. Called once per report, so it
  /// also moves the delegate's baseline.
  HistoryAction Function()? stackChange;

  /// How many browser entries a pop may go back: the number of routed pages
  /// the stack change of the report removed from the top, also for a
  /// requested [HistoryAction.pop]; 1 for a requested pop with any other
  /// stack change.
  int popDepth = 1;

  void requestHistory(HistoryAction action) {
    if (action == HistoryAction.auto) return;
    _requested = action;
    if (action == HistoryAction.pop) popDepth = 1;
  }

  HistoryAction takeRequested() {
    final derived = stackChange?.call() ?? HistoryAction.auto;
    final requested = _requested;
    _requested = HistoryAction.auto;
    return requested == HistoryAction.auto ? derived : requested;
  }
}
