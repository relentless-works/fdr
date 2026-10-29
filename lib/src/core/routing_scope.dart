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
/// requested by state changes to the router layer.
final class RoutingScope {
  HistoryAction _requested = HistoryAction.auto;

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
