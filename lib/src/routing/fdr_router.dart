import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/core.dart';
import 'browser_history.dart';
import 'url.dart';

/// The Router configuration: the root route, or the URL that did not parse,
/// plus the non-URL state tree.
final class RouteSnapshot<R extends NavRoute> {
  const RouteSnapshot(this.route, {this.missing, this.historyState});

  /// The route to apply; for a URL that did not parse completely, the
  /// longest prefix that did. `null` if not even `/` parses.
  final R? route;

  /// The URL as typed, if it did not parse completely: shown with the
  /// not-found page on top of [route].
  final Url? missing;

  final Object? historyState;

  Url get url => missing ?? route!.toUrl();
}

class FdrRouterDelegate<R extends NavRoute>
    extends RouterDelegate<RouteSnapshot<R>>
    with ChangeNotifier {
  FdrRouterDelegate({
    required this.root,
    required this.fromUrl,
    required this.notFound,
  }) {
    scope
      ..stackChange = _stackChange
      ..openRoot = ((route, history) => _open(route as R, history))
      ..hrefOf = ((route) => (route as R).toUrl().toString());
    // assigned before the first update: an open() in a navigator's
    // initState or build runs at its end and needs _host
    _host = NavHost<R>(scope, description: 'the router ($R)');
    _host
      ..pages.addListener(_onPagesChanged)
      ..update(_entries());
    _reportedStack = _routedStack();
  }

  final StatefulNavigator<R> root;
  final R Function(Url url) fromUrl;
  final Widget Function(Url url) notFound;
  final RoutingScope scope = RoutingScope();

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  late final NavHost<R> _host;
  Url? _missing;
  R? _lastRoute;
  int _applying = 0;
  bool _started = false;
  bool _openedBeforeStart = false;

  // set by FdrRouter: the initial route is the platform's "/" (no deep
  // link), and the app asked to keep the navigators' state then
  bool _keepStateAtStart = false;

  List<LocalKey> _reportedStack = const [];

  List<NavEntry<Object?>> _entries() => [
    root,
    if (_missing case final url?)
      NavPage<Object?>(route: url, onPop: _closeNotFound, child: notFound(url)),
  ];

  void _closeNotFound() {
    _missing = null;
    _host.update(_entries());
  }

  void _onPagesChanged() {
    if (_applying == 0) notifyListeners();
  }

  static String _print(Object route) => switch (route) {
    Url() => route.toString(),
    _ => (route as NavRoute).toUrl().toString(),
  };

  /// Printed URL of the current state (null while no page has a route).
  String? get currentUrl {
    final top = _host.route;
    return top == null ? null : _print(top);
  }

  @override
  RouteSnapshot<R>? get currentConfiguration {
    final top = _host.route;
    if (top is Url) {
      return RouteSnapshot(
        null,
        missing: top,
        historyState: _host.historyState,
      );
    }
    final derived = top as R?;
    if (derived != null) {
      _lastRoute = derived;
      assert(_debugCheckRoundTrip(derived));
    }
    final route = derived ?? _lastRoute;
    if (route == null) return null;
    return RouteSnapshot(route, historyState: _host.historyState);
  }

  String? _checked;

  // a URL the app prints has to lead back to the same URL, or links,
  // reloads and shared URLs end up elsewhere
  bool _debugCheckRoundTrip(R route) {
    final printed = route.toUrl().toString();
    if (printed == _checked) return true;
    _checked = printed;
    String outcome;
    try {
      final again = fromUrl(Url.parse(Uri.parse(printed))).toUrl().toString();
      if (again == printed) return true;
      outcome = 'parses to a route that prints $again';
    } on Object catch (error) {
      outcome = 'does not parse ($error)';
    }
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: FlutterError.fromParts([
          ErrorSummary('${route.runtimeType} prints $printed, which $outcome.'),
          ErrorHint(
            'toUrl and fromUrl have to agree: links, reloads and shared URLs '
            'use what toUrl prints.',
          ),
        ]),
        library: 'fdr',
      ),
    );
    return true;
  }

  @override
  Future<void> setNewRoutePath(RouteSnapshot<R> configuration) {
    _started = true;
    _apply(configuration);
    return SynchronousFuture(null);
  }

  /// The platform's initial route, unless the app opened a route before it
  /// arrived (e.g. from the notification that launched it): that one wins,
  /// and its URL replaces the initial one. The same for the state the
  /// navigators start with, if there is no deep link and the app asked for
  /// it (`FdrRouter.keepStateWithoutDeepLink`).
  ///
  /// A Router mounted again for this delegate applies nothing: what the
  /// provider holds is the last report, and the navigators' state is newer.
  @override
  Future<void> setInitialRoutePath(RouteSnapshot<R> configuration) {
    if (_started) {
      notifyListeners();
      return SynchronousFuture(null);
    }
    final keepState = _keepStateAtStart && currentUrl != null;
    if (!_openedBeforeStart && !keepState) {
      return setNewRoutePath(configuration);
    }
    return _keepOpened();
  }

  /// The route restored after process death; at start, a route the app
  /// opened before wins over it too.
  @override
  Future<void> setRestoredRoutePath(RouteSnapshot<R> configuration) {
    if (_started || !_openedBeforeStart) return setNewRoutePath(configuration);
    return _keepOpened();
  }

  Future<void> _keepOpened() {
    _started = true;
    scope.requestHistory(HistoryAction.replace);
    notifyListeners();
    return SynchronousFuture(null);
  }

  /// URL -> state, top-down. Idempotent: an incoming route whose URL equals
  /// the current one touches no navigator state (only the history state is
  /// restored, for browser back/forward).
  void _apply(RouteSnapshot<R> snapshot) {
    _applying++;
    try {
      if (snapshot.url.toString() != currentUrl) {
        _missing = snapshot.missing;
        _host.update(_entries(), incomingRoute: snapshot.route);
      }
      if (snapshot.historyState != null) {
        _host
          ..restoreHistoryState(snapshot.historyState)
          // rebuild so pages pick up the restored non-URL state
          ..update(_entries());
      }
    } on Object catch (error, stack) {
      // an applyRoute or build threw: the navigators stay at their last
      // good pages, and the report below puts the URL of what they show in
      // place of this one. Reported, not thrown: nothing in the app called
      // this.
      _missing = switch (_host.route) {
        final Url url => url,
        _ => null,
      };
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'fdr',
          context: ErrorDescription('while applying ${snapshot.url}'),
        ),
      );
    } finally {
      _applying--;
    }
    // the platform delivered this route, so it already is the browser's
    // current entry: the next report corrects it in place (canonical form,
    // redirect, failed apply) instead of adding one
    scope.requestHistory(HistoryAction.replace);
    notifyListeners();
  }

  /// Navigates to [route] like a link: from a push notification handler, a
  /// widget outside the pages, a test. By default, the history action
  /// follows from how the page stack changes (push, or a back for pops).
  void open(R route, {HistoryAction history = HistoryAction.auto}) {
    scope.open(route, history);
  }

  void _open(R route, HistoryAction history) {
    // a redirect (an open() during an update, e.g. in initState) is not a
    // route the app opened: the platform's initial route still applies
    if (!_started && !scope.redirecting) _openedBeforeStart = true;
    // a redirect from applying another route (an open() in applyRoute):
    // its replace is meant for that route, which was never reported, so
    // the history action of the navigation in progress stands
    final nested = _applying > 0;
    _applying++;
    try {
      // a redirect of the nearest page of a URL that does not parse keeps
      // the not-found page and the URL as typed
      if (!nested) _missing = null;
      _host.update(_entries(), incomingRoute: route);
    } finally {
      _applying--;
    }
    if (!nested || history != HistoryAction.replace) {
      scope.requestHistory(history);
    }
    notifyListeners();
  }

  List<LocalKey> _routedStack() => _routedKeys(_host.keyed());

  // routed page keys, looking into the active tab of tabs pages
  static List<LocalKey> _routedKeys(List<KeyedPage> pages) => [
    for (final (key, page) in pages)
      if (page.nestedPages case final nested?)
        ..._routedKeys(nested())
      else if (page.route != null)
        key,
  ];

  // pages only removed from the top is a pop, pages only added on top a push
  HistoryAction _stackChange() {
    final before = _reportedStack;
    final now = _routedStack();
    _reportedStack = now;
    if (now.length < before.length &&
        listEquals(now, before.sublist(0, now.length))) {
      scope.popDepth = before.length - now.length;
      return HistoryAction.pop;
    }
    if (now.length > before.length &&
        listEquals(before, now.sublist(0, before.length))) {
      return HistoryAction.push;
    }
    return HistoryAction.auto;
  }

  @override
  Widget build(BuildContext context) {
    return _ReassembleHook(
      onReassemble: () => _host.reassemble(_entries),
      child: _host.navigator(key: navigatorKey),
    );
  }

  /// Android back: `maybePop` honours `Page.canPop` and any `PopScope`; on
  /// the bottom page it bubbles, so the app is left.
  @override
  Future<bool> popRoute() {
    return navigatorKey.currentState?.maybePop() ?? SynchronousFuture(false);
  }

  @override
  void dispose() {
    _host
      ..pages.removeListener(_onPagesChanged)
      ..dispose();
    super.dispose();
  }
}

