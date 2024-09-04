part of 'declarative_navigatable.dart';

class DeclarativeNavigatablePage implements DeclarativeNavigatable {
  DeclarativeNavigatablePage({
    required PageBuilder builder,
    required this.onPop,
  })  : _builder = builder,
        page = builder(onPop);

  final PageBuilder _builder;

  final Page<Object?> page;

  final VoidCallback? onPop;

  DeclarativeNavigatablePage withOnPop({required VoidCallback? onPop}) {
    return DeclarativeNavigatablePage(
      builder: _builder,
      onPop: onPop,
    );
  }
}

typedef PageBuilder = Page<Object?> Function(VoidCallback? onPop);
