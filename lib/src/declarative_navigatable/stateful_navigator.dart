part of 'declarative_navigatable.dart';

abstract class StatefulNavigator implements DeclarativeNavigatable {
  StatefulNavigatorState createState();
}

abstract class StatefulNavigatorState<T extends StatefulNavigator>
    implements NavigatableSource {
  late T navigator;

  late final NavigatableToPageMapper _pageMapper;

  @override
  ValueListenable<List<DeclarativeNavigatablePage>> get pages =>
      _pageMapper.pages;

  @mustCallSuper
  void initState() {
    _pageMapper = NavigatableToPageMapper();
    DeclarativeNavigator.hotReload.addListener(updatePages);
  }

  @mustCallSuper
  void didUpdateNavigator(covariant T oldNavigator) {}

  // todo: ignore while updating
  void setState(void Function() fn) {
    fn();

    updatePages();
  }

  // Exposed so it can be triggered after `initState` and `didUpdateNavigator` ran
  // (as this can not be part of the base implementation, as the `super.*` methods are called at the beginning)
  void updatePages() {
    _pageMapper.updatePages(build());
  }

  List<DeclarativeNavigatable> build();

  @mustCallSuper
  void dispose() {
    DeclarativeNavigator.hotReload.removeListener(updatePages);
    _pageMapper.dispose();
  }

  bool isForNavigator(StatefulNavigator item) {
    return item is T;
  }
}
