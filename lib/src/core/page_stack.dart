part of 'core.dart';

typedef KeyedPage = (LocalKey key, DeclarativeNavigatablePage<Object?> page);

/// Keys a flattened page list so the Navigator pairs old and new pages by
/// identity instead of position: explicit keys win; a routed page is keyed by
/// [routeKey] of its route (`#n` for repeats); a page without a route by the
/// key of the routed page below it plus its offset.
List<KeyedPage> keyPages(
  List<DeclarativeNavigatablePage<Object?>> pages,
  String? Function(Object route) routeKey,
) {
  final seen = <String, int>{};
  final result = <KeyedPage>[];
  var below = '';
  var offset = 0;
  for (final page in pages) {
    final route = page.route;
    final base = route == null ? null : routeKey(route);
    final explicit = page.key;
    final String derived;
    if (explicit != null) {
      // pages above an explicitly keyed page (e.g. a shell) stay stable
      // while its route changes
      below = '$explicit';
      offset = 0;
      derived = below;
    } else if (base != null) {
      final n = seen.update(base, (c) => c + 1, ifAbsent: () => 0);
      below = n == 0 ? base : '$base#$n';
      offset = 0;
      derived = below;
    } else {
      offset++;
      derived = '$below~$offset';
    }
    result.add((page.key ?? ValueKey('fdr:$derived'), page));
  }
  return result;
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
  if (current().any((e) => e.$1 == removed.key)) {
    _reportPopMisuse(
      'onPop of page ${removed.key} ran but the state still builds the page; '
      'onPop must change the state so the page disappears.',
    );
  }
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
