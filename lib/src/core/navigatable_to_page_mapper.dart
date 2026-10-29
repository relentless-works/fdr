part of 'core.dart';

/// Reconciles one navigator's build list into a flat page list.
///
/// Besides flattening (as in fdr 0.0.5) it does three routing jobs:
/// 1. state -> URL: every page in the flat list carries its route in the
///    route type of the owning navigator; child pages are re-typed through
///    the mount's `embed`. [route] is the route of the top-most routed page.
/// 2. URL -> state: an [updatePages] call with `incomingRoute` hands each
///    mounted child the part `unwrap` extracts, before the child's build.
/// 3. non-URL state: [historyState] aggregates the states' `historyState`
///    into a JSON tree keyed by index and navigator type.
final class NavigatableToPageMapper {
  NavigatableToPageMapper(this._scope, [this.routeKey = _noRouteKey]);

  final RoutingScope? _scope;

  /// Identity of a route of this mapper's route type, for page keys; derived
  /// by the router from the root codec through the chain of mounts.
  final String? Function(Object route) routeKey;

  static String? _noRouteKey(Object route) => null;

  final _pages = ValueNotifier<List<DeclarativeNavigatablePage<Object?>>>([]);

  var _activeStatesByIndex = <_AnyState?>[];
  var _activeShellsByIndex = <_ShellHost?>[];
  var _navigatables = <DeclarativeNavigatable<Object?>>[];
  Object? _incomingRoute;

  /// Route of the top-most routed page, in the owning navigator's route type.
  Object? route;

  ValueListenable<List<DeclarativeNavigatablePage<Object?>>> get pages {
    return _pages;
  }

  void updatePages(
    List<DeclarativeNavigatable<Object?>> navigatables, {
    Object? incomingRoute,
  }) {
    _navigatables = navigatables;
    _incomingRoute = incomingRoute;
    try {
      _rebuildPages(reconcile: true);
    } finally {
      _incomingRoute = null;
    }
  }

  // a child changed its pages: re-flatten without touching any child state
  void _onChildPagesChanged() => _rebuildPages(reconcile: false);

