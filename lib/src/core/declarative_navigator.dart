part of 'core.dart';

/// Shows a navigator tree without a router: no URLs, e.g. a small app or a
/// part of a widget tree.
///
/// ```dart
/// MaterialApp(home: DeclarativeNavigator(navigator: AppNavigator()))
/// ```
class DeclarativeNavigator extends StatefulWidget {
  const DeclarativeNavigator({super.key, required this.navigator});

  final NavEntry<Object?> navigator;

  @override
  State<DeclarativeNavigator> createState() => _DeclarativeNavigatorState();
}

class _DeclarativeNavigatorState extends State<DeclarativeNavigator>
    with WidgetsBindingObserver {
  late final NavHost<Never> _host;
  final _navigatorKey = GlobalKey<NavigatorState>();
  var _observing = false;

  @override
  void initState() {
    super.initState();
    final scope = RoutingScope()
      ..openRoot = ((route, _) {
        _host.update([widget.navigator], incomingRoute: route);
      });
    // assigned before the first update: an open() in a navigator's
    // initState or build runs at its end and needs _host
    _host = NavHost<Never>(scope, description: 'DeclarativeNavigator');
    _host.update([widget.navigator]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _host.linkTo(context);
    // Outside a route (MaterialApp.builder, directly under runApp) the pop
    // handler in build has no route to register with, so system back is
    // taken from the binding. Of the route only its existence is read,
    // which `opaqueOf` does without a rebuild for each change of the route.
    final observe = ModalRoute.opaqueOf(context) == null;
    if (observe != _observing) {
      _observing = observe;
      if (observe) {
        WidgetsBinding.instance.addObserver(this);
      } else {
        WidgetsBinding.instance.removeObserver(this);
      }
    }
  }

  @override
  Future<bool> didPopRoute() async =>
      await _navigatorKey.currentState?.maybePop() ?? false;

  @override
  void reassemble() {
    super.reassemble();
    // hot reload: the update from the root rebuilds every navigator once
    _host.update([widget.navigator]);
  }

  @override
  void didUpdateWidget(covariant DeclarativeNavigator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.navigator != oldWidget.navigator) {
      _host.update([widget.navigator]);
    }
  }

  // system back pops this navigator's pages before it leaves the app (or
  // the enclosing route)
  @override
  Widget build(BuildContext context) => NavigatorPopHandler<Object?>(
    onPopWithResult: (_) => _navigatorKey.currentState?.maybePop(),
    child: _host.navigator(key: _navigatorKey),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _host.dispose();
    super.dispose();
  }
}