class _ReassembleHook extends StatefulWidget {
  const _ReassembleHook({required this.onReassemble, required this.child});

  final VoidCallback onReassemble;
  final Widget child;

  @override
  State<_ReassembleHook> createState() => _ReassembleHookState();
}

class _ReassembleHookState extends State<_ReassembleHook> {
  @override
  void reassemble() {
    super.reassemble();
    widget.onReassemble();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class FdrRouteInformationParser<R extends NavRoute>
    extends RouteInformationParser<RouteSnapshot<R>> {
  FdrRouteInformationParser({required this.fromUrl, this.normalize = appPath});

  final R Function(Url url) fromUrl;

  /// Maps an incoming URI (web path, OS deep link) to the routed path+query.
  final Uri Function(Uri uri) normalize;

  /// Path and query of an incoming URI. OS deep links carry scheme and host;
  /// for a custom scheme (`myapp://orders/42`) the host is the first segment
  /// (lowercased, like every host), and so is the host of a URI without a
  /// scheme: a path that starts with two slashes (`//orders/42`), which a
  /// browser sends as typed. A web link whose route is in the
  /// fragment (hash URL strategy, `https://shop.example/#/orders/42`) is
  /// routed by the fragment.
  static Uri appPath(Uri uri) {
    if ((uri.scheme == 'http' || uri.scheme == 'https') &&
        (uri.path.isEmpty || uri.path == '/') &&
        uri.fragment.startsWith('/')) {
      // a fragment that is no URI (`#//a:b`) is no route
      final route = Uri.tryParse(uri.fragment);
      if (route != null) return appPath(route);
    }
    final web = uri.scheme == 'http' || uri.scheme == 'https';
    final path = !web && uri.host.isNotEmpty
        ? '/${uri.host}${uri.path}'
        : uri.path;
    return Uri(
      path: path.isEmpty ? '/' : path,
      query: uri.hasQuery ? uri.query : null,
    );
  }

  /// The route for [url], or, if a level throws [NotFound], for the longest
  /// prefix of [url] that parses: the same path without the query first,
  /// then one segment less at a time. [url] is then returned as missing too.
  /// Any other error is a bug in a `fromUrl`; it is reported and handled
  /// like a URL that does not parse at all.
  (R?, Url?) resolve(Url url) {
    var attempt = url;
    while (true) {
      try {
        return (fromUrl(attempt), identical(attempt, url) ? null : url);
      } on NotFound {
        final segments = attempt.segments;
        if (attempt.query.isNotEmpty) {
          attempt = Url(segments);
        } else if (segments.isEmpty) {
          return (null, url);
        } else {
          attempt = Url(segments.sublist(0, segments.length - 1));
        }
      } on Object catch (error, stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'fdr',
            context: ErrorDescription('while parsing $attempt'),
          ),
        );
        return (null, url);
      }
    }
  }

