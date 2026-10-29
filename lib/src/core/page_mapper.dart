part of 'core.dart';

/// Reconciles one navigator's build list into a flat page list.
///
/// Besides flattening it does three routing jobs:
/// 1. state -> URL: every page in the flat list carries its route in the
///    route type of the owning navigator; child pages are lifted through
///    [NestedNavigator.at]. [route] is the route of the top-most routed page.
/// 2. URL -> state: an [updatePages] call with `incomingRoute` hands each
///    child navigator its [NestedNavigator.route] if that addresses it,
///    before the child's build.
/// 3. non-URL state: [historyState] aggregates the states' `historyState`
///    into a JSON tree keyed by index and navigator type.
final class _PageMapper {
  _PageMapper(this._owner);

  /// The navigator state (or host) whose build list this is.
  final _LinkTarget _owner;

  final _pages = ValueNotifier<List<FlatPage>>([]);

  var _statesByIndex = <_AnyState?>[];
  var _tabsByIndex = <_TabsHost?>[];
  var _entries = <NavEntry<Object?>>[];
  Object? _incomingRoute;

  // during a pass: a child's pages changed, or this navigator was asked to
  // update again (a child's initState or applyRoute changed an ancestor);
  // both are handled once the pass is done instead of re-entering it
  bool _building = false;
  bool _childChanged = false;
  (List<NavEntry<Object?>>, Object?)? _queued;

  /// Route of the top-most routed page, in the owning navigator's route type.
  Object? route;

  ValueListenable<List<FlatPage>> get pages => _pages;

  String? routeKey(Object route) => _owner._routeKeyOf(route);

  void updatePages(List<NavEntry<Object?>> entries, {Object? incomingRoute}) {
    if (_building) {
      _queued = (entries, incomingRoute ?? _queued?.$2);
      return;
    }
    _pass(() => _reconcile(entries, incomingRoute));
  }

  void _reconcile(List<NavEntry<Object?>> entries, Object? incomingRoute) {
    _entries = entries;
    _incomingRoute = incomingRoute;
    try {
      _rebuildPages(reconcile: true);
    } finally {
      _incomingRoute = null;
    }
  }

  // a child changed its pages: re-flatten without touching any child state
  void _onChildPagesChanged() {
    if (_building) {
      _childChanged = true;
      return;
    }
    _pass(() => _rebuildPages(reconcile: false));
  }

  void _pass(VoidCallback pass) {
    final routing = _owner._routing;
    routing._passes++;
    _building = true;
    try {
      pass();
      while (_queued != null || _childChanged) {
        _childChanged = false;
        if (_queued case (final entries, final incoming)?) {
          _queued = null;
          _reconcile(entries, incoming);
        } else {
          _rebuildPages(reconcile: false);
        }
      }
    } finally {
      _building = false;
      routing._passes--;
    }
    if (routing._passes == 0) routing._openQueued();
  }

  void _rebuildPages({required bool reconcile}) {
    final pages = <FlatPage>[];
    final states = List<_AnyState?>.filled(_entries.length, null);
    final tabs = List<_TabsHost?>.filled(_entries.length, null);
    final incoming = _incomingRoute;

    for (final (index, entry) in _entries.indexed) {
      switch (entry) {
        case NavPage<Object?>():
          pages.add(_navPage(entry));

        case DialogPage():
          pages.add(_dialogPage(entry));

        case CustomPage<Object?>():
          final child = _NavScope(target: _owner, child: entry.child);
          pages.add(
            FlatPage(
              builder: (key, canPop) => entry.builder(key, canPop, child),
              onPop: entry.onPop,
              route: entry.route,
              key: entry.key,
            ),
          );

        case StatefulNavigator<Object?>():
          // same route type: the incoming routes of this navigator are the
          // child's too, as far as its type takes them (none for `Never`)
          final state = _childState(
            index,
            entry,
            lift: null,
            incoming: incoming != null && entry._takes(incoming)
                ? incoming
                : null,
            initial: null,
            reconcile: reconcile,
          );
          states[index] = state;
          pages.addAll(state._pageMapper.pages.value);

        case NestedNavigator<Object?, Object?>():
          assert(
            entry._debugLiftsWithoutAt,
            'NestedNavigator around ${entry.child.runtimeType} needs `at`: '
            'its route type differs from its parent\'s. A navigator with a '
            'route type needs parents with route types up to the root.',
          );
          final route = entry.route;
          final addressed =
              incoming != null &&
              route != null &&
              _sameRoute(entry._lift(route), incoming);
          final state = _childState(
            index,
            entry.child,
            lift: entry._lift,
            incoming: addressed ? route : null,
            initial: route,
            reconcile: reconcile,
          );
          states[index] = state;
          final childPages = [
            for (final page in state._pageMapper.pages.value)
              page.route == null
                  ? page
                  : page.withRoute(entry._lift(page.route)),
          ];
          final onPop = entry.onPop;
          if (onPop != null && childPages.isNotEmpty) {
            childPages[0] = childPages[0].withOnPop(onPop);
          }
          pages.addAll(childPages);

        case TabsPage<Object?>():
          final existing = index < _tabsByIndex.length
              ? _tabsByIndex[index]
              : null;
          final _TabsHost host;
          if (existing != null) {
            host = existing;
            _tabsByIndex[index] = null;
            if (reconcile) host.update(entry, incoming);
          } else {
            assert(reconcile, 'new tabs while only re-flattening');
            host = _TabsHost(_owner, _onChildPagesChanged)
              ..update(entry, incoming);
          }
          tabs[index] = host;
          pages.add(host.page());
      }
    }

    for (final unusedState in _statesByIndex.nonNulls) {
      unusedState._pageMapper.pages.removeListener(_onChildPagesChanged);
      unusedState.dispose();
    }
    _statesByIndex = states;
    for (final unusedTabs in _tabsByIndex.nonNulls) {
      unusedTabs.dispose();
    }
    _tabsByIndex = tabs;

    route = _topRoute(pages);
    _pages.value = pages;
  }

