part of 'core.dart';

/// The Flutter page behind [NavPage] and [TabsPage].
///
/// An adaptive page chooses its route when the Navigator creates it, from the
/// platform of the surrounding [Theme]: a Cupertino route (with swipe back)
/// on iOS and macOS, a Material route elsewhere. On the web it is always the
/// Material route, so the app's `pageTransitionsTheme` decides the
/// transition.
///
/// Both routes forward [canPop] to `canPop` and `impliesAppBarDismissal`, so
/// the `AppBar` and `CupertinoNavigationBar` back buttons follow the pop
/// contract; Flutter's own page routes ignore `Page.canPop` there.
class _NavPage extends Page<Object?> {
  const _NavPage({
    super.key,
    super.canPop,
    required this.child,
    required this.style,
    this.title,
    this.maintainState = true,
    this.fullscreenDialog = false,
  });

  final Widget child;
  final _PageStyle style;
  final String? title;
  final bool maintainState;
  final bool fullscreenDialog;

  @override
  Route<Object?> createRoute(BuildContext context) {
    final cupertino = switch (style) {
      _PageStyle.material => false,
      _PageStyle.cupertino => true,
      _PageStyle.adaptive =>
        !kIsWeb &&
            switch (Theme.of(context).platform) {
              TargetPlatform.iOS || TargetPlatform.macOS => true,
              _ => false,
            },
    };
    return cupertino ? _CupertinoRoute(page: this) : _MaterialRoute(page: this);
  }
}

class _MaterialRoute extends PageRoute<Object?>
    with MaterialRouteTransitionMixin<Object?> {
  _MaterialRoute({required _NavPage page}) : super(settings: page);

  _NavPage get _page => settings as _NavPage;

  @override
  Widget buildContent(BuildContext context) => _page.child;

  @override
  bool get maintainState => _page.maintainState;

  @override
  bool get fullscreenDialog => _page.fullscreenDialog;

  @override
  String get debugLabel => '${super.debugLabel}(${_page.key})';

  @override
  bool get canPop => super.canPop && _page.canPop;

  @override
  bool get impliesAppBarDismissal =>
      super.impliesAppBarDismissal && _page.canPop;
}

class _CupertinoRoute extends PageRoute<Object?>
    with CupertinoRouteTransitionMixin<Object?> {
  _CupertinoRoute({required _NavPage page}) : super(settings: page);

  _NavPage get _page => settings as _NavPage;

  @override
  Widget buildContent(BuildContext context) => _page.child;

  @override
  String? get title => _page.title;

  @override
  bool get maintainState => _page.maintainState;

  @override
  bool get fullscreenDialog => _page.fullscreenDialog;

  @override
  String get debugLabel => '${super.debugLabel}(${_page.key})';

  @override
  bool get canPop => super.canPop && _page.canPop;

  @override
  bool get impliesAppBarDismissal =>
      super.impliesAppBarDismissal && _page.canPop;
}

/// The Flutter page behind [DialogPage]: Material's dialog route, also
/// without a `MaterialApp` above it.
class _DialogPage extends Page<Object?> {
  const _DialogPage({
    super.key,
    super.canPop,
    required this.child,
    required this.barrierDismissible,
  });

  final Widget child;
  final bool barrierDismissible;

  @override
  Route<Object?> createRoute(BuildContext context) {
    final localizations = Localizations.of<MaterialLocalizations>(
      context,
      MaterialLocalizations,
    );
    return DialogRoute<Object?>(
      context: context,
      settings: this,
      builder: (_) => child,
      barrierDismissible: canPop && barrierDismissible,
      barrierLabel: localizations?.modalBarrierDismissLabel ?? 'Dismiss',
    );
  }
}
