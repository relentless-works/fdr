part of 'core.dart';

/// The Flutter page behind [NavPage] and [TabsPage].
///
/// An adaptive page chooses its route when the Navigator creates it, from the
/// platform of the surrounding [Theme] (material_ui's, which falls back to
/// `defaultTargetPlatform`): a Cupertino route (with swipe back) on iOS and
/// macOS, a Material route elsewhere. On the web it is always the Material
/// route, so the app's `pageTransitionsTheme` decides the transition.
///
/// Both routes forward [canPop] to `canPop` and `impliesAppBarDismissal`, so
/// the `AppBar` and `CupertinoNavigationBar` back buttons follow the pop
/// contract; `MaterialPage` and `CupertinoPage` ignore `Page.canPop` there.
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

/// Finishes the exit of a page that the state removes while the user drags
/// it back (the iOS swipe; Material routes have it there too).
///
/// The removal pops the route, and the next drag update stops its exit
/// animation. At the end of the gesture Flutter restarts the animation only
/// for a route that is still current, so the page stayed on screen, mounted
/// and unable to take input. Flutter's own `pop` cancels the gesture instead;
/// an update of `Navigator.pages` does not.
mixin _ExitAfterGesture on TransitionRoute<Object?> {
  ValueListenable<bool>? _gesture;

  @override
  bool didPop(Object? result) {
    final popped = super.didPop(result);
    final gesture = navigator?.userGestureInProgressNotifier;
    if (popped && _gesture == null && (gesture?.value ?? false)) {
      _gesture = gesture?..addListener(_gestureChanged);
    }
    return popped;
  }

  void _gestureChanged() {
    if (_gesture?.value ?? false) return;
    _stopListening();
    final controller = this.controller!;
    if (!controller.isAnimating && !controller.isDismissed) {
      controller.reverse();
    }
  }

  void _stopListening() {
    _gesture?.removeListener(_gestureChanged);
    _gesture = null;
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }
}

class _MaterialRoute extends PageRoute<Object?>
    with MaterialRouteTransitionMixin<Object?>, _ExitAfterGesture {
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
    with CupertinoRouteTransitionMixin<Object?>, _ExitAfterGesture {
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

/// The Flutter page behind [DialogPage]: material_ui's dialog route, also
/// without material_ui's `MaterialApp` above it.
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
    return _DialogRoute(
      context: context,
      page: this,
      barrierLabel: localizations?.modalBarrierDismissLabel ?? 'Dismiss',
    );
  }
}

/// Reads the child and the barrier from the current page, like the page
/// routes above: a rebuild hands the route a new page with the same key.
class _DialogRoute extends DialogRoute<Object?> {
  _DialogRoute({
    required super.context,
    required _DialogPage page,
    required super.barrierLabel,
  }) : super(settings: page, builder: _child);

  static Widget _child(BuildContext context) =>
      (ModalRoute.settingsOf(context)! as _DialogPage).child;

  _DialogPage get _page => settings as _DialogPage;

  @override
  bool get barrierDismissible => _page.canPop && _page.barrierDismissible;
}
