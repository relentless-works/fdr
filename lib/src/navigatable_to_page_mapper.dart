import 'package:fdr/fdr.dart';
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

    for (final (index, outerItem) in _navigatables.indexed) {
      final (item, onPopOverwrite) = outerItem is PopOverwriteNavigatable
          ? (outerItem.child, outerItem.onPop)
          : (outerItem, null);

      switch (item) {
        case DeclarativeNavigatablePage():
          if (onPopOverwrite != null) {
            pages.add(item.withOnPop(onPop: onPopOverwrite));
          } else {
            pages.add(item);
          }

        case NavigatableSource():
          item.pages.removeListener(_rebuildPages);

          if (onPopOverwrite != null) {
            final childPages = item.pages.value;

            pages.addAll([
              childPages.first.withOnPop(onPop: onPopOverwrite),
              ...childPages.skip(1),
            ]);
          } else {
            pages.addAll(item.pages.value);
          }

          item.pages.addListener(_rebuildPages);

        case StatefulNavigator():
          if (_activeStatesByIndex.length > index &&
              _activeStatesByIndex[index]?.isForNavigator(item) == true) {
            // reuse existing state object
            states[index] = _activeStatesByIndex[index];

            // prevent circular calls while updating child
            states[index]!.pages.removeListener(_rebuildPages);

            final oldNavigator = states[index]!.navigator;
            states[index]!.navigator = item;
            states[index]!.didUpdateNavigator(oldNavigator);
            states[index]!.updatePages();

            states[index]!.pages.addListener(_rebuildPages);

            if (onPopOverwrite != null) {
              final childPages = states[index]!.pages.value;

              final poppablePages = [
                childPages.first.withOnPop(onPop: onPopOverwrite),
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
            states[index]!.navigator = item;
            states[index]!.initState();
            states[index]!.updatePages();

            states[index]!.pages.addListener(_rebuildPages);

            if (onPopOverwrite != null) {
              final childPages = states[index]!.pages.value;

              final poppablePages = [
                childPages.first.withOnPop(onPop: onPopOverwrite),
                ...childPages.skip(1),
              ];

              pages.addAll(poppablePages);
            } else {
              pages.addAll(states[index]!.pages.value);
            }
          }

        case PopOverwriteNavigatable():
          throw Exception(
            'Unexpected case, as $PopOverwriteNavigatable is unwrapped above',
          );

        case DisposableNavigatable():
          throw Exception(
            '$item only implements $DisposableNavigatable, but should implement another subtype of $DeclarativeNavigatable',
          );
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
