part of 'core.dart';

typedef KeyedPage = (LocalKey key, FlatPage page);

/// Keys a flattened page list so the Navigator pairs old and new pages by
/// identity instead of position: explicit keys win; a routed page is keyed by
/// [routeKey] of its route (`#n` for repeats, a printed path has no `#`); a
/// page without a route gets a [_RouteLessKey], which matches it like an
/// unkeyed widget among the pages above the same routed page.
List<KeyedPage> keyPages(
  List<FlatPage> pages,
  String? Function(Object route) routeKey,
) {
  final seen = <String, int>{};
  final seenAbove = <(Object?, Object?), int>{};
  final result = <KeyedPage>[];
  LocalKey? below;
  for (final page in pages) {
    final route = page.route;
    final base = page.keyBase ?? (route == null ? null : routeKey(route));
    final explicit = page.key;
    final LocalKey key;
    if (base != null) {
      if (explicit != null) {
        key = explicit;
      } else {
        final n = seen.update(base, (c) => c + 1, ifAbsent: () => 0);
        key = ValueKey(n == 0 ? 'fdr:$base' : 'fdr:$base#$n');
      }
      // also for an explicit key: the pages above e.g. a shell stay stable
      // while its route changes
      below = key;
      seenAbove.clear();
    } else if (explicit != null) {
      key = explicit;
    } else {
      final kind = (page.owner, page.identity);
      final n = seenAbove.update(kind, (c) => c + 1, ifAbsent: () => 0);
      key = _RouteLessKey(below, page.owner, page.identity, n);
    }
    result.add((key, page));
  }
  return result;
}

/// The key of a page without a route and without a key of its own: what
/// `Element.updateChildren` would match an unkeyed widget by, among the pages
/// above the same routed page. So a page that comes or goes below it does not
/// hand its Route and widget state to another page; pages that are equal in
/// all of this are matched in order.
///
/// Compared by the types themselves, not their names, which a release build
/// for the web minifies.
final class _RouteLessKey extends LocalKey {
  const _RouteLessKey(this.below, this.owner, this.identity, this.occurrence);

  /// Key of the nearest routed page below, `null` without one.
  final LocalKey? below;

  /// The navigator state (or host) that built the page: a page is not taken
  /// for one of another navigator, whose state it does not own.
  final Object? owner;

  /// [FlatPage.identity]: the kind of entry and its child's type and key.
  final Object? identity;

  /// Index among the pages equal in the above, from the bottom.
  final int occurrence;

  @override
  bool operator ==(Object other) =>
      other is _RouteLessKey &&
      other.below == below &&
      identical(other.owner, owner) &&
      other.identity == identity &&
      other.occurrence == occurrence;

  @override
  int get hashCode =>
      Object.hash(below, identityHashCode(owner), identity, occurrence);

  @override
  String toString() =>
      '[fdr: $identity#$occurrence of ${owner.runtimeType} above $below]';
}

/// The pop contract, applied where the SDK reports exactly the imperative
/// removals (back button, swipe, system back, barrier tap, `Navigator.pop`):
/// `Navigator.onDidRemovePage`. Removals caused by a state change never get
/// here, so `onPop` cannot run twice. [current] is evaluated lazily against
/// the latest state, so a pop that races an unrelated rebuild still finds its
/// page by key.
void applyPopContract(
  Page<Object?> removed,
  List<KeyedPage> Function() current,
) {
  final match = current().where((e) => e.$1 == removed.key).firstOrNull;
  if (match == null) return; // the state already removed it
  final onPop = match.$2.onPop;
  if (onPop == null) {
    _reportPopMisuse(
      'Page ${removed.key} was popped imperatively (Navigator.pop) but has '
      'onPop == null. Pages are removed by changing the state that builds '
      'them; the page is shown again on the next build.',
    );
    return;
  }
  onPop();
  // checked after the microtasks, so a store whose stream delivers its new
  // state asynchronously (a bloc) has rebuilt the navigator by then
  final identity = match.$2.identity;
  Timer.run(() {
    if (current().any(
      (e) => e.$1 == removed.key && e.$2.identity == identity,
    )) {
      _reportPopMisuse(
        'onPop of page ${removed.key} ran but the state still builds the '
        'page; onPop must change the state so the page disappears.',
      );
    }
  });
}

// reported, not thrown: this runs inside the Navigator's locked history
// update, where a throw would leave the Navigator unusable
void _reportPopMisuse(String message) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: FlutterError(message),
      library: 'fdr',
      context: ErrorDescription('while handling onDidRemovePage'),
    ),
  );
}
