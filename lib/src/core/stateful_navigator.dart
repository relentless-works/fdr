part of 'core.dart';

/// Throwaway configuration of a navigator; its state lives in the
/// [StatefulNavigatorState] the library creates and retains.
///
/// [R] is the navigator's route type (a sealed class), `Never` for navigators
/// without a URL.
abstract class StatefulNavigator<R> implements DeclarativeNavigatable<R> {
  const StatefulNavigator({this.key});

  /// Like [Widget.key]: states are reused when runtimeType and key match.
  final Key? key;

  StatefulNavigatorState<StatefulNavigator<R>, R> createState();
}

typedef _AnyState = StatefulNavigatorState<StatefulNavigator<Object?>, Object?>;

abstract class StatefulNavigatorState<N extends StatefulNavigator<R>, R> {
  late N _navigator;

  N get navigator => _navigator;

  late final NavigatableToPageMapper _pageMapper;

  RoutingScope? _scope;
  String? Function(Object route)? _routeKey;
  bool _mounted = false;

  /// Whether this state is in use: true from [initState] until [dispose].
  /// Check it before calling [setState] from an async callback.
  bool get mounted => _mounted;

  ValueListenable<List<DeclarativeNavigatablePage<Object?>>> get pages {
    return _pageMapper.pages;
  }

  /// The route of the top-most routed page in this navigator's flattened page
  /// list (own pages and mounted children), or `null` if there is none.
  R? get route => _pageMapper.route as R?;

  @mustCallSuper
  void initState() {
    _mounted = true;
    _pageMapper = NavigatableToPageMapper(
      _scope,
      _routeKey ?? NavigatableToPageMapper._noRouteKey,
    );
    FdrHotReload.listenable.addListener(updatePages);
  }

  @mustCallSuper
  void didUpdateNavigator(covariant N oldNavigator) {}

  /// Sets the state so that the next [build] produces the pages for [route].
  ///
  /// Called for deep links, address-bar edits, browser back/forward, state
  /// restoration and [navigate], before the next build. Only this navigator's
  /// own state is to be set here: the routes of mounted children are
  /// distributed by the library through [MountedNavigatable.unwrap].
  void applyRoute(R route) {
    assert(
      false,
      '$runtimeType received a route ($route) but does not override applyRoute',
    );
  }

  /// Non-URL state to keep in the browser history entry and the restoration
  /// bucket; JSON primitives only (null, bool, num, String, List, Map).
  Object? get historyState => null;

  void restoreHistoryState(Object? state) {}

  /// Tag under which [historyState] is stored; override with a stable string
  /// if the runtime type name may change (minified web builds, renames).
  String get restorationType => runtimeType.toString();

  void setState(
    void Function() fn, {
    HistoryAction history = HistoryAction.auto,
  }) {
    assert(mounted, 'setState() called on $runtimeType after dispose()');
    fn();
    _scope?.requestHistory(history);
    updatePages();
  }

  /// Rebuilds this navigator whenever [listenable] notifies, until this
  /// state is disposed: for navigation that follows app state owned
  /// elsewhere (a session, a repository), which [build] then reads directly.
  /// Call it in [initState]; [history] applies to the resulting changes.
  void watch(
    Listenable listenable, {
    HistoryAction history = HistoryAction.auto,
  }) {
    void rebuild() => setState(() {}, history: history);
    listenable.addListener(rebuild);
    _unwatch.add(() => listenable.removeListener(rebuild));
  }

  final _unwatch = <VoidCallback>[];

  /// Typed in-app navigation: applies [route] to this navigator and its
  /// mounted children, exactly like an incoming URL.
  void navigate(R route, {HistoryAction history = HistoryAction.auto}) {
    applyRoute(route);
    _scope?.requestHistory(history);
    _updatePages(route);
  }

  void updatePages() => _updatePages(null);

  void _updatePages(Object? incomingRoute) {
    _pageMapper.updatePages(build(), incomingRoute: incomingRoute);
  }

  List<DeclarativeNavigatable<R>> build();

  @mustCallSuper
  void dispose() {
    for (final unwatch in _unwatch) {
      unwatch();
    }
    _unwatch.clear();
    _mounted = false;
    FdrHotReload.listenable.removeListener(updatePages);
    _pageMapper.dispose();
  }

  bool isForNavigator(StatefulNavigator<Object?> item) {
    return item.runtimeType == _navigator.runtimeType &&
        item.key == _navigator.key;
  }
}
