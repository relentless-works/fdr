import 'package:flutter/material.dart';

/// Fork of Flutter's `MaterialPage` whose route forwards the page's `canPop`
/// as `canPop` and `impliesAppBarDismissal`, so the AppBar back button follows
/// the declarative pop contract (still needed on Flutter 3.47.5).
class FDRMaterialPage<T> extends MaterialPage<T> {
  const FDRMaterialPage({
    super.key,
    super.name,
    super.restorationId,
    required super.child,
    super.canPop,
    super.onPopInvoked,
  });

  @override
  Route<T> createRoute(BuildContext context) {
    return _PageBasedMaterialPageRoute<T>(
      page: this,
      allowSnapshotting: allowSnapshotting,
    );
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
  Widget buildContent(BuildContext context) => _page.child;

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
