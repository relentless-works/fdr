part of 'declarative_navigatable.dart';

abstract class DisposableNavigatable implements DeclarativeNavigatable {
  @mustCallSuper
  void dispose();
}
