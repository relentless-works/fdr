part of 'declarative_navigatable.dart';

// When implementing this class, consider whether `pages` should be updated with hot reload
abstract class NavigatableSource implements DeclarativeNavigatable {
  ValueListenable<List<DeclarativeNavigatablePage>> get pages;
}
