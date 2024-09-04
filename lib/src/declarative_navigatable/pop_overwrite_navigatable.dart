part of 'declarative_navigatable.dart';

class PopOverwriteNavigatable implements DeclarativeNavigatable {
  final DeclarativeNavigatable child;

  final VoidCallback? onPop;

  PopOverwriteNavigatable(
    DeclarativeNavigatable child, {
    this.onPop,
  }) : child = child is PopOverwriteNavigatable ? child.child : child {
    assert(child is! PopOverwriteNavigatable);
  }
}
