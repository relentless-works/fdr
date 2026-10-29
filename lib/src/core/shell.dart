part of 'core.dart';

/// Builds the persistent chrome of a shell (e.g. a `Scaffold` with a
/// `NavigationBar`) around [branches], one nested navigator widget per
/// branch, of which [active] is the visible one. Put the branches into an
/// `IndexedStack` (or anything else that keeps them mounted) so inactive
/// branches keep their pages and widget state.
typedef ShellBuilder = Widget Function(
  BuildContext context,
  List<Widget> branches,
  int active,
);

/// A page whose body hosts one nested navigator per branch, e.g. the tabs
/// behind a bottom navigation bar.
///
/// The shell contributes a single page (with a stable key) to its owner's
/// stack, so its chrome does not animate when pages are pushed inside a
/// branch. Each branch keeps its own retained navigator states and page
/// stack. The shell page's route is the active branch's top route, so the
/// URL follows the visible tab; an incoming route is handed to every branch,
/// and the branches' mounts decide which one it addresses.
final class ShellNavigatable<R> implements DeclarativeNavigatable<R> {
  ShellNavigatable({
    required this.branches,
    required this.active,
    required this.builder,
    required this.page,
  }) : assert(
         active >= 0 && active < branches.length,
         'active branch $active out of range',
       );

  final List<DeclarativeNavigatable<R>> branches;
  final int active;
  final ShellBuilder builder;

  /// Wraps the shell's body into the page shown in the owner's navigator.
  final DeclarativeNavigatablePage<R> Function(Widget body) page;
}

/// The retained part of a shell: one page mapper per branch.
final class _ShellHost {
  _ShellHost(this._scope, this._routeKey, this._onBranchChanged);

  final RoutingScope? _scope;
  final String? Function(Object route) _routeKey;
  final VoidCallback _onBranchChanged;
  final _branches = <NavigatableToPageMapper>[];
  late ShellNavigatable<Object?> _item;

  void update(ShellNavigatable<Object?> item, Object? incomingRoute) {
    _item = item;
    while (_branches.length > item.branches.length) {
      _branches.removeLast()
        ..pages.removeListener(_onBranchChanged)
        ..dispose();
    }
    for (final (i, branch) in item.branches.indexed) {
      if (i == _branches.length) {
        _branches.add(NavigatableToPageMapper(_scope, _routeKey));
      } else {
        _branches[i].pages.removeListener(_onBranchChanged);
      }
      _branches[i]
        ..updatePages([branch], incomingRoute: incomingRoute)
        ..pages.addListener(_onBranchChanged);
    }
  }

  NavigatableToPageMapper get _activeBranch => _branches[_item.active];

  DeclarativeNavigatablePage<Object?> page() {
    final shellPage = _item.page(
      _ShellView(host: this, builder: _item.builder, active: _item.active),
    );
    return DeclarativeNavigatablePage<Object?>(
      builder: shellPage._builder,
      onPop: shellPage.onPop,
      route: _activeBranch.route,
      key: shellPage.key,
      nestedPages: () => keyPages(_activeBranch.pages.value, _routeKey),
    );
  }

  Object? get historyState {
    final branches = [for (final b in _branches) b.historyState];
    return branches.every((s) => s == null) ? null : branches;
  }

  void restoreHistoryState(Object? state) {
    if (state is! List) return;
    for (final (i, branch) in _branches.indexed) {
      if (i < state.length) branch.restoreHistoryState(state[i]);
    }
  }

  void dispose() {
    for (final branch in _branches) {
      branch
        ..pages.removeListener(_onBranchChanged)
        ..dispose();
    }
    _branches.clear();
  }
}

class _ShellView extends StatelessWidget {
  const _ShellView({
    required this.host,
    required this.builder,
    required this.active,
  });

  final _ShellHost host;
  final ShellBuilder builder;
  final int active;

  @override
  Widget build(BuildContext context) {
    return builder(context, [
      for (final (i, branch) in host._branches.indexed)
        _BranchNavigator(
          key: ObjectKey(branch),
          mapper: branch,
          routeKey: host._routeKey,
          active: i == active,
        ),
    ], active);
  }
}

/// The nested Navigator of one shell branch. System back reaches it through
/// [NavigatorPopHandler] while it is the active branch; at the branch's root
/// the pop bubbles to the owner's navigator.
class _BranchNavigator extends StatefulWidget {
  const _BranchNavigator({
    super.key,
    required this.mapper,
    required this.routeKey,
    required this.active,
  });

  final NavigatableToPageMapper mapper;
  final String? Function(Object route) routeKey;
  final bool active;

  @override
  State<_BranchNavigator> createState() => _BranchNavigatorState();
}

class _BranchNavigatorState extends State<_BranchNavigator> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _heroController = HeroController();

  List<KeyedPage> _keyed() =>
      keyPages(widget.mapper.pages.value, widget.routeKey);

  @override
  Widget build(BuildContext context) {
    return NavigatorPopHandler<Object?>(
      enabled: widget.active,
      onPopWithResult: (_) {
        // a vetoed pop is announced to every PopScope of the shell's route,
        // including the handlers of inactive branches
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
              return Navigator(
                key: _navigatorKey,
                pages: [
                  for (final (i, (key, page)) in keyPages(
                    pages,
                    widget.routeKey,
                  ).indexed)
                    page.buildPage(defaultKey: key, forceCanPop: i == 0),
                ],
                onDidRemovePage: (page) => applyPopContract(page, _keyed),
              );
            },
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