  @override
  Future<RouteSnapshot<R>> parseRouteInformation(
    RouteInformation routeInformation,
  ) {
    final R? route;
    final Url? missing;
    try {
      (route, missing) = resolve(Url.parse(normalize(routeInformation.uri)));
    } on Object catch (error, stack) {
      // a bug in the app's `rewriteUri`: handled like one in a `fromUrl`
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'fdr',
          context: ErrorDescription('while rewriting ${routeInformation.uri}'),
        ),
      );
      return SynchronousFuture(
        RouteSnapshot(
          null,
          missing: Url.parse(routeInformation.uri),
          historyState: routeInformation.state,
        ),
      );
    }
    return SynchronousFuture(
      RouteSnapshot(
        route,
        missing: missing,
        historyState: routeInformation.state,
      ),
    );
  }

  @override
  RouteInformation? restoreRouteInformation(RouteSnapshot<R> configuration) {
    return RouteInformation(
      uri: configuration.url.toUri(),
      state: configuration.historyState,
    );
  }
}

typedef _Report = (
  RouteInformation info,
  RouteInformationReportingType type,
  HistoryAction action,
);

/// Reports to the engine with the history action of the state change and
/// keeps a shadow of the browser entries this session created, so an in-app
/// pop can become a real browser back (`history.go(-n)`).
class FdrRouteInformationProvider extends PlatformRouteInformationProvider {
  FdrRouteInformationProvider({
    required super.initialRouteInformation,
    required this.scope,
    this.browserHistory = const NoBrowserHistory(),
    this.popFallback = HistoryAction.push,
    int? sessionId,
  }) : _session = sessionId ?? DateTime.now().microsecondsSinceEpoch {
    _adoptEntryAfterReload();
  }

