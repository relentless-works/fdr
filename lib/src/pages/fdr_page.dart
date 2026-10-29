import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The page behind `.page()`.
///
/// Its route is chosen when the Navigator creates it, from the platform of
/// the surrounding [Theme]: a Cupertino route (with swipe back) on iOS and
/// macOS, a Material route elsewhere. On the web it is always the Material
/// route, so the app's `pageTransitionsTheme` decides the transition.
///
/// Both routes forward [canPop] to `canPop` and `impliesAppBarDismissal`, so
/// the `AppBar` and `CupertinoNavigationBar` back buttons follow the pop
/// contract; Flutter's own page routes ignore `Page.canPop` there.
class FDRPage<T> extends Page<T> {
  const FDRPage({
    super.key,
    super.name,
    super.restorationId,
    super.canPop,
    required this.child,
    this.title,
    this.maintainState = true,
    this.fullscreenDialog = false,
  });

  final Widget child;

  /// The Cupertino navigation bar's title and the next page's back label.
  final String? title;

  final bool maintainState;
  final bool fullscreenDialog;

  @override
  Route<T> createRoute(BuildContext context) {
    final platform = Theme.of(context).platform;
    final cupertino =
        !kIsWeb &&
        (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS);
    return cupertino
        ? _FDRCupertinoRoute<T>(page: this)
        : _FDRMaterialRoute<T>(page: this);
  }
}

class _FDRMaterialRoute<T> extends PageRoute<T>
    with MaterialRouteTransitionMixin<T> {
  _FDRMaterialRoute({required FDRPage<T> page}) : super(settings: page);

  FDRPage<T> get _page => settings as FDRPage<T>;

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

class _FDRCupertinoRoute<T> extends PageRoute<T>
    with CupertinoRouteTransitionMixin<T> {
  _FDRCupertinoRoute({required FDRPage<T> page}) : super(settings: page);

  FDRPage<T> get _page => settings as FDRPage<T>;

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
