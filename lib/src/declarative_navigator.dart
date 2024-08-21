// ignore_for_file: unused_element

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
  @override
  void initState() {
    super.initState();

    final navigator = widget.navigator;

    if (navigator is NavigatableSource) {
      navigator.pages.addListener(_handleChange);
    }
  }

  @override
  void didUpdateWidget(covariant DeclarativeNavigator oldWidget) {
    super.didUpdateWidget(oldWidget);

    final navigator = widget.navigator;
    final oldNavigator = oldWidget.navigator;

    if (navigator != oldNavigator) {
      if (oldNavigator is NavigatableSource) {
        oldNavigator.pages.removeListener(_handleChange);
      }

      if (navigator is NavigatableSource) {
        navigator.pages.addListener(_handleChange);
      }
    }
  }

  void _handleChange() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final navigator = widget.navigator;

    final pageNavigatables = switch (navigator) {
      DeclarativeNavigatablePage() => [navigator],
      // widget is already subscribed for updates
      NavigatableSource() => navigator.pages.value,
    };

    return Navigator(
      pages: pageNavigatables.map((n) => n.page).toList(),
      onDidRemovePage: (page) {
        debugPrint('onPopPage: $page');
      },
    );
  }

  @override
  void dispose() {
    final navigator = widget.navigator;

    if (navigator is NavigatableSource) {
      navigator.pages.removeListener(_handleChange);
    }

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
}

sealed class DeclarativeNavigatable {}

typedef PageBuilder = Page<Object?> Function(VoidCallback? onPop);

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

extension Poppable on NavigatableSource {
  NavigatableSource poppable({required VoidCallback? onPop}) {
    return _PoppableNavigatableSourceWrapper(this, onPop);
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
  MappedNavigatableSource({required T initialState}) : _state = initialState {
    _pages = ValueNotifier([]);
    _buildPages();
  }

  T _state;

  @protected
  T get state {
    return _state;
  }

  final _childNavigatableSources = <NavigatableSource>[];

  @protected
  set state(T value) {
    _state = value;

    _buildPages();
  }

  // TODO(tp): Don't build (for child) while building (self)
  void _buildPages() {
    final description = build();

    for (final n in _childNavigatableSources) {
      n.pages.removeListener(_buildPages);
    }

    _childNavigatableSources.clear();

    final pages = <DeclarativeNavigatablePage>[];

    for (final item in description) {
      switch (item) {
        case DeclarativeNavigatablePage():
          pages.add(item);

        case NavigatableSource():
          _childNavigatableSources.add(item);

          item.pages.addListener(_buildPages);

          pages.addAll(item.pages.value);
      }
    }

    _pages.value = pages;
  }

  late final ValueNotifier<List<DeclarativeNavigatablePage>> _pages;

  @override
  ValueListenable<List<DeclarativeNavigatablePage>> get pages => _pages;

  @protected
  List<DeclarativeNavigatable> build();

  @mustCallSuper
  void dispose() {
    for (final n in _childNavigatableSources) {
      n.pages.removeListener(_buildPages);
    }
  }
}