  final RoutingScope scope;
  final BrowserHistory browserHistory;

  /// What an in-app pop does when it cannot be a browser back (not on the
  /// web, or no previous entry has the new URL): [HistoryAction.push]
  /// like Flutter's default, or [HistoryAction.replace].
  final HistoryAction popFallback;

  int _session;

  // entries before an entry that are recorded in its state, so that the
  // history this session knows about survives a reload
  static const _recordedPredecessors = 32;

  // entries kept before the current one: more than a reload restores, and
  // more than a pop goes back
  static const _keptPredecessors = 64;

  final List<RouteInformation> _entries = [];
  int _index = -1;
  int _serial = 0;

  // URL and state last written to the browser, which are those of its
  // current entry until it moves: a report with the same is not sent again
  // (WebKit limits how often an entry may be written)
  String? _written;

  static String? _encoded(RouteInformation entry) {
    try {
      return jsonEncode([entry.uri.toString(), entry.state]);
    } on Object {
      return null;
    }
  }

  // the entries that pending traversals will deliver, by serial, and how
  // far each traversal goes
  final List<(int serial, int delta)> _awaitedBacks = [];

  // the latest report made while a back was in flight, sent once it arrived
  _Report? _deferred;

  /// How long the browser may take to deliver a traversal before it counts
  /// as lost (it takes a frame or two). Settable for tests, in which
  /// settling a page transition takes that long.
  Duration backTimeout = const Duration(seconds: 1);
  Timer? _backTimer;

  // the latest report that became a traversal: reported if that gets lost
  _Report? _traversing;

  // A traversal given up as lost, which the browser may only be late with:
  // for another [backTimeout], the entry it delivers is still recognised.
  // That is the entry asked for, or, in a browser that applies the delta
  // when it carries the traversal out, the entry that far from the current
  // one. A traversal by the user to one of these is taken for it.
  (int serial, int delta)? _abandoned;
  Timer? _abandonTimer;

  /// The browser entries created in this session (URL strings), for tests.
  List<String> get shadowHistory =>
      _entries.map((e) => e.uri.toString()).toList();
  int get shadowIndex => _index;
  int get pendingBacks => _awaitedBacks.length;

  @override
  void routerReportsNewRouteInformation(
    RouteInformation routeInformation, {
    RouteInformationReportingType type = RouteInformationReportingType.none,
  }) {
    _report((routeInformation, type, scope.takeRequested()));
  }

  // how many entries back the new URL is, if a pop of [depth] pages may
  // traverse there: the nearest previous entry within depth with that URL
  int? _stepsBackTo(String url, int depth) {
    if (!browserHistory.supportsTraversal) return null;
    for (var k = 1; k <= depth && _index - k >= 0; k++) {
      if (_entries[_index - k].uri.toString() == url) return k;
    }
    return null;
  }

