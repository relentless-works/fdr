import 'package:flutter/widgets.dart';

import 'core/core.dart';

/// Renders a navigator tree without a Router (no URL); kept for embedding a
/// declarative stack inside an ordinary widget tree.
class DeclarativeNavigator extends StatefulWidget {
  const DeclarativeNavigator({super.key, required this.navigator});

  final DeclarativeNavigatable<Object?> navigator;

  @override
  State<DeclarativeNavigator> createState() => _DeclarativeNavigatorState();
}

class _DeclarativeNavigatorState extends State<DeclarativeNavigator> {
  late final NavigatableToPageMapper _pageMapper;

  @override
  void initState() {
    super.initState();
    _pageMapper = NavigatableToPageMapper(RoutingScope())
      ..updatePages([widget.navigator]);
  }

  @override
  void reassemble() {
    super.reassemble();
    FdrHotReload.trigger();
  }

  @override
  void didUpdateWidget(covariant DeclarativeNavigator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.navigator != oldWidget.navigator) {
      _pageMapper.updatePages([widget.navigator]);
    }
  }

  List<KeyedPage> _keyed() => keyPages(_pageMapper.pages.value, (_) => null);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _pageMapper.pages,
      builder: (context, pages, _) {
        return Navigator(
          pages: [
            for (final (i, (key, page)) in _keyed().indexed)
              page.buildPage(defaultKey: key, forceCanPop: i == 0),
          ],
          onDidRemovePage: (page) => applyPopContract(page, _keyed),
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
