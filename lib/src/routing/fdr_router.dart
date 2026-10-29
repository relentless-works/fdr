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
    _host = NavHost<R>(scope, description: 'the router ($R)')
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
  /// and its URL replaces the initial one.
  @override
  Future<void> setInitialRoutePath(RouteSnapshot<R> configuration) {
    if (!_openedBeforeStart) return setNewRoutePath(configuration);
    _started = true;
    scope.requestHistory(HistoryAction.replace);
    notifyListeners();
    return SynchronousFuture(null);
  }

  @override
  Future<void> setRestoredRoutePath(RouteSnapshot<R> configuration) {
    return setNewRoutePath(configuration);
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
    } finally {
      _applying--;
    }
    // the platform delivered this route, so it already is the browser's
    // current entry: the next report corrects it in place (canonical form,
    // redirect) instead of adding one
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
    if (!_started) _openedBeforeStart = true;
    _applying++;
    try {
      _missing = null;
      _host.update(_entries(), incomingRoute: route);
    } finally {
      _applying--;
    }
    scope.requestHistory(history);
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
    return _ReassembleHook(child: _host.navigator(key: navigatorKey));
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
  const _ReassembleHook({required this.child});

  final Widget child;

  @override
  State<_ReassembleHook> createState() => _ReassembleHookState();
}

class _ReassembleHookState extends State<_ReassembleHook> {
  @override
  void reassemble() {
    super.reassemble();
    FdrHotReload.trigger();
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
  /// for a custom scheme (`myapp://orders/42`) the host is the first segment.
  static Uri appPath(Uri uri) {
    final custom =
        uri.hasScheme && uri.scheme != 'http' && uri.scheme != 'https';
    final path = custom && uri.host.isNotEmpty
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
    final url = Url.parse(normalize(routeInformation.uri));
    final (route, missing) = resolve(url);
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

  final List<RouteInformation> _entries = [];
  int _index = -1;
  int _serial = 0;

  // serials of the entries that pending traversals will deliver
  final List<int> _awaitedBacks = [];

  // the latest report made while a back was in flight, sent once it arrived
  _Report? _deferred;

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
      // didPushRouteInformation recognises and swallows
      _index -= steps;
      _awaitedBacks.add(_serialOf(_entries[_index]));
      browserHistory.go(-steps);
      return;
    }

    if (_awaitedBacks.isNotEmpty) {
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
    } else {
      final serial = _index >= 0 ? _serialOf(_entries[_index]) : ++_serial;
      final entry = _entry(
        _index < 0 ? 0 : _index,
        routeInformation.uri,
        serial,
        routeInformation.state,
      );
      super.routerReportsNewRouteInformation(
        entry,
        type: RouteInformationReportingType.neglect,
      );
      if (_index < 0) {
        _entries.add(entry);
        _index = 0;
      } else {
        _entries[_index] = entry;
      }
    }
  }

  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) {
    final state = routeInformation.state;
    final own = state is Map && state['fdr'] == 1 && state['s'] == _session;
    final serial = own ? state['i'] : null;

    if (_awaitedBacks.isNotEmpty) {
      if (serial == _awaitedBacks.first) {
        _awaitedBacks.removeAt(0);
        _moveTo(serial, routeInformation.uri);
        // the app popped in-app and already shows this entry; an entry of
        // an earlier one of several queued traversals is never shown
        if (_awaitedBacks.isEmpty) {
          final deferred = _deferred;
          _deferred = null;
          if (deferred != null) _report(deferred);
        }
        return SynchronousFuture(true);
      }
      // the user moved through the history on their own: the browser wins
      _awaitedBacks.clear();
      _deferred = null;
    }

    _restoredInitialState = null;
    if (own) {
      _moveTo(serial, routeInformation.uri);
      return super.didPushRouteInformation(
        RouteInformation(uri: routeInformation.uri, state: state['h']),
      );
    }
    // reload, typed URL, OS deep link or another session: start a new shadow
    _entries.clear();
    _index = -1;
    return super.didPushRouteInformation(
      RouteInformation(uri: routeInformation.uri),
    );
  }

  // moves to the entry the browser delivered; serials grow along the
  // history, so an entry not known yet (forward after a reload) is inserted
  // at its place
  void _moveTo(Object? serial, Uri uri) {
    if (serial is! num) return;
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
    final before = _entries.take(position).toList();
    final recorded = before.skip(
      before.length > _recordedPredecessors
          ? before.length - _recordedPredecessors
          : 0,
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
    if (restored == null || current.state != null) return current;
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
class FdrRouter<R extends NavRoute> {
  FdrRouter({
    required StatefulNavigator<R> root,
    required R Function(Url url) fromUrl,
    Widget Function(Url url) notFound = _defaultNotFound,
    BrowserHistory? browserHistory,
    HistoryAction popFallback = HistoryAction.push,
    RouteInformation? initialRouteInformation,
    @visibleForTesting int? sessionId,
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
       parser = FdrRouteInformationParser(fromUrl: fromUrl) {
    provider = FdrRouteInformationProvider(
      initialRouteInformation:
          initialRouteInformation ??
          RouteInformation(
            // also lets the router be created before runApp
            uri: Uri.parse(
              WidgetsFlutterBinding.ensureInitialized()
                  .platformDispatcher
                  .defaultRouteName,
            ),
          ),
      scope: delegate.scope,
      browserHistory: browserHistory ?? BrowserHistory.platform(),
      popFallback: popFallback,
      sessionId: sessionId,
    );
  }

  final FdrRouterDelegate<R> delegate;
  final FdrRouteInformationParser<R> parser;
  late final FdrRouteInformationProvider provider;

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
    provider.dispose();
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