  void _report(_Report report) {
    final (routeInformation, type, action) = report;
    final url = routeInformation.uri.toString();

    final steps = action == HistoryAction.pop
        ? _stepsBackTo(url, scope.popDepth)
        : null;
    if (steps != null) {
      // the engine delivers that entry as pushRouteInformation, which
      // didPushRouteInformation recognises and swallows. What was deferred
      // during an earlier traversal describes a state the app has left: the
      // state now is that entry's.
      _deferred = null;
      _index -= steps;
      _awaitedBacks.add((_serialOf(_entries[_index]), -steps));
      _traversing = report;
      _awaitBacks();
      browserHistory.go(-steps);
      return;
    }

    if (_awaitedBacks.isNotEmpty) {
      // a pop back to the entry the traversal leads to: together, the
      // deferred changes add no entry (a page was opened and closed again)
      if (action == HistoryAction.pop &&
          url == _entries[_index].uri.toString()) {
        _deferred = (
          routeInformation,
          RouteInformationReportingType.neglect,
          HistoryAction.replace,
        );
        return;
      }
      final previous = _deferred;
      final pushes =
          action == HistoryAction.push ||
          type == RouteInformationReportingType.navigate ||
          (previous != null && previous.$3 == HistoryAction.push);
      _deferred = (
        routeInformation,
        type,
        pushes ? HistoryAction.push : action,
      );
      return;
    }

    // the first report always replaces the entry the engine started with
    // (`_valueInEngine` is the initial URL), also after canonicalisation
    final first = _index < 0;
    final urlChanged = !first && _entries[_index].uri.toString() != url;
    final effective = action == HistoryAction.pop ? popFallback : action;
    final push =
        !first &&
        switch (effective) {
          HistoryAction.push => true,
          HistoryAction.replace || HistoryAction.pop => false,
          HistoryAction.auto => switch (type) {
            RouteInformationReportingType.navigate => true,
            RouteInformationReportingType.neglect => false,
            RouteInformationReportingType.none => urlChanged,
          },
        };

    if (push) {
      if (_index >= 0) {
        // refresh the entry being left with the latest non-URL state
        final leaving = _entry(
          _index,
          _entries[_index].uri,
          _serialOf(_entries[_index]),
          routeInformation.state,
        );
        super.routerReportsNewRouteInformation(
          leaving,
          type: RouteInformationReportingType.neglect,
        );
        _entries[_index] = leaving;
      }
      _serial += 1;
      final entry = _entry(
        _index + 1,
        routeInformation.uri,
        _serial,
        routeInformation.state,
      );
      super.routerReportsNewRouteInformation(
        entry,
        type: RouteInformationReportingType.navigate,
      );
      _entries
        ..removeRange(_index + 1, _entries.length)
        ..add(entry);
      _index = _entries.length - 1;
      _written = _encoded(entry);
      // a long session does not keep every entry; one the browser goes
      // back to later is inserted again, as after a reload
      if (_index > _keptPredecessors) {
        _entries.removeRange(0, _index - _keptPredecessors);
        _index = _keptPredecessors;
      }
    } else {
      final serial = _index >= 0 ? _serialOf(_entries[_index]) : ++_serial;
      final entry = _entry(
        _index < 0 ? 0 : _index,
        routeInformation.uri,
        serial,
        routeInformation.state,
      );
      // a rebuild that changed neither URL nor state; the state includes
      // the serial, so this is the entry that was written
      final encoded = _encoded(entry);
      if (_index >= 0 && encoded != null && encoded == _written) return;
      super.routerReportsNewRouteInformation(
        entry,
        type: RouteInformationReportingType.neglect,
      );
      _written = encoded;
      if (_index < 0) {
        _entries.add(entry);
        _index = 0;
      } else {
        _entries[_index] = entry;
      }
    }
  }

  void _awaitBacks() {
    _backTimer?.cancel();
    _backTimer = Timer(backTimeout, _onBacksLost);
  }

  void _backsDone() {
    _backTimer?.cancel();
    _backTimer = null;
    _awaitedBacks.clear();
    _traversing = null;
  }

