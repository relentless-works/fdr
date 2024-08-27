import 'package:fdr/fdr.dart';
import 'package:fdr/src/declarative_navigator.dart'
    show PoppableStatefulNavigator;
import 'package:flutter/foundation.dart';

final class NavigatableToPageMapper {
  final _pages = ValueNotifier<List<DeclarativeNavigatablePage>>([]);

  var _activeStatesByIndex = <StatefulNavigatorState?>[];
  var _navigatables = <DeclarativeNavigatable>[];

  ValueListenable<List<DeclarativeNavigatablePage>> get pages => _pages;

  void updatePages(List<DeclarativeNavigatable> navigatables) {
    final oldNavigatables = _navigatables;
    _navigatables = navigatables;

    _rebuildPages(oldNavigatables);
  }

  void _rebuildPages([
    // Only passed when we switch to a different set of navigatables (though some children might overlap)
    final List<DeclarativeNavigatable>? oldNavigatable,
  ]) {
    if (oldNavigatable != null) {
      for (final n in oldNavigatable.whereType<NavigatableSource>()) {
        n.pages.removeListener(_rebuildPages);
      }
    }

    final pages = <DeclarativeNavigatablePage>[];

    final states = List<StatefulNavigatorState?>.filled(
      _navigatables.length,
      null,
    );

    for (final (index, item) in _navigatables.indexed) {
      switch (item) {
        case DeclarativeNavigatablePage():
          pages.add(item);

        case NavigatableSource():
          item.pages.removeListener(_rebuildPages);

          pages.addAll(item.pages.value);

          item.pages.addListener(_rebuildPages);

        case StatefulNavigator():
          if (_activeStatesByIndex.length > index &&
              (item is PoppableStatefulNavigator &&
                      _activeStatesByIndex[index]
                              ?.isForNavigator(item.navigator) ==
                          true ||
                  _activeStatesByIndex[index]?.isForNavigator(item) == true)) {
            // reuse existing state object
            states[index] = _activeStatesByIndex[index];

            // prevent circular calls while updating child
            states[index]!.pages.removeListener(_rebuildPages);

            final oldNavigator = states[index]!.navigator;
            if (item is PoppableStatefulNavigator) {
              states[index]!.navigator = item.navigator;
            } else {
              states[index]!.navigator = item;
            }
            states[index]!.didUpdateNavigator(oldNavigator);
            states[index]!.updatePages();

            states[index]!.pages.addListener(_rebuildPages);

            if (item is PoppableStatefulNavigator) {
              final childPages = states[index]!.pages.value;

              final poppablePages = [
                childPages.first.poppable(onPop: item.onPop)
                    as DeclarativeNavigatablePage,
                ...childPages.skip(1),
              ];

              pages.addAll(poppablePages);
            } else {
              pages.addAll(states[index]!.pages.value);
            }

            // remove from old list, so it does not get cleaned up
            _activeStatesByIndex[index] = null;
          } else {
            states[index] = item.createState();
            if (item is PoppableStatefulNavigator) {
              states[index]!.navigator = item.navigator;
            } else {
              states[index]!.navigator = item;
            }
            states[index]!.initState();
            states[index]!.updatePages();

            states[index]!.pages.addListener(_rebuildPages);

            if (item is PoppableStatefulNavigator) {
              final childPages = states[index]!.pages.value;

              final poppablePages = [
                childPages.first.poppable(onPop: item.onPop)
                    as DeclarativeNavigatablePage,
                ...childPages.skip(1),
              ];

              pages.addAll(poppablePages);
            } else {
              pages.addAll(states[index]!.pages.value);
            }
          }
      }
    }

    for (final unusedState in _activeStatesByIndex.nonNulls) {
      unusedState.pages.removeListener(_rebuildPages);

      unusedState.dispose();
    }

    _activeStatesByIndex = states;

    _pages.value = pages;
  }

  void dispose() {
    for (final state in _activeStatesByIndex.nonNulls) {
      state.dispose();
    }

    for (final n in _navigatables.whereType<NavigatableSource>()) {
      n.pages.removeListener(_rebuildPages);
    }
  }
}
