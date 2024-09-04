import 'package:fdr/fdr.dart';
import 'package:fdr/src/navigatable_to_page_mapper.dart';
import 'package:flutter/foundation.dart';

abstract class MappedNavigatableSource<T>
    implements NavigatableSource, DisposableNavigatable {
  MappedNavigatableSource({
    required T initialState,
  }) : _state = initialState {
    _update();

    DeclarativeNavigator.hotReload.addListener(_update);
  }

  final _pageMapper = NavigatableToPageMapper();

  T _state;

  @protected
  T get state {
    return _state;
  }

  @protected
  set state(T value) {
    _state = value;

    _update();
  }

  void _update() {
    _pageMapper.updatePages(build());
  }

  @override
  ValueListenable<List<DeclarativeNavigatablePage>> get pages =>
      _pageMapper.pages;

  @protected
  List<DeclarativeNavigatable> build();

  @override
  @mustCallSuper
  void dispose() {
    DeclarativeNavigator.hotReload.removeListener(_update);

    _pageMapper.dispose();
  }
}