  // The browser did not deliver a traversal: `history.go` does nothing if
  // the entry does not exist, which happens once the shadow and the real
  // history disagree. Reporting must not wait for it forever. The shadow
  // continues at the entry the browser is on, if it knows that one, and
  // the app's URL is reported there without another traversal. The browser
  // may still carry the traversal out after that: see [_abandoned].
  void _onBacksLost() {
    final (info, type, action) = _deferred ?? _traversing!;
    final given = _awaitedBacks.first;
    _deferred = null;
    _backsDone();
    final state = browserHistory.currentState;
    final own = state is Map && state['fdr'] == 1 && state['s'] == _session;
    final serial = own ? state['i'] : null;
    _index = serial is num
        ? _entries.indexWhere((e) => _serialOf(e) == serial)
        : -1;
    if (_index < 0) _entries.clear();
    // the traversal may have happened and only its delivery got lost
    final known = _index >= 0;
    final arrived = known && _entries[_index].uri == info.uri;
    _report((
      info,
      type,
      action != HistoryAction.pop
          ? action
          : arrived
          ? HistoryAction.replace
          : popFallback,
    ));
    _forgetAbandoned();
    if (known && !arrived) {
      _abandoned = given;
      _abandonTimer = Timer(backTimeout, _forgetAbandoned);
    }
  }

  void _forgetAbandoned() {
    _abandonTimer?.cancel();
    _abandonTimer = null;
    _abandoned = null;
  }

  // whether the entry delivered is the one of the traversal given up
  bool _isLate(Object? serial) {
    final abandoned = _abandoned;
    if (abandoned == null || serial is! num || _index < 0) return false;
    final (asked, delta) = abandoned;
    if (serial == asked) return true;
    // the browser's position is not known while it has more to carry out
    if (_awaitedBacks.isNotEmpty) return false;
    final at = _index + delta;
    return at >= 0 && at < _entries.length && _serialOf(_entries[at]) == serial;
  }

  // The browser carried out a traversal that was given up. The app has
  // reported the state it is in since, into an entry of its own: it keeps
  // that state, and the browser goes back to that entry.
  void _undoLate(num serial, Uri uri) {
    _forgetAbandoned();
    // the app asked for another traversal since, which follows this one
    if (_awaitedBacks.isNotEmpty) return;
    final shown = _entries[_index];
    _moveTo(serial, uri);
    final delta = _entries.indexOf(shown) - _index;
    if (delta == 0) return;
    _index += delta;
    _awaitedBacks.add((_serialOf(shown), delta));
    // if this one gets lost, the app's state is written where the browser is
    _traversing = (
      RouteInformation(uri: shown.uri, state: (shown.state! as Map)['h']),
      RouteInformationReportingType.neglect,
      HistoryAction.replace,
    );
    _awaitBacks();
    browserHistory.go(delta);
  }

