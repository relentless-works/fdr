part of 'core.dart';

/// A child navigator whose routes ([C]) are part of the parent's route type
/// ([P]). [embed] lifts a child route into the parent's (state -> URL),
/// [unwrap] extracts the child's part of an incoming parent route, or `null`
/// if the parent route does not address this child (URL -> state).
///
/// [initialRoute] is applied when the child's state is created without an
/// incoming route addressing it: the way to hand a pending route to a child
/// that only exists once something has loaded.
final class MountedNavigatable<P, C> implements DeclarativeNavigatable<P> {
  MountedNavigatable(
    this.child, {
    required this.embed,
    required this.unwrap,
    this.initialRoute,
  });

  final StatefulNavigator<C> child;
  final P Function(C route) embed;
  final C? Function(P route) unwrap;
  final C? initialRoute;

  // The mapper only sees `MountedNavigatable<Object?, Object?>`; reading the
  // function-typed fields through that view fails Dart's covariance check
  // (`(HomeRoute) => HomeAt` is not a `(Object?) => Object?`), so the calls
  // are made here, where P and C are known.
  Object? embedUntyped(Object? route) => embed(route as C);

  Object? unwrapUntyped(Object? route) => unwrap(route as P);
}

extension MountNavigator<C> on StatefulNavigator<C> {
  DeclarativeNavigatable<P> mount<P>({
    required P Function(C route) embed,
    required C? Function(P route) unwrap,
    C? initialRoute,
  }) {
    return MountedNavigatable<P, C>(
      this,
      embed: embed,
      unwrap: unwrap,
      initialRoute: initialRoute,
    );
  }
}

/// The embedding of a child navigator's route type [C] into its parent's [P],
/// declared once and used twice: by the parent's codec (`codec.embedded(lens)`)
/// and by the parent's build list (`child.mountWith(lens)`), so the URL layer
/// and the reconciliation cannot disagree about which parent route addresses
/// which child.
final class RouteLens<P, C> {
  const RouteLens({required this.embed, required this.unwrap});

  final P Function(C route) embed;
  final C? Function(P route) unwrap;
}

extension MountNavigatorWithLens<C> on StatefulNavigator<C> {
  DeclarativeNavigatable<P> mountWith<P>(
    RouteLens<P, C> lens, {
    C? initialRoute,
  }) {
    return MountedNavigatable<P, C>(
      this,
      embed: lens.embed,
      unwrap: lens.unwrap,
      initialRoute: initialRoute,
    );
  }
}
