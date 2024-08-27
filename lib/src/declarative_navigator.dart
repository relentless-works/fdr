// ignore_for_file: unused_element

import 'package:fdr/src/navigatable_to_page_mapper.dart';
import 'package:fdr/src/pages/cupertino_page.dart';
import 'package:fdr/src/pages/material_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class DeclarativeNavigator extends StatefulWidget {
  final DeclarativeNavigatable navigator;
  const DeclarativeNavigator({
    super.key,
    required this.navigator,
  });

  static Widget managing({
    required ValueGetter<DeclarativeNavigatable> navigatorFactory,
  }) {
    return _ManagingDeclarativeNavigator(
      navigatorFactory: navigatorFactory,
    );
  }

  @override
  State<DeclarativeNavigator> createState() => _DeclarativeNavigatorState();
}

class _DeclarativeNavigatorState extends State<DeclarativeNavigator> {
  late final NavigatableToPageMapper _pageMapper;

  @override
  void initState() {
    super.initState();

    final navigator = widget.navigator;

    _pageMapper = NavigatableToPageMapper()..updatePages([navigator]);
  }

  @override
  void didUpdateWidget(covariant DeclarativeNavigator oldWidget) {
    super.didUpdateWidget(oldWidget);

    final navigator = widget.navigator;
    final oldNavigator = oldWidget.navigator;

    if (navigator != oldNavigator) {
      _pageMapper.updatePages([navigator]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _pageMapper.pages,
      builder: (context, pages, _) {
        return Navigator(
          pages: pages.map((n) => n.page).toList(),
          onDidRemovePage: (page) {
            debugPrint('onPopPage: $page');
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _pageMapper.dispose();

    super.dispose();
  }
}

class _ManagingDeclarativeNavigator extends StatefulWidget {
  const _ManagingDeclarativeNavigator({
    super.key,
    required this.navigatorFactory,
  });

  final ValueGetter<DeclarativeNavigatable> navigatorFactory;

  @override
  State<_ManagingDeclarativeNavigator> createState() =>
      __ManagingDeclarativeNavigatorState();
}

class __ManagingDeclarativeNavigatorState
    extends State<_ManagingDeclarativeNavigator> {
  late final DeclarativeNavigatable navigator;

  @override
  void initState() {
    super.initState();

    navigator = widget.navigatorFactory();
  }

  @override
  Widget build(BuildContext context) {
    return DeclarativeNavigator(
      navigator: navigator,
    );
  }

  @override
  void dispose() {
    final navigator = this.navigator;

    switch (navigator) {
      case StatefulNavigator():
        break;
      case DeclarativeNavigatablePage():
        break;
      case NavigatableSource():
        // TODO: Find better interface for when to cleanup
        // Maybe the widget should receive a `dispose` callback parameter?
        if (navigator is MappedNavigatableSource) {
          navigator.dispose();
        }
    }

    super.dispose();
  }
}

sealed class DeclarativeNavigatable {}

typedef PageBuilder = Page<Object?> Function(VoidCallback? onPop);

abstract class StatefulNavigator implements DeclarativeNavigatable {
  StatefulNavigatorState createState();
}

extension on StatefulNavigator {
  StatefulNavigator _wrapWithPoppable({VoidCallback? onPop}) {
    return PoppableStatefulNavigator(this, onPop: onPop);
  }
}

class PoppableStatefulNavigator implements StatefulNavigator {
  PoppableStatefulNavigator(
    this.navigator, {
    this.onPop,
  });

  final StatefulNavigator navigator;
  final VoidCallback? onPop;

  @override
  StatefulNavigatorState<StatefulNavigator> createState() {
    return navigator.createState();
  }
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
  }

  @mustCallSuper
  void didUpdateNavigator(covariant T oldNavigator) {}

  // todo: ignore while updating
  void setState(void Function() fn) {
    fn();

    updatePages();
  }

  void updatePages() {
    _pageMapper.updatePages(build());
  }

  List<DeclarativeNavigatable> build();

  @mustCallSuper
  void dispose() {
    _pageMapper.dispose();
  }

  bool isForNavigator(StatefulNavigator item) {
    return item is T;
  }
}

class DeclarativeNavigatablePage implements DeclarativeNavigatable {
  DeclarativeNavigatablePage({
    required PageBuilder builder,
    required this.onPop,
  })  : _builder = builder,
        page = builder(onPop);

  final PageBuilder _builder;

  final Page<Object?> page;

  final VoidCallback? onPop;
}

extension Poppable on DeclarativeNavigatable {
  DeclarativeNavigatable poppable({required VoidCallback? onPop}) {
    final self = this;

    return switch (self) {
      DeclarativeNavigatablePage() => DeclarativeNavigatablePage(
          builder: self._builder,
          onPop: onPop,
        ),
      // TODO(tp): Use "pipe trick" to retain original type on wrapper?
      NavigatableSource() => _PoppableNavigatableSourceWrapper(
          self,
          onPop,
        ),
      StatefulNavigator() => self._wrapWithPoppable(onPop: onPop),
    };
  }
}

class _PoppableNavigatableSourceWrapper implements NavigatableSource {
  _PoppableNavigatableSourceWrapper(
    this._navigatableSource,
    this.onPop,
  ) {
    _navigatableSource.pages.addListener(_updatePages);
    _updatePages();
  }

  final NavigatableSource _navigatableSource;
  final VoidCallback? onPop;

  final _pages = ValueNotifier<List<DeclarativeNavigatablePage>>([]);

  @override
  ValueListenable<List<DeclarativeNavigatablePage>> get pages => _pages;

  void _updatePages() {
    final pages = _navigatableSource.pages.value;

    _pages.value = [
      DeclarativeNavigatablePage(
        builder: pages.first._builder,
        // TODO(tp): What about the underlying onpop, if any? (though unlikely makes sense)
        onPop: onPop,
      ),
      ...pages.skip(1),
    ];
  }

  // TODO(tp): Ensure invocation
  void dispose() {
    _navigatableSource.pages.removeListener(_updatePages);
  }
}

extension DeclarativeNavigatableFromWidget on Widget {
  DeclarativeNavigatablePage page({
    /// Provide `null` if the page should not be poppable
    required VoidCallback? onPop,
  }) {
    return DeclarativeNavigatablePage(
      builder: (onPop) => defaultTargetPlatform == TargetPlatform.android
          ? FDRMaterialPage(
              child: this,
              canPop: onPop != null,
              onPopInvoked: (didPop, _) {
                if (didPop) {
                  // When the route was popped, it had to be pop-able (`canPop = true`),
                  // such that there is a callback to update the state to reflect its absence
                  onPop!();
                }
              },
            )
          : FDRCupertinoPage(
              child: this,
              canPop: onPop != null,
              onPopInvoked: (didPop, _) {
                if (didPop) {
                  // When the route was popped, it had to be pop-able (`canPop = true`),
                  // such that there is a callback to update the state to reflect its absence
                  onPop!();
                }
              },
            ),
      onPop: onPop,
    );
  }

  DeclarativeNavigatablePage popup({
    /// Provide `null` if the model should not be poppable
    required VoidCallback? onPop,
  }) {
    return DeclarativeNavigatablePage(
      builder: (onPop) => _CupertinoModalPopupPage(child: this),
      onPop: onPop,
    );
  }
}

class _CupertinoModalPopupPage<T> extends Page<T> {
  const _CupertinoModalPopupPage({
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
    required this.child,
  });

  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) {
    return CupertinoModalPopupRoute(
      settings: this,
      barrierDismissible: true, // TODO(tp): Adapt
      barrierColor: Colors.transparent,
      builder: (context) => child,
    );
  }
}

abstract class NavigatableSource implements DeclarativeNavigatable {
  ValueListenable<List<DeclarativeNavigatablePage>> get pages;
}

abstract class MappedNavigatableSource<T> implements NavigatableSource {
  MappedNavigatableSource({
    required T initialState,
  }) : _state = initialState {
    _pageMapper.updatePages(build());
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

    _pageMapper.updatePages(build());
  }

  @override
  ValueListenable<List<DeclarativeNavigatablePage>> get pages =>
      _pageMapper.pages;

  @protected
  List<DeclarativeNavigatable> build();

  @mustCallSuper
  void dispose() {
    _pageMapper.dispose();
  }
}
