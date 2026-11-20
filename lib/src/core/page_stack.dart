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
///
/// A page without `onPop` gets here only by a removal [_PageNavigatorState]
/// does not refuse (`removeRouteBelow`, a `pushReplacement` on it): it is
/// reported, and [showAgain] has to rebuild the Navigator from the pages the
/// state builds, which puts the page back.
void applyPopContract(
  Page<Object?> removed,
  List<KeyedPage> Function() current,
  VoidCallback showAgain,
) {
  final match = current().where((e) => e.$1 == removed.key).firstOrNull;
  if (match == null) return; // the state already removed it
  final onPop = match.$2.onPop;
  if (onPop == null) {
    _reportPopMisuse(
      'Page ${removed.key} was removed from its Navigator imperatively but '
      'has no onPop. Pages are removed by changing the state that builds '
      'them; the page is shown again.',
    );
    // not in the Navigator's locked history update, which this runs in
    scheduleMicrotask(showAgain);
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

/// The Navigator of a keyed page list. `Navigator.pop` and
/// `Navigator.removeRoute` of a page without `onPop` throw to their caller
/// and leave the page where it is.
///
/// `Navigator.pop` ignores `Page.canPop`, which only stops `maybePop` (the
/// back button, system back) and the back gestures. Refusing it later is not
/// possible: `onDidRemovePage` runs once the route is on its way out, and a
/// route that refuses in `didPop` makes `popUntil` loop forever.
///
/// Flutter's own gesture handlers pop the route after they moved it out
/// themselves (the end of a swipe or predictive back whose page lost `onPop`
/// on the way, a bottom sheet dragged down). A throw there leaves the route
/// off screen and the Navigator without input, so that pop is refused
/// without one and the route's transition runs forward again.
class _PageNavigator extends Navigator {
  const _PageNavigator({
    super.key,
    required super.pages,
    required super.onDidRemovePage,
    required this.current,
  });

  /// The pages the state builds now, which may be newer than [pages].
  final List<KeyedPage> Function() current;

  @override
  NavigatorState createState() => _PageNavigatorState();
}

class _PageNavigatorState extends NavigatorState {
  bool _inPopUntil = false;

  @override
  void popUntil(RoutePredicate predicate) {
    final outer = _inPopUntil;
    _inPopUntil = true;
    try {
      super.popUntil(predicate);
    } finally {
      _inPopUntil = outer;
    }
  }

  @override
  void pop<T extends Object?>([T? result]) {
    Route<Object?>? top;
    super.popUntil((route) {
      top = route;
      return true;
    });
    // with a local history entry (an open drawer) the pop closes that
    if (top case final top? when !top.willHandlePopInternally) {
      final page = _pageWithoutOnPop(top);
      if (page != null) {
        // popUntil pops until the route is gone, so it needs the throw
        if (!_inPopUntil && _showAgain(top, page)) return;
        throw _noOnPop(page, 'Navigator.pop');
      }
    }
    super.pop(result);
  }

  @override
  void removeRoute<T extends Object?>(Route<T> route, [T? result]) {
    final page = _pageWithoutOnPop(route);
    if (page != null) throw _noOnPop(page, 'Navigator.removeRoute');
    super.removeRoute(route, result);
  }

  /// The page of [route], if the state builds it without `onPop`.
  Page<Object?>? _pageWithoutOnPop(Route<Object?> route) {
    final page = route.settings;
    // a route pushed on top of the pages is the app's to pop
    if (page is! Page<Object?>) return null;
    final current = (widget as _PageNavigator).current();
    final match = current.where((e) => e.$1 == page.key).firstOrNull;
    // not in the list: the state already removed it, and the route is leaving
    if (match == null || match.$2.onPop != null) return null;
    return page;
  }

  /// Whether [route] was being moved out by a gesture, in which case it is
  /// brought back.
  bool _showAgain(Route<Object?> route, Page<Object?> page) {
    if (route is! TransitionRoute<Object?>) return false;
    // ignore: invalid_use_of_protected_member
    final controller = route.controller;
    if (controller == null) return false;
    if (userGestureInProgress) {
      // a back gesture starts only on a page with onPop, so the page lost it
      // on the way: no error. the handler may still animate the route after
      // this returns, so it comes back once the gesture is over
      final gesture = userGestureInProgressNotifier;
      void ended() {
        if (gesture.value) return;
        gesture.removeListener(ended);
        if (route.isActive) controller.forward();
      }

      gesture.addListener(ended);
      return true;
    }
    if (!controller.isDismissed &&
        controller.status != AnimationStatus.reverse) {
      return false;
    }
    // a bottom sheet that was dragged down: it should not be draggable
    controller.forward();
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: _noOnPop(
          page,
          'Navigator.pop',
          'The route was closing by itself (a bottom sheet dragged down) and '
              'is shown again; a page without onPop must not offer that '
              '(enableDrag: canPop).',
        ),
        library: 'fdr',
        context: ErrorDescription('while a route popped itself'),
      ),
    );
    return true;
  }

  FlutterError _noOnPop(Page<Object?> page, String call, [String? outcome]) =>
      FlutterError.fromParts([
        ErrorSummary(
          '$call was called on page ${page.key}, which has no onPop.',
        ),
        ErrorDescription(
          'A page is removed by changing the state that builds it. $call '
          'removes the page from the Navigator only, so the page has to say '
          'in onPop how the state changes. '
          '${outcome ?? 'The page stays as it is.'}',
        ),
        ErrorHint(
          'Pass onPop to the page and remove it from build() there, or change '
          'the state instead of calling $call.',
        ),
      ]);
}
