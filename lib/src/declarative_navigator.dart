import 'package:fdr/fdr.dart';
import 'package:fdr/src/navigatable_to_page_mapper.dart';
import 'package:flutter/widgets.dart';

class DeclarativeNavigator extends StatefulWidget {
  final DeclarativeNavigatable navigator;
  const DeclarativeNavigator({
    super.key,
    required this.navigator,
  });

  static final _hotReload = ChangeNotifier();
  static Listenable get hotReload => _hotReload;

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
  void reassemble() {
    super.reassemble();

    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    DeclarativeNavigator._hotReload.notifyListeners();
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
