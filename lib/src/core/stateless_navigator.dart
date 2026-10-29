part of 'core.dart';

/// A navigator whose pages are a pure function of its configuration; it has
/// no state of its own, so an incoming route is reflected only through the
/// configuration the parent built from it, while mounted children still get
/// their part of the route.
abstract class StatelessNavigator<R> extends StatefulNavigator<R> {
  const StatelessNavigator({super.key});

  List<DeclarativeNavigatable<R>> build();

  @override
  StatefulNavigatorState<StatefulNavigator<R>, R> createState() {
    return _StatelessNavigatorState<R>();
  }
}

class _StatelessNavigatorState<R>
    extends StatefulNavigatorState<StatelessNavigator<R>, R> {
  @override
  List<DeclarativeNavigatable<R>> build() => navigator.build();

  @override
  void applyRoute(R route) {}
}
