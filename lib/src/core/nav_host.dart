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
    // after dispose (a late open() or platform route), nothing would
    // dispose the navigator states an update creates
    if (_disposed) return;
    _mapper.updatePages(entries, incomingRoute: incomingRoute);
  }

  /// Hot reload: the update from the root rebuilds every navigator once. An
  /// error in a navigator's code is reported, not thrown, and the navigators
  /// keep what they showed: a throw out of `State.reassemble` would end the
  /// reassembly of the rest of the app and leave the binding's events locked.
  void reassemble(List<NavEntry<Object?>> Function() entries) {
    try {
      update(entries());
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'fdr',
          context: ErrorDescription(
            'while rebuilding the navigators for hot reload',
          ),
        ),
      );
    }
  }

  bool _disposed = false;

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
    // the scope also covers routes pushed outside the pages that do not
    // capture the themes of a page (see _NavScope): their links resolve at
    // the root
    return _NavScope(
      target: _target,
      child: ValueListenableBuilder(
        valueListenable: _mapper.pages,
        builder: (context, pages, _) {
          if (pages.isEmpty) {
            // Flutter's Navigator fails on an empty list, without a word
            // on where it came from
            assert(() {
              final root = _mapper._entries.map((entry) => entry.runtimeType);
              throw FlutterError.fromParts([
                ErrorSummary('fdr: ${_target._description} shows no page.'),
                ErrorDescription(
                  'The build of ${root.join(', ')} and its child navigators '
                  'returned no page. A navigator tree has to show at least '
                  'one.',
                ),
                ErrorHint(
                  'Check for a collection-if without a page below it, and '
                  'for child navigators that can be empty.',
                ),
              ]);
            }());
            return const SizedBox.shrink();
          }
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

  void dispose() {
    _disposed = true;
    _mapper.dispose();
  }
}
