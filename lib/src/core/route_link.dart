part of 'core.dart';

/// Builds the widget a [RouteLink] makes tappable; call [open] on tap.
typedef RouteLinkBuilder = Widget Function(
  BuildContext context,
  VoidCallback open,
);

/// A link to [route], e.g. `RouteLink(route: OrderItem(3), builder: ...)`.
///
/// The route is one of the navigator that shows the link, or of one of its
/// parents; the nearest navigator of the route's type resolves it. Its URL is
/// printed by the root, through the parents' [NestedNavigator.at], the same
/// way as the address bar.
///
/// Under a router, the link is a real link: on the web, hovering shows the
/// URL, and cmd/ctrl/shift-click and the context menu open it in a new tab
/// or window. A plain tap opens the route in the app, like
/// [StatefulNavigatorState.open].
class RouteLink extends StatelessWidget {
  const RouteLink({super.key, required this.route, required this.builder});

  final NavRoute route;
  final RouteLinkBuilder builder;

  @override
  Widget build(BuildContext context) {
    final target = _NavScope.targetFor(context, route);
    final routing = target._routing;
    // lifted again on tap: the parents' `at` may have changed since
    void open() => routing.open(target._toRoot(route), HistoryAction.auto);
    final href = routing.hrefOf?.call(target._toRoot(route));
    if (href == null) return builder(context, open);
    return Link(
      // absolute, so url_launcher never pushes it to the framework itself
      // (which would bypass fdr's history); a late followLink then opens a
      // new tab instead of navigating in the app
      uri: Uri.parse(externalHref(href)),
      builder: (context, followLink) => builder(context, () {
        if (!kIsWeb || followLink == null) return open();
        switch (_modifier) {
          // the browser opens a new tab or window, if Link tells it that the
          // tap followed the link
          case _Modifier.newTab:
            unawaited(followLink());
          // ctrl-click on macOS is a right click: the context menu
          case _Modifier.contextMenu:
            return;
          case null:
            open();
        }
      }),
    );
  }

  static _Modifier? get _modifier {
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed &&
        defaultTargetPlatform == TargetPlatform.macOS) {
      return _Modifier.contextMenu;
    }
    if (keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        keyboard.isShiftPressed) {
      return _Modifier.newTab;
    }
    // alt-click would download the page: opened in the app instead
    return null;
  }
}

enum _Modifier { newTab, contextMenu }
