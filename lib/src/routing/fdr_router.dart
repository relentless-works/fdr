import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/core.dart';
import 'browser_history.dart';
import 'url_codec.dart';

/// The Router configuration: the root route plus the non-URL state tree.
final class RouteSnapshot<R extends Object> {
  const RouteSnapshot(this.route, {this.historyState});

  final R route;
  final Object? historyState;
}

class FdrRouterDelegate<R extends Object>
    extends RouterDelegate<RouteSnapshot<R>>
    with ChangeNotifier {
  FdrRouterDelegate({required this.root, required this.codec, this.pageKey}) {
    scope.stackChange = _stackChange;
    _mapper = NavigatableToPageMapper(scope)
      ..pages.addListener(_onPagesChanged)
      ..updatePages([_rootMount(root)]);
    _reportedStack = _routedStack();
  }

  final StatefulNavigator<R> root;
  final UrlCodec<R> codec;
  final RoutingScope scope = RoutingScope();

  /// Identity of a routed page for the Navigator's diffing. Defaults to the
  /// printed path without the query: `/orders?page=2` -> `?page=3` updates
  /// the list page in place, `/orders/42` -> `/orders/43` is a new page.
  final String Function(R route)? pageKey;

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  late final NavigatableToPageMapper _mapper;
  R? _lastRoute;
  bool _applying = false;
  List<LocalKey> _reportedStack = const [];

  // the root is mounted with the identity embedding
  static MountedNavigatable<R, R> _rootMount<R>(StatefulNavigator<R> root) {
    return MountedNavigatable<R, R>(root, embed: (r) => r, unwrap: (r) => r);
  }

  void _onPagesChanged() {
    if (!_applying) notifyListeners();
  }

  /// Printed URL of the current state (null while no page has a route).
  String? get currentUrl {
    final r = _mapper.route as R?;
    return r == null ? null : codec.encode(r).toString();
  }

  @override
  RouteSnapshot<R>? get currentConfiguration {
    final derived = _mapper.route as R?;
    if (derived != null) _lastRoute = derived;
    final route = derived ?? _lastRoute;
    if (route == null) return null;
    return RouteSnapshot(route, historyState: _mapper.historyState);
  }

  @override
  Future<void> setNewRoutePath(RouteSnapshot<R> configuration) {
    _apply(configuration);
    return SynchronousFuture(null);
  }

  @override
  Future<void> setRestoredRoutePath(RouteSnapshot<R> configuration) {
    return setNewRoutePath(configuration);
  }

  /// URL -> state, top-down. Idempotent: an incoming route whose URL equals
  /// the derived one touches no navigator state (only the history state is
  /// restored, for browser back/forward).
  void _apply(RouteSnapshot<R> snapshot) {
    final incomingUrl = codec.encode(snapshot.route).toString();
    _applying = true;
    try {
      if (incomingUrl != currentUrl) {
        _mapper.updatePages([_rootMount(root)], incomingRoute: snapshot.route);
      }
      if (snapshot.historyState != null) {
        _mapper
          ..restoreHistoryState(snapshot.historyState)
          // rebuild so pages pick up the restored non-URL state
          ..updatePages([_rootMount(root)]);
      }
    } finally {
      _applying = false;
    }
    // the platform delivered this route, so it already is the browser's
    // current entry: the next report corrects it in place (canonical form,
    // redirect) instead of adding one
    scope.requestHistory(HistoryAction.replace);
    notifyListeners();
  }

  String? _routeKey(Object route) {
    final custom = pageKey;
    if (custom != null) return custom(route as R);
    return codec.encode(route as R).path;
  }

  List<KeyedPage> _keyed() => keyPages(_mapper.pages.value, _routeKey);

  List<LocalKey> _routedStack() => [
    for (final (key, page) in _keyed())
      if (page.route != null) key,
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
      child: ValueListenableBuilder(
        valueListenable: _mapper.pages,
        builder: (context, pages, _) {
          return Navigator(
            key: navigatorKey,
            pages: [
              for (final (i, (key, page)) in keyPages(pages, _routeKey).indexed)
                page.buildPage(defaultKey: key, forceCanPop: i == 0),
            ],
            onDidRemovePage: (page) => applyPopContract(page, _keyed),
          );
        },
      ),
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
    _mapper
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

class FdrRouteInformationParser<R extends Object>
    extends RouteInformationParser<RouteSnapshot<R>> {
  FdrRouteInformationParser({
    required this.codec,
    required this.notFound,
    this.normalize = appPath,
  });

  final UrlCodec<R> codec;

  /// Typed fallback for URLs the codec rejects (no match or invalid value).
  final R Function(Uri uri) notFound;

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

  @override
  Future<RouteSnapshot<R>> parseRouteInformation(
    RouteInformation routeInformation,
  ) {
    final uri = normalize(routeInformation.uri);
    final route = codec.decode(uri) ?? notFound(uri);
    return SynchronousFuture(
      RouteSnapshot(route, historyState: routeInformation.state),
    );
  }

  @override
  RouteInformation? restoreRouteInformation(RouteSnapshot<R> configuration) {
    return RouteInformation(
      uri: codec.encode(configuration.route),
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
  }) : _session = sessionId ?? DateTime.now().microsecondsSinceEpoch;

  final RoutingScope scope;
  final BrowserHistory browserHistory;

  /// What an in-app pop does when it cannot be a browser back (not on the
  /// web, or no previous entry has the new URL): [HistoryAction.push]
  /// like Flutter's default, or [HistoryAction.replace].
  final HistoryAction popFallback;

  final int _session;

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
        final leaving = RouteInformation(
          uri: _entries[_index].uri,
          state: _envelope(_serialOf(_entries[_index]), routeInformation.state),
        );
        super.routerReportsNewRouteInformation(
          leaving,
          type: RouteInformationReportingType.neglect,
        );
        _entries[_index] = leaving;
      }
      _serial += 1;
      final entry = RouteInformation(
        uri: routeInformation.uri,
        state: _envelope(_serial, routeInformation.state),
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
      final entry = RouteInformation(
        uri: routeInformation.uri,
        state: _envelope(serial, routeInformation.state),
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
        _moveTo(serial);
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

    if (own) {
      _moveTo(serial);
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

  void _moveTo(Object? serial) {
    final i = _entries.indexWhere((e) => _serialOf(e) == serial);
    if (i >= 0) _index = i;
  }

  Map<String, Object?> _envelope(int serial, Object? historyState) {
    return {'fdr': 1, 's': _session, 'i': serial, 'h': historyState};
  }

  static int _serialOf(RouteInformation entry) {
    return ((entry.state! as Map)['i']! as num).toInt();
  }
}

/// Bundles delegate, parser and provider for `MaterialApp.router`.
class FdrRouter<R extends Object> {
  FdrRouter({
    required StatefulNavigator<R> root,
    required UrlCodec<R> codec,
    required R Function(Uri uri) notFound,
    BrowserHistory? browserHistory,
    HistoryAction popFallback = HistoryAction.push,
    RouteInformation? initialRouteInformation,
    int? sessionId,
  }) : delegate = FdrRouterDelegate(root: root, codec: codec),
       parser = FdrRouteInformationParser(codec: codec, notFound: notFound) {
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
}