  FlatPage _navPage(NavPage<Object?> entry) {
    final child = _NavScope(target: _owner, child: entry.child);
    return FlatPage(
      builder: (key, canPop) => _NavPage(
        key: key,
        canPop: canPop,
        style: entry._style,
        title: entry.title,
        maintainState: entry.maintainState,
        fullscreenDialog: entry.fullscreenDialog,
        child: child,
      ),
      onPop: entry.onPop,
      route: entry.route,
      key: entry.key,
    );
  }

  FlatPage _dialogPage(DialogPage entry) {
    final child = _NavScope(target: _owner, child: entry.child);
    return FlatPage(
      builder: (key, canPop) => _DialogPage(
        key: key,
        canPop: canPop,
        barrierDismissible: entry.barrierDismissible,
        child: child,
      ),
      onPop: entry.onPop,
      key: entry.key,
    );
  }

  _AnyState _childState(
    int index,
    StatefulNavigator<Object?> navigator, {
    required Object? Function(Object? route)? lift,
    required Object? incoming,
    required Object? initial,
    required bool reconcile,
  }) {
    // a keyed navigator keeps its state when it moves in the list, like a
    // keyed widget; others are matched by position
    final at = navigator.key == null
        ? index
        : _statesByIndex.indexWhere((s) => s != null && s._isFor(navigator));
    final existing = at >= 0 && at < _statesByIndex.length
        ? _statesByIndex[at]
        : null;
    if (existing != null && existing._isFor(navigator)) {
      // remove from the old list, so it does not get disposed below
      _statesByIndex[at] = null;
      if (reconcile) {
        existing._pageMapper.pages.removeListener(_onChildPagesChanged);
        final oldNavigator = existing._navigator;
        existing
          .._navigator = navigator
          .._lift = lift ?? _identity
          ..didUpdateNavigator(oldNavigator);
        if (incoming != null) existing.applyRoute(incoming);
        existing._updatePages(incoming);
        existing._pageMapper.pages.addListener(_onChildPagesChanged);
      }
      return existing;
    }
    assert(reconcile, 'new navigator while only re-flattening');
    final state = navigator.createState()
      .._navigator = navigator
      .._parent = _owner
      .._lift = lift ?? _identity
      ..initState();
    final first = incoming ?? initial;
    if (first != null) state.applyRoute(first);
    state._updatePages(first);
    state._pageMapper.pages.addListener(_onChildPagesChanged);
    return state;
  }

  // whether a child route placed in this navigator's type is the incoming
  // route: same URL for routes, equality otherwise
  static bool _sameRoute(Object? a, Object? b) {
    if (a is NavRoute && b is NavRoute) return a.toUrl() == b.toUrl();
    return a == b;
  }

  static Object? _topRoute(List<FlatPage> pages) {
    for (final page in pages.reversed) {
      if (page.route != null) return page.route;
    }
    return null;
  }

  /// JSON tree of the non-URL state of this navigator's children.
  Object? get historyState {
    final tree = <String, Object?>{};
    for (final (index, state) in _statesByIndex.indexed) {
      if (state == null) continue;
      final own = state.historyState;
      final children = state._pageMapper.historyState;
      if (own == null && children == null) continue;
      tree['$index'] = <String, Object?>{
        't': state.restorationType,
        if (own != null) 's': own,
        if (children != null) 'c': children,
      };
    }
    for (final (index, host) in _tabsByIndex.indexed) {
      final branches = host?.historyState;
      if (branches != null) tree['$index'] = {'b': branches};
    }
    return tree.isEmpty ? null : tree;
  }

  void restoreHistoryState(Object? tree) {
    if (tree is! Map) return;
    for (final (index, state) in _statesByIndex.indexed) {
      final entry = tree['$index'];
      if (state == null || entry is! Map) continue;
      if (entry['t'] != state.restorationType) continue;
      if (entry.containsKey('s')) state.restoreHistoryState(entry['s']);
      state._pageMapper.restoreHistoryState(entry['c']);
    }
    for (final (index, host) in _tabsByIndex.indexed) {
      final entry = tree['$index'];
      if (host != null && entry is Map) host.restoreHistoryState(entry['b']);
    }
  }

  void dispose() {
    for (final state in _statesByIndex.nonNulls) {
      state._pageMapper.pages.removeListener(_onChildPagesChanged);
      state.dispose();
    }
    _statesByIndex = [];
    for (final host in _tabsByIndex.nonNulls) {
      host.dispose();
    }
    _tabsByIndex = [];
    _pages.dispose();
  }
}
