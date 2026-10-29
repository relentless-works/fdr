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

class _DeclarativeNavigatorState extends State<DeclarativeNavigator> {
  late final NavHost<Never> _host;
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    final scope = RoutingScope()
      ..openRoot = ((route, _) {
        _host.update([widget.navigator], incomingRoute: route);
      });
    _host = NavHost<Never>(scope, description: 'DeclarativeNavigator')
      ..update([widget.navigator]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _host.linkTo(context);
  }

  @override
  void reassemble() {
    super.reassemble();
    FdrHotReload.trigger();
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
    _host.dispose();
    super.dispose();
  }
}
