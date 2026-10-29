part of 'core.dart';

/// An item of a navigator's [StatefulNavigatorState.build] list: a page or a
/// child navigator.
///
/// [R] is the route type of the navigator whose list the item belongs to: the
/// type a page can be addressed by ([DeclarativeNavigatablePage.route]) and
/// the type a mounted child's routes are embedded into ([MountedNavigatable]).
/// Items without a URL use `Never`, which fits into every list.
sealed class DeclarativeNavigatable<R> {}

extension Poppable<R> on DeclarativeNavigatable<R> {
  /// Lets the parent decide what popping the first page of this item does.
  DeclarativeNavigatable<R> poppable({required VoidCallback? onPop}) {
    return PopOverwriteNavigatable<R>(this, onPop: onPop);
  }
}