  // nothing is delivered or reported while no Router listens
  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (_awaitedBacks.isNotEmpty && _backTimer == null) _awaitBacks();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _backTimer?.cancel();
      _backTimer = null;
      _forgetAbandoned();
    }
  }

  @override
  void dispose() {
    _backTimer?.cancel();
    _abandonTimer?.cancel();
    super.dispose();
  }

  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) {
    final state = routeInformation.state;
    final own = state is Map && state['fdr'] == 1 && state['s'] == _session;
    final serial = own ? state['i'] : null;

    if (_isLate(serial)) {
      _undoLate(serial as num, routeInformation.uri);
      return SynchronousFuture(true);
    }
    // the browser carries traversals out in the order they were asked for
    _forgetAbandoned();

    final awaiting = _awaitedBacks.isNotEmpty;
    if (awaiting) {
      if (serial == _awaitedBacks.first.$1) {
        _awaitedBacks.removeAt(0);
        _moveTo(serial, routeInformation.uri);
        // the app popped in-app and already shows this entry; an entry of
        // an earlier one of several queued traversals is never shown
        if (_awaitedBacks.isEmpty) {
          final deferred = _deferred;
          _deferred = null;
          _backsDone();
          if (deferred != null) _report(deferred);
        }
        return SynchronousFuture(true);
      }
      // the user moved through the history on their own: the browser wins
      _backsDone();
      _deferred = null;
    }

    _restoredInitialState = null;
    if (own) {
      _moveTo(serial, routeInformation.uri);
      return super.didPushRouteInformation(
        RouteInformation(
          uri: routeInformation.uri,
          // an entry without non-URL state is restored too: its navigators
          // had their defaults then (a foreign entry has nothing to restore)
          state: state['h'] ?? const <String, Object?>{},
        ),
      );
    }
    if (state == null &&
        browserHistory.supportsTraversal &&
        _index >= 0 &&
        !awaiting) {
      // a hash typed into the address bar while the app runs is a new
      // entry after the current one. The entries before it stay, for later
      // in-app pops; the report that follows writes this entry's state.
      _entries
        ..removeRange(_index + 1, _entries.length)
        ..add(_known(++_serial, routeInformation.uri));
      _index = _entries.length - 1;
    } else {
      // an OS deep link, another session's entry, or a position that is
      // not known (a traversal was pending): start a new shadow
      _entries.clear();
      _index = -1;
    }
    return super.didPushRouteInformation(
      RouteInformation(uri: routeInformation.uri),
    );
  }

  // moves to the entry the browser delivered; serials grow along the
  // history, so an entry not known yet (forward after a reload) is inserted
  // at its place
  void _moveTo(Object? serial, Uri uri) {
    if (serial is! num) return;
    // a serial learned from the browser is not handed out again
    if (serial > _serial) _serial = serial.toInt();
    final i = _entries.indexWhere((e) => _serialOf(e) == serial);
    if (i >= 0) {
      _index = i;
      return;
    }
    final at = _entries.indexWhere((e) => _serialOf(e) > serial);
    final position = at < 0 ? _entries.length : at;
    _entries.insert(position, _known(serial.toInt(), uri));
    _index = position;
  }

  RouteInformation _known(int serial, Uri uri) =>
      RouteInformation(uri: uri, state: {'fdr': 1, 's': _session, 'i': serial});

  RouteInformation _entry(
    int position,
    Uri uri,
    int serial,
    Object? historyState,
  ) {
    final recorded = _entries.getRange(
      position > _recordedPredecessors ? position - _recordedPredecessors : 0,
      position,
    );
    return RouteInformation(
      uri: uri,
      state: {
        'fdr': 1,
        's': _session,
        'i': serial,
        'h': historyState,
        'b': [
          for (final e in recorded) [_serialOf(e), e.uri.toString()],
        ],
      },
    );
  }

  /// After a reload the engine starts with the path only. If the current
  /// browser entry was written by this app, continue its session: its
  /// non-URL state is applied with the initial route, and the recorded
  /// earlier entries let an in-app pop still go back in the browser history.
  void _adoptEntryAfterReload() {
    final state = browserHistory.currentState;
    if (state is! Map || state['fdr'] != 1) return;
    final session = state['s'];
    final serial = state['i'];
    if (session is! num || serial is! num) return;
    final initial = value;
    _session = session.toInt();
    _entries
      ..clear()
      ..addAll([
        for (final recorded in (state['b'] as List?) ?? const [])
          if (recorded case [final num s, final String url])
            _known(s.toInt(), Uri.parse(url)),
        _known(serial.toInt(), initial.uri),
      ]);
    _index = _entries.length - 1;
    _serial = _entries.map(_serialOf).reduce((a, b) => a > b ? a : b);
    _restoredInitialState = state['h'];
  }

  Object? _restoredInitialState;

  @override
  RouteInformation get value {
    final restored = _restoredInitialState;
    final current = super.value;
    final state = current.state;
    // the last report is an entry of this provider: a Router reading it
    // gets the non-URL state, as with an entry the browser delivers
    if (state is Map && state['fdr'] == 1) {
      return RouteInformation(uri: current.uri, state: state['h']);
    }
    if (restored == null || state != null) return current;
    return RouteInformation(uri: current.uri, state: restored);
  }

  static int _serialOf(RouteInformation entry) {
    return ((entry.state! as Map)['i']! as num).toInt();
  }
}