  void _rebuildPages({required bool reconcile}) {
    final pages = <DeclarativeNavigatablePage<Object?>>[];
    final states = List<_AnyState?>.filled(_navigatables.length, null);
    final shells = List<_ShellHost?>.filled(_navigatables.length, null);

    for (final (index, outerItem) in _navigatables.indexed) {
      var item = outerItem;

      var hasPopOverwrite = false;
      VoidCallback? popOverwrite;
      if (item is PopOverwriteNavigatable<Object?>) {
        hasPopOverwrite = true;
        popOverwrite = item.onPop;
        item = item.child;
      }

      Object? Function(Object?)? embed;
      Object? childRoute;
      Object? initialRoute;
      if (item is MountedNavigatable<Object?, Object?>) {
        embed = item.embedUntyped;
        initialRoute = item.initialRoute;
        final incoming = _incomingRoute;
        if (incoming != null) {
          childRoute = item.unwrapUntyped(incoming);
        }
        item = item.child;
      }

      switch (item) {
        case DeclarativeNavigatablePage<Object?>():
          pages.add(
            hasPopOverwrite ? item.withOnPop(onPop: popOverwrite) : item,
          );

        case StatefulNavigator<Object?>():
          final existing = index < _activeStatesByIndex.length
              ? _activeStatesByIndex[index]
              : null;
          final _AnyState state;
          if (existing != null && existing.isForNavigator(item)) {
            state = existing;
            // remove from the old list, so it does not get disposed below
            _activeStatesByIndex[index] = null;
            if (reconcile) {
              state.pages.removeListener(_onChildPagesChanged);
              final oldNavigator = state._navigator;
              state._navigator = item;
              state.didUpdateNavigator(oldNavigator);
              if (childRoute != null) {
                state.applyRoute(childRoute);
              }
              state._updatePages(childRoute);
              state.pages.addListener(_onChildPagesChanged);
            }
          } else {
            assert(reconcile, 'new navigator while only re-flattening');
            state = item.createState();
            state._navigator = item;
            state._scope = _scope;
            final lift = embed;
            state._routeKey = lift == null
                ? routeKey
                : (route) => routeKey(lift(route)!);
            state.initState();
            final firstRoute = childRoute ?? initialRoute;
            if (firstRoute != null) {
              state.applyRoute(firstRoute);
            }
            state._updatePages(firstRoute);
            state.pages.addListener(_onChildPagesChanged);
          }
          states[index] = state;

          Iterable<DeclarativeNavigatablePage<Object?>> childPages =
              state.pages.value;
          if (hasPopOverwrite && childPages.isNotEmpty) {
            childPages = [
              childPages.first.withOnPop(onPop: popOverwrite),
              ...childPages.skip(1),
            ];
          }
          if (embed != null) {
            final lift = embed;
            childPages = childPages.map((p) {
              final r = p.route;
              return p.withRoute<Object?>(r == null ? null : lift(r));
            });
          }
          pages.addAll(childPages);

        case ShellNavigatable<Object?>():
          final existing = index < _activeShellsByIndex.length
              ? _activeShellsByIndex[index]
              : null;
          final _ShellHost host;
          if (existing != null) {
            host = existing;
            _activeShellsByIndex[index] = null;
            if (reconcile) host.update(item, _incomingRoute);
          } else {
            assert(reconcile, 'new shell while only re-flattening');
            host = _ShellHost(_scope, routeKey, _onChildPagesChanged)
              ..update(item, _incomingRoute);
          }
          shells[index] = host;
          final page = host.page();
          pages.add(
            hasPopOverwrite ? page.withOnPop(onPop: popOverwrite) : page,
          );

        case PopOverwriteNavigatable<Object?>():
        case MountedNavigatable<Object?, Object?>():
          throw StateError('wrappers are unwrapped above');
      }
    }

    for (final unusedState in _activeStatesByIndex.nonNulls) {
      unusedState.pages.removeListener(_onChildPagesChanged);
      unusedState.dispose();
    }
    _activeStatesByIndex = states;
    for (final unusedShell in _activeShellsByIndex.nonNulls) {
      unusedShell.dispose();
    }
    _activeShellsByIndex = shells;

    route = _topRoute(pages);
    _pages.value = pages;
  }

  static Object? _topRoute(List<DeclarativeNavigatablePage<Object?>> pages) {
    for (final page in pages.reversed) {
      if (page.route != null) return page.route;
    }
    return null;
  }

  /// JSON tree of the non-URL state of this navigator's children.
  Object? get historyState {
    final tree = <String, Object?>{};
    for (final (index, state) in _activeStatesByIndex.indexed) {
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
    for (final (index, shell) in _activeShellsByIndex.indexed) {
      final branches = shell?.historyState;
      if (branches != null) tree['$index'] = {'b': branches};
    }
    return tree.isEmpty ? null : tree;
  }

  void restoreHistoryState(Object? tree) {
    if (tree is! Map) return;
    for (final (index, state) in _activeStatesByIndex.indexed) {
      final entry = tree['$index'];
      if (state == null || entry is! Map) continue;
      if (entry['t'] != state.restorationType) continue;
      if (entry.containsKey('s')) state.restoreHistoryState(entry['s']);
      state._pageMapper.restoreHistoryState(entry['c']);
    }
    for (final (index, shell) in _activeShellsByIndex.indexed) {
      final entry = tree['$index'];
      if (shell != null && entry is Map) shell.restoreHistoryState(entry['b']);
    }
  }

  void dispose() {
    for (final state in _activeStatesByIndex.nonNulls) {
      state.pages.removeListener(_onChildPagesChanged);
      state.dispose();
    }
    _activeStatesByIndex = [];
    for (final shell in _activeShellsByIndex.nonNulls) {
      shell.dispose();
    }
    _activeShellsByIndex = [];
    _pages.dispose();
  }
}
