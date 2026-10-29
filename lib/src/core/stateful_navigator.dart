part of 'core.dart';

/// Throwaway configuration of a navigator; its state lives in the
/// [StatefulNavigatorState] the library creates and retains.
///
/// [R] is the navigator's route type (a sealed class extending [NavRoute]),
/// `Never` for navigators without a URL.
abstract class StatefulNavigator<R> implements NavEntry<R> {
  const StatefulNavigator({this.key});

  /// Like [Widget.key]: a state is reused for a navigator of the same
  /// runtimeType and key, also when a keyed navigator moves in the build
  /// list; unkeyed navigators are matched by position.
  final Key? key;

  StatefulNavigatorState<StatefulNavigator<R>, R> createState();

  bool _takes(Object route) => route is R;

  bool _takesAll<T>() => <T>[] is List<R>;
}

/// Whether every [T] is a route of [navigator]; for the router's debug check.
bool debugNavigatorTakes<T>(StatefulNavigator<Object?> navigator) =>
    navigator._takesAll<T>();

typedef _AnyState = StatefulNavigatorState<StatefulNavigator<Object?>, Object?>;

Object? _identity(Object? route) => route;

/// The retained state of a [StatefulNavigator], like a widget's [State].
///
/// Lifecycle: [initState]; [applyRoute] with the route it was created for,
/// if any; [build]. Then, any number of times: [applyRoute] for each
/// incoming route that addresses this navigator, followed by [build];
/// [setState] (or a [watch]ed or [listen]ed change) followed by [build];
/// [didUpdateNavigator] when the parent rebuilds with a new configuration.
/// Finally [dispose], when the parent no longer builds it.
///
/// The URL follows from the routes of the pages [build] returns; between
/// incoming routes, this state decides what is shown.
abstract class StatefulNavigatorState<N extends StatefulNavigator<R>, R>
    implements _LinkTarget {
  late N _navigator;

  N get navigator => _navigator;

  late final _PageMapper _pageMapper;

  // set by the parent before initState, and on every build of the parent
  late _LinkTarget _parent;
  Object? Function(Object? route) _lift = _identity;

  bool _mounted = false;

  /// Whether this state is in use: true from [initState] until [dispose].
  /// Check it before calling [setState] from an async callback.
  bool get mounted => _mounted;

  @mustCallSuper
  void initState() {
    _mounted = true;
    _pageMapper = _PageMapper(this);
    FdrHotReload.listenable.addListener(_rebuild);
  }

  @mustCallSuper
  void didUpdateNavigator(covariant N oldNavigator) {}

  /// Sets the state so that the next [build] shows [route].
  ///
  /// Called for deep links, address-bar edits, browser back/forward, links,
  /// [open] and state restoration, before the next build. Only this
  /// navigator's own state is set here; for a child navigator, store the
  /// child's part of the route and pass it as [NestedNavigator.route].
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

  /// Runs [fn] and rebuilds. [history] says what the resulting URL change
  /// does to the browser history; by default it follows from how the page
  /// stack changed: pages removed from the top go back, pages added on top
  /// push, anything else pushes if the URL changed.
  void setState(
    void Function() fn, {
    HistoryAction history = HistoryAction.auto,
  }) {
    assert(mounted, 'setState() called on $runtimeType after dispose()');
    fn();
    _routing.requestHistory(history);
    _rebuild();
  }

  /// Rebuilds this navigator whenever [listenable] notifies, until this
  /// state is disposed: for navigation that follows app state owned
  /// elsewhere (a session, a view model), which [build] then reads directly.
  /// Call it in [initState]; [history] applies to the resulting changes.
  void watch(
    Listenable listenable, {
    HistoryAction history = HistoryAction.auto,
  }) {
    void rebuild() => setState(() {}, history: history);
    listenable.addListener(rebuild);
    _unsubscribe.add(() => listenable.removeListener(rebuild));
  }

  /// Rebuilds this navigator on every event of [stream] (e.g. a bloc's
  /// `stream`), until this state is disposed. Call it in [initState]. For a
  /// store with a current value (a bloc's `state`), [build] reads that, and
  /// page `onPop`s can call the store directly: the page goes once the store
  /// has emitted its new state.
  void listen(
    Stream<Object?> stream, {
    HistoryAction history = HistoryAction.auto,
  }) {
    final subscription = stream.listen(
      (_) => setState(() {}, history: history),
    );
    _unsubscribe.add(() => unawaited(subscription.cancel()));
  }

  final _unsubscribe = <VoidCallback>[];

  /// Navigates to [route] like a link: the route is placed in the root's
  /// route type through the parents' [NestedNavigator.at] and applied from
  /// the root down, exactly like an incoming URL. By default, the history
  /// action follows from how the page stack changes (push, or a back).
  ///
  /// Called during an update (e.g. in [applyRoute] or [initState], to
  /// redirect), it runs once that update is done.
  void open(R route, {HistoryAction history = HistoryAction.auto}) {
    assert(mounted, 'open() called on $runtimeType after dispose()');
    _routing.open(_toRoot(route), history);
  }

  void _rebuild() => _updatePages(null);

  void _updatePages(Object? incomingRoute) {
    _pageMapper.updatePages(build().toList(), incomingRoute: incomingRoute);
  }

  /// The pages and child navigators to show, bottom first: usually a list
  /// literal with collection-`if`s, or a `sync*` body.
  Iterable<NavEntry<R>> build();

  @mustCallSuper
  void dispose() {
    for (final unsubscribe in _unsubscribe) {
      unsubscribe();
    }
    _unsubscribe.clear();
    _mounted = false;
    FdrHotReload.listenable.removeListener(_rebuild);
    _pageMapper.dispose();
  }

  bool _isFor(StatefulNavigator<Object?> item) {
    return item.runtimeType == _navigator.runtimeType &&
        item.key == _navigator.key;
  }

  @override
  _LinkTarget? get _parentTarget => _parent;

  @override
  RoutingScope get _routing => _parent._routing;

  @override
  bool _accepts(Object route) => route is R;

  @override
  Object? _toRoot(Object? route) => _parent._toRoot(_lift(route));

  @override
  String? _routeKeyOf(Object route) {
    final lifted = _lift(route);
    return lifted == null ? null : _parent._routeKeyOf(lifted);
  }

  @override
  String get _description => '${_navigator.runtimeType} ($R)';
}