/// Bundles delegate, parser and provider for `MaterialApp.router`.
///
/// ```dart
/// final router = FdrRouter(root: ShopNavigator(), fromUrl: ShopRoute.fromUrl);
/// void main() => runApp(MaterialApp.router(routerConfig: router.config));
/// ```
///
/// [notFound] builds the page shown on top of the nearest existing page when
/// a URL does not parse completely (see [NotFound]).
///
/// [keepStateWithoutDeepLink]: on a start without a deep link, the platform's
/// initial route is `/`, which is applied like any route by default. With
/// `true`, it is not: the navigators keep the state they were created with
/// (e.g. from a hydrated store), and the URL follows from it. Not on the web,
/// where `/` is a URL the user opened.
///
/// [rewriteUri] rewrites each incoming URI (an OS deep link, a web path)
/// before it is routed, e.g. to drop a host that is not part of the route
/// (`myapp://shop.example/orders/42`) or the path prefix of universal links.
/// What it returns is then reduced to path and query by the rules of the
/// default: a host is the first segment unless the scheme is http(s).
/// An error it throws is reported, and the link shows the not-found page.
class FdrRouter<R extends NavRoute> {
  FdrRouter({
    required StatefulNavigator<R> root,
    required R Function(Url url) fromUrl,
    Widget Function(Url url) notFound = _defaultNotFound,
    this._browserHistory,
    this._popFallback = HistoryAction.push,
    this._initialRouteInformation,
    this._keepStateWithoutDeepLink = false,
    Uri Function(Uri uri)? rewriteUri,
    @visibleForTesting this._sessionId,
  }) : assert(
         // Dart infers R as a common supertype when root and fromUrl
         // disagree; routes of the other type would reach the root
         debugNavigatorTakes<R>(root),
         'The root ${root.runtimeType} does not take every $R that fromUrl '
         'returns: fromUrl has to return the root\'s route type.',
       ),
       delegate = FdrRouterDelegate(
         root: root,
         fromUrl: fromUrl,
         notFound: notFound,
       ),
       parser = FdrRouteInformationParser(
         fromUrl: fromUrl,
         normalize: rewriteUri == null
             ? FdrRouteInformationParser.appPath
             : (uri) => FdrRouteInformationParser.appPath(rewriteUri(uri)),
       );

  final FdrRouterDelegate<R> delegate;
  final FdrRouteInformationParser<R> parser;

  final RouteInformation? _initialRouteInformation;
  final BrowserHistory? _browserHistory;
  final HistoryAction _popFallback;
  final bool _keepStateWithoutDeepLink;
  final int? _sessionId;

  /// Created on first use, usually by [config] when the app starts. Flutter's
  /// provider needs the widgets binding, and creating the router must not
  /// install one: the app or a test may install its own after it (a test
  /// binding, integration_test).
  FdrRouteInformationProvider get provider => _provider ??= _createProvider();
  FdrRouteInformationProvider? _provider;

  FdrRouteInformationProvider _createProvider() {
    final platformRoute = _initialRouteInformation == null
        // also before runApp
        ? WidgetsFlutterBinding.ensureInitialized()
              .platformDispatcher
              .defaultRouteName
        : null;
    // "/" is what the platform starts with when no route was requested
    delegate._keepStateAtStart =
        _keepStateWithoutDeepLink &&
        !kIsWeb &&
        platformRoute == Navigator.defaultRouteName;
    return FdrRouteInformationProvider(
      initialRouteInformation:
          _initialRouteInformation ??
          RouteInformation(uri: Uri.parse(platformRoute!)),
      scope: delegate.scope,
      browserHistory: _browserHistory ?? BrowserHistory.platform(),
      popFallback: _popFallback,
      sessionId: _sessionId,
    );
  }

  RouterConfig<RouteSnapshot<R>> get config => RouterConfig(
    routeInformationProvider: provider,
    routeInformationParser: parser,
    routerDelegate: delegate,
    backButtonDispatcher: RootBackButtonDispatcher(),
  );

  /// Navigates to [route] like a link, e.g. from a push notification.
  void open(R route, {HistoryAction history = HistoryAction.auto}) {
    delegate.open(route, history: history);
  }

  /// The URL of the current state.
  String? get currentUrl => delegate.currentUrl;

  /// Disposes the navigator states (and with them their subscriptions);
  /// for a router that is not created once for the app's lifetime.
  void dispose() {
    delegate.dispose();
    _provider?.dispose();
  }

  static Widget _defaultNotFound(Url url) => _NotFoundPage(url: url);
}

class _NotFoundPage extends StatelessWidget {
  const _NotFoundPage({required this.url});

  final Url url;

  @override
  Widget build(BuildContext context) => Material(
    child: SafeArea(child: Center(child: Text('No page at $url'))),
  );
}
