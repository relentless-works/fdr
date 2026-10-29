part of 'core.dart';

final class PopOverwriteNavigatable<R> implements DeclarativeNavigatable<R> {
  PopOverwriteNavigatable(DeclarativeNavigatable<R> child, {this.onPop})
    : child = child is PopOverwriteNavigatable<R> ? child.child : child;

  final DeclarativeNavigatable<R> child;
  final VoidCallback? onPop;
}
