import 'package:flutter/cupertino.dart';

/// Fork of Flutter's `CupertinoPage`, see `FDRMaterialPage`.
class FDRCupertinoPage<T> extends CupertinoPage<T> {
  const FDRCupertinoPage({
    super.key,
    super.name,
    super.restorationId,
    required super.child,
    super.canPop,
    super.onPopInvoked,
  });

  @override
  Route<T> createRoute(BuildContext context) {
    return _PageBasedCupertinoPageRoute<T>(
      page: this,
      allowSnapshotting: allowSnapshotting,
    );
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
  bool get canPop => super.canPop && _page.canPop;

  @override
  bool get impliesAppBarDismissal =>
      super.impliesAppBarDismissal && _page.canPop;
}
