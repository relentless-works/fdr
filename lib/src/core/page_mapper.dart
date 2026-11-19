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
    final previous = _entries;
    _entries = entries;
    _incomingRoute = incomingRoute;
    try {
      _rebuildPages(reconcile: true);
    } on Object {
      // user code threw (a child's build, applyRoute, initState): this
      // navigator stays at its last good entries and states. Children
      // updated before the throw keep their new pages, so flatten again.
      _entries = previous;
      _incomingRoute = null;
      try {
        _rebuildPages(reconcile: false);
      } on Object {
        // the first error is the one to report
      }
      rethrow;
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
    var done = false;
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
      done = true;
    } finally {
      // set only if the pass threw: what it queued is as stale as the pass
      _queued = null;
      _childChanged = false;
      _building = false;
      routing._passes--;
      if (!done && routing._passes == 0) routing._abandon();
    }
    if (routing._passes == 0) routing._settle();
  }

  void _rebuildPages({required bool reconcile}) {
    final pages = <FlatPage>[];
    final states = List<_AnyState?>.filled(_entries.length, null);
    final tabs = List<_TabsHost?>.filled(_entries.length, null);
    // The old lists stay as they are until every entry is done, so a throw
    // in user code (a child's build, applyRoute, initState) leaves this
    // navigator with the states it had. `reused` are the old states and
    // tabs taken over so far.
    final reused = Set<Object>.identity();

    try {
      _visitEntries(pages, states, tabs, reused, reconcile: reconcile);
    } on Object {
      // what this pass created is not kept
      for (final state in states.nonNulls) {
        if (!reused.contains(state)) _discard(state);
      }
      for (final host in tabs.nonNulls) {
        if (!reused.contains(host)) _guarded(host.dispose);
      }
      rethrow;
    }

    for (final unusedState in _statesByIndex.nonNulls) {
      if (reused.contains(unusedState)) continue;
      unusedState._pageMapper.pages.removeListener(_onChildPagesChanged);
      unusedState.dispose();
    }
    _statesByIndex = states;
    for (final unusedTabs in _tabsByIndex.nonNulls) {
      if (!reused.contains(unusedTabs)) unusedTabs.dispose();
    }
    _tabsByIndex = tabs;

    route = _topRoute(pages);
    _pages.value = pages;
  }

  // disposes a state created in a pass that then threw
  void _discard(_AnyState state) {
    state._pageMapper.pages.removeListener(_onChildPagesChanged);
    _guarded(state.dispose);
  }

  // cleanup after a throw: a second error must not hide the first
  static void _guarded(VoidCallback cleanup) {
    try {
      cleanup();
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack, library: 'fdr'),
      );
    }
  }

  void _visitEntries(
    List<FlatPage> pages,
    List<_AnyState?> states,
    List<_TabsHost?> tabs,
    Set<Object> reused, {
    required bool reconcile,
  }) {
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
              identity: (CustomPage, entry.child.runtimeType, entry.child.key),
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
            reused: reused,
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
            reused: reused,
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
          // matched like its page key: by key, unkeyed ones in order, so
          // the tabs keep their state when other entries come and go
          // below them
          bool free(_TabsHost? h) =>
              h != null && !reused.contains(h) && h.key == entry.key;
          final existing = _tabsByIndex.where(free).firstOrNull;
          final _TabsHost host;
          if (existing != null) {
            host = existing;
            reused.add(host);
            if (reconcile) host.update(entry, incoming);
          } else {
            assert(reconcile, 'new tabs while only re-flattening');
            host = _TabsHost(_owner, _onChildPagesChanged);
            // from here on the failed pass disposes it
            tabs[index] = host;
            host.update(entry, incoming);
          }
          tabs[index] = host;
          pages.add(host.page());
      }
    }
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
      identity: (NavPage, entry.child.runtimeType, entry.child.key),
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
      identity: (DialogPage, entry.child.runtimeType, entry.child.key),
    );
  }

  _AnyState _childState(
    int index,
    StatefulNavigator<Object?> navigator, {
    required Object? Function(Object? route)? lift,
    required Object? incoming,
    required Object? initial,
    required Set<Object> reused,
    required bool reconcile,
  }) {
    // a keyed navigator keeps its state when it moves in the list, like a
    // keyed widget; others are matched by position
    bool free(_AnyState? s) =>
        s != null && !reused.contains(s) && s._isFor(navigator);
    final at = navigator.key == null ? index : _statesByIndex.indexWhere(free);
    final existing = at >= 0 && at < _statesByIndex.length
        ? _statesByIndex[at]
        : null;
    if (existing != null && free(existing)) {
      // taken over, so it does not get disposed after the pass
      reused.add(existing);
      if (reconcile) {
        existing._pageMapper.pages.removeListener(_onChildPagesChanged);
        try {
          final oldNavigator = existing._navigator;
          existing
            .._navigator = navigator
            .._lift = lift ?? _identity
            .._configuring = true
            ..didUpdateNavigator(oldNavigator);
          if (incoming != null) existing.applyRoute(incoming);
          existing._configuring = false;
          existing._updatePages(incoming);
        } finally {
          existing._configuring = false;
          existing._pageMapper.pages.addListener(_onChildPagesChanged);
        }
      }
      return existing;
    }
    assert(reconcile, 'new navigator while only re-flattening');
    final state = navigator.createState()
      .._navigator = navigator
      .._parent = _owner
      .._lift = lift ?? _identity;
    try {
      state
        .._configuring = true
        ..initState();
      final first = incoming ?? initial;
      if (first != null) state.applyRoute(first);
      state._configuring = false;
      state._updatePages(first);
    } on Object {
      // not mounted: initState threw before it reached super.initState
      if (state._mounted) _guarded(state.dispose);
      rethrow;
    }
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
