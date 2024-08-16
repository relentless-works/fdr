import 'package:fdr/src/pages/fdr_page.dart';
import 'package:flutter/cupertino.dart';

/// Fork of Flutter's default `CupertinoPage` with a fix applied to the `PageRoute` it creates,
/// which now forwards the `Page`'s `canPop` property, also as `impliesAppBarDismissal` (such that the back button can be dynamically updated).
class FDRCupertinoPage<T> extends CupertinoPage<T> implements FDRPage {
  const FDRCupertinoPage({
    required super.child,
    super.canPop,
    super.onPopInvoked,
  });

  @override
  Route<T> createRoute(BuildContext context) {
    return _PageBasedCupertinoPageRoute<T>(
        page: this, allowSnapshotting: allowSnapshotting);
  }
}

class _PageBasedCupertinoPageRoute<T> extends PageRoute<T>
    with CupertinoRouteTransitionMixin<T> {
  _PageBasedCupertinoPageRoute({
    required CupertinoPage<T> page,
    super.allowSnapshotting = true,
  }) : super(settings: page) {
    assert(opaque);
  }

  CupertinoPage<T> get _page => settings as CupertinoPage<T>;

  @override
  Widget buildContent(BuildContext context) => _page.child;

  @override
  String? get title => _page.title;

  @override
  bool get maintainState => _page.maintainState;

  @override
  bool get fullscreenDialog => _page.fullscreenDialog;

  @override
  String get debugLabel => '${super.debugLabel}(${_page.name})';

  @override
  bool get canPop => _page.canPop;

  @override
  bool get impliesAppBarDismissal => _page.canPop;
}
