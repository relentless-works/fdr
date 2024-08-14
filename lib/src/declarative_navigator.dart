// ignore_for_file: unused_element

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
      onPopPage: (route, result) {
        debugPrint('onPopPage: $route $result');

        if (pageNavigatables.last.onPop != null) {
          pageNavigatables.last.onPop!();

          // pop will not yet be completed on edge-swipe (as the animation still runs), so we can not yet return `true`
          return false;
        }

        return false;
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

class DeclarativeNavigatablePage implements DeclarativeNavigatable {
  DeclarativeNavigatablePage({
    required this.page,
    this.onPop,
  });

  final Page page;

  // TODO(tp): Make final, and then provide better creators
  VoidCallback? onPop;
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
        page: pages.first.page,
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

extension DeclarativeNavigatableFromPage on Page {
  DeclarativeNavigatablePage get navigatable {
    return DeclarativeNavigatablePage(page: this);
  }
}

extension DeclarativeNavigatableFromWidget on Widget {
  DeclarativeNavigatablePage get page {
    return CupertinoPage(child: this).navigatable;
  }

  DeclarativeNavigatablePage get popup {
    return _CupertinoModalPopupPage(child: this).navigatable;
  }
}

class _CupertinoModalPopupPage extends Page {
  const _CupertinoModalPopupPage({
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
    required this.child,
  });
  final Widget child;

  @override
  Route createRoute(BuildContext context) {
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
    final description = build(state);

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

  // _pages.value = build(_state);

  late final ValueNotifier<List<DeclarativeNavigatablePage>> _pages;

  @override
  ValueListenable<List<DeclarativeNavigatablePage>> get pages => _pages;

  // TODO(tp): Find a better name for `state` to avoid confusion between state and this.state (former should never be assigned)
  // We might be able to do without the state, but then we have to use the usual `final state = this.state` at the beginning of the function for matchin (or use more `switch`…)
  @protected
  List<DeclarativeNavigatable> build(final T state);

  @mustCallSuper
  void dispose() {
    for (final n in _childNavigatableSources) {
      n.pages.removeListener(_buildPages);
    }
  }
}
