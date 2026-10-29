part of 'core.dart';

/// The top of a navigator tree, shared by the router and
/// [DeclarativeNavigator]: flattens the root entries and renders them in one
/// Navigator. [R] is the root's route type, which links of that type resolve
/// to.
final class NavHost<R> {
  NavHost(this.scope, {required String description})
    : _target = _HostTarget<R>(scope, description) {
    _mapper = _PageMapper(_target);
  }

  final RoutingScope scope;
  final _HostTarget<R> _target;
  late final _PageMapper _mapper;

  ValueListenable<List<FlatPage>> get pages => _mapper.pages;

  /// Route of the top-most routed page, in [R] (or a [Url] for the
  /// not-found page).
  Object? get route => _mapper.route;

  Object? get historyState => _mapper.historyState;

  void restoreHistoryState(Object? state) => _mapper.restoreHistoryState(state);

  void update(List<NavEntry<Object?>> entries, {Object? incomingRoute}) {
    _mapper.updatePages(entries, incomingRoute: incomingRoute);
  }

  String? routeKey(Object route) => _target._routeKeyOf(route);

  /// Links resolve in [scope] after this tree, e.g. the tree of an enclosing
  /// page; taken from [context].
  void linkTo(BuildContext context) {
    _target._parentTarget = context
        .getInheritedWidgetOfExactType<_NavScope>()
        ?.target;
  }

  List<KeyedPage> keyed() => keyPages(_mapper.pages.value, routeKey);

  Widget navigator({Key? key}) {
    // the scope also covers routes pushed outside the pages, like
    // showModalBottomSheet or menus: their links resolve at the root
    return _NavScope(
      target: _target,
      child: ValueListenableBuilder(
        valueListenable: _mapper.pages,
        builder: (context, pages, _) {
          return Navigator(
            key: key,
            pages: [
              for (final (i, (key, page)) in keyPages(pages, routeKey).indexed)
                page.buildPage(defaultKey: key, forceCanPop: i == 0),
            ],
            onDidRemovePage: (page) => applyPopContract(page, keyed),
          );
        },
      ),
    );
  }

  void dispose() => _mapper.dispose();
}
