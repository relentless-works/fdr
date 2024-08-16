import 'package:fdr/src/pages/fdr_page.dart';
import 'package:flutter/material.dart';

/// Fork of Flutter's default `MaterialPage` with a fix applied to the `PageRoute` it creates,
/// which now forwards the `Page`'s `canPop` property, also as `impliesAppBarDismissal` (such that the back button can be dynamically updated).
class FDRMaterialPage<T> extends MaterialPage<T> implements FDRPage {
  const FDRMaterialPage({
    required super.child,
    super.canPop,
    super.onPopInvoked,
  });

  @override
  Route<T> createRoute(BuildContext context) {
    return _PageBasedMaterialPageRoute<T>(
        page: this, allowSnapshotting: allowSnapshotting);
  }
}

class _PageBasedMaterialPageRoute<T> extends PageRoute<T>
    with MaterialRouteTransitionMixin<T> {
  _PageBasedMaterialPageRoute({
    required MaterialPage<T> page,
    super.allowSnapshotting,
  }) : super(settings: page) {
    assert(opaque);
  }

  MaterialPage<T> get _page => settings as MaterialPage<T>;

  @override
  Widget buildContent(BuildContext context) {
    return _page.child;
  }

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
