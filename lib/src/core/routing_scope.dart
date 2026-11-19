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

  /// Go back in the browser history if the previous entry is the new URL,
  /// otherwise fall back to the router's `popFallback`.
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

  void _openQueued() {
    final queued = _queuedOpen;
    if (queued == null) return;
    _queuedOpen = null;
    openRoot?.call(queued.$1, queued.$2);
  }

  /// Set by the router delegate: the action implied by how the routed page
  /// stack changed since the previous report. Called once per report, so it
  /// also moves the delegate's baseline.
  HistoryAction Function()? stackChange;

  /// How many routed pages the last derived [HistoryAction.pop] removed, i.e.
  /// how many browser entries it may go back; 1 for a requested pop.
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
