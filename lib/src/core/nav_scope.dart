part of 'core.dart';

/// Where links resolve and routes are lifted to the root: a navigator state,
/// or the host above the root navigator.
abstract interface class _LinkTarget {
  _LinkTarget? get _parentTarget;

  RoutingScope get _routing;

  bool _accepts(Object route);

  /// [route], of this target's route type, as a route of the root.
  Object? _toRoot(Object? route);

  /// Identity of a page with [route] (this target's route type).
  String? _routeKeyOf(Object route);

  String get _description;
}

/// Above the root navigator: the router (route type [R]) or a
/// [DeclarativeNavigator] (route type `Never`, no URLs).
final class _HostTarget<R> implements _LinkTarget {
  _HostTarget(this._routing, this._description);

  @override
  final RoutingScope _routing;

  @override
  final String _description;

  /// For a [DeclarativeNavigator] inside a page of another navigator tree:
  /// links of that tree's route types resolve there.
  @override
  _LinkTarget? _parentTarget;

  @override
  bool _accepts(Object route) => route is R;

  @override
  Object? _toRoot(Object? route) => route;

  @override
  String? _routeKeyOf(Object route) => switch (route) {
    Url() => route.path,
    NavRoute() => route.toUrl().path,
    _ => null,
  };
}

/// Tells the widgets of a page which navigator built it, for [RouteLink].
class _NavScope extends InheritedWidget {
  const _NavScope({required this.target, required super.child});

  final _LinkTarget target;

  // rebuilt only when the owning navigator rebuilds, which is when the
  // parents' `at` (and with it a link's URL) can change
  @override
  bool updateShouldNotify(_NavScope oldWidget) => true;

  /// The nearest navigator whose route type [route] belongs to.
  static _LinkTarget targetFor(BuildContext context, NavRoute route) {
    final scope = context.dependOnInheritedWidgetOfExactType<_NavScope>();
    final seen = <String>[];
    for (var target = scope?.target; target != null;) {
      if (target._accepts(route)) return target;
      seen.add(target._description);
      target = target._parentTarget;
    }
    throw FlutterError.fromParts([
      ErrorSummary('No navigator for ${route.runtimeType} above this link.'),
      ErrorDescription(
        scope == null
            ? 'The link is not inside a page built by fdr.'
            : 'Navigators above it, nearest first: ${seen.join(', ')}.',
      ),
      ErrorHint(
        'A link takes a route of the navigator that shows it, or of one of '
        'its parents.',
      ),
    ]);
  }
}
