part of 'core.dart';

/// The retained part of a [TabsPage]: one page mapper per tab.
///
/// The tabs contribute a single page (with a stable key) to the owner's
/// stack; its route is the active tab's top route, so the URL follows the
/// visible tab.
final class _TabsHost {
  _TabsHost(this._owner, this._onTabChanged);

  final _LinkTarget _owner;
  final VoidCallback _onTabChanged;
  final _tabs = <_PageMapper>[];
  late TabsPage<Object?> _entry;

  /// [history] is restored into the tabs this creates: history state that
  /// was restored before they existed (see [restoreHistoryState]).
  void update(
    TabsPage<Object?> entry,
    Object? incomingRoute, [
    Object? history,
  ]) {
    assert(
      entry.index >= 0 && entry.index < entry.tabs.length,
      'tab index ${entry.index} out of range',
    );
    // a tab whose update throws leaves the tabs and the entry as they were
    final before = _tabs.length;
    try {
      for (final (i, tab) in entry.tabs.indexed) {
        if (i == _tabs.length) {
          // restored before its navigator is created, which takes it then
          _tabs.add(_PageMapper(_owner)..restoreHistoryState(_tab(history, i)));
        } else {
          _tabs[i].pages.removeListener(_onTabChanged);
        }
        try {
          _tabs[i].updatePages([tab], incomingRoute: incomingRoute);
        } finally {
          _tabs[i].pages.addListener(_onTabChanged);
        }
      }
    } on Object {
      while (_tabs.length > before) {
        _removeLastTab();
      }
      rethrow;
    }
    while (_tabs.length > entry.tabs.length) {
      _removeLastTab();
    }
    _entry = entry;
  }

  void _removeLastTab() {
    final tab = _tabs.removeLast()..pages.removeListener(_onTabChanged);
    _PageMapper._guarded(tab.dispose);
  }

  /// The [TabsPage.key] these tabs were built for.
  LocalKey? get key => _entry.key;

  _PageMapper get _activeTab => _tabs[_entry.index];

  FlatPage page() {
    final view = _NavScope(
      target: _owner,
      child: _TabsView(
        // a copy: a removed page keeps showing its tabs while it animates
        // out, also after they are disposed
        tabs: List.of(_tabs),
        builder: _entry.builder,
        active: _entry.index,
      ),
    );
    return FlatPage(
      builder: (key, canPop) => _NavPage(
        key: key,
        canPop: canPop,
        style: _PageStyle.adaptive,
        child: view,
      ),
      onPop: _entry.onPop,
      route: _activeTab.route,
      key: _entry.key,
      keyBase: 'fdr:tabs',
      nestedPages: () => keyPages(_activeTab.pages.value, _owner._routeKeyOf),
      identity: TabsPage,
      owner: _owner,
    );
  }

  Object? get historyState {
    final tabs = [for (final tab in _tabs) tab.historyState];
    return tabs.every((s) => s == null) ? null : tabs;
  }

  // a tab the state holds nothing for had no history state then
  void restoreHistoryState(Object? state) {
    for (final (i, tab) in _tabs.indexed) {
      tab.restoreHistoryState(_tab(state, i));
    }
  }

  static Object? _tab(Object? state, int i) =>
      state is List && i < state.length ? state[i] : null;

  void dispose() {
    for (final tab in _tabs) {
      tab.pages.removeListener(_onTabChanged);
      _PageMapper._guarded(tab.dispose);
    }
    _tabs.clear();
  }
}

class _TabsView extends StatelessWidget {
  const _TabsView({
    required this.tabs,
    required this.builder,
    required this.active,
  });

  final List<_PageMapper> tabs;
  final TabsBuilder builder;
  final int active;

  @override
  Widget build(BuildContext context) {
    return builder(context, [
      for (final (i, tab) in tabs.indexed)
        _TabNavigator(key: ObjectKey(tab), mapper: tab, active: i == active),
    ]);
  }
}

/// The nested Navigator of one tab. System back reaches it through
/// [NavigatorPopHandler] while it is the active tab; at the tab's root the
/// pop bubbles to the owner's navigator.
class _TabNavigator extends StatefulWidget {
  const _TabNavigator({super.key, required this.mapper, required this.active});

  final _PageMapper mapper;
  final bool active;

  @override
  State<_TabNavigator> createState() => _TabNavigatorState();
}

class _TabNavigatorState extends State<_TabNavigator> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _heroController = HeroController();

  List<KeyedPage> _keyed() =>
      keyPages(widget.mapper.pages.value, widget.mapper.routeKey);

  @override
  Widget build(BuildContext context) {
    // An inactive tab's Navigator must not tell the ancestors that it can
    // handle a pop: an enclosing NavigatorPopHandler would then veto system
    // back, which the active tab at its root cannot handle. When the tab
    // becomes active, its handler's PopScope changes and the tabs' route
    // announces the new state.
    return NotificationListener<NavigationNotification>(
      onNotification: (_) => !widget.active,
      child: NavigatorPopHandler<Object?>(
        enabled: widget.active,
        onPopWithResult: (_) {
          // a vetoed pop is announced to every PopScope of the tabs' route,
          // including the handlers of inactive tabs
          if (widget.active) _navigatorKey.currentState?.maybePop();
        },
        child: TickerMode(
          enabled: widget.active,
          child: HeroControllerScope(
            controller: _heroController,
            child: ValueListenableBuilder(
              valueListenable: widget.mapper.pages,
              builder: (context, pages, _) {
                if (pages.isEmpty) return const SizedBox.shrink();
                return _NavScope(
                  target: widget.mapper._owner,
                  child: Navigator(
                    key: _navigatorKey,
                    pages: [
                      for (final (i, (key, page)) in keyPages(
                        pages,
                        widget.mapper.routeKey,
                      ).indexed)
                        page.buildPage(defaultKey: key, forceCanPop: i == 0),
                    ],
                    onDidRemovePage: (page) => applyPopContract(page, _keyed),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _heroController.dispose();
    super.dispose();
  }
}
