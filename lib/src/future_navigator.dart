import 'dart:async';

import 'package:flutter/widgets.dart';

import 'core/core.dart';

/// Builds the navigator that shows the loaded [data]. [reload] loads again
/// while the current data stays on screen; it completes with the load's
/// error if that fails.
typedef FutureChildBuilder<T, R> = StatefulNavigator<R> Function(
  T data,
  Future<void> Function() reload,
);

/// Loads a value and then shows the navigator built from it, so that child
/// receives a domain model (or a view model owning one) instead of an id,
/// and never deals with loading or errors of its own input.
///
/// ```dart
/// NestedNavigator(
///   at: (route) => OrderAt(id, route),
///   route: orderRoute,
///   onPop: () => setState(() => id = null),
///   child: FutureNavigator(
///     key: ValueKey(id),
///     load: () => api.order(id),
///     loading: const LoadingPage(),
///     error: (error, retry) => ErrorPage(error: error, retry: retry),
///     builder: (order, reload) => OrderNavigator(order: order),
///   ),
/// )
/// ```
///
/// Its route type is the child's. While loading, or after a failure, it shows
/// a [loading] or [error] page addressed by the route it was given, so the
/// URL stays where the user is going and finishing the load adds no history
/// entry. That route is handed to the child when it is created, which makes
/// deep links into nested, separately loaded levels work.
///
/// What is loaded is identified by [key]: a different key is a different
/// navigator, so its state starts over and a load still in flight for the
/// old key is ignored. The loaded value lives as long as this navigator's
/// state; [onDispose] releases it (also a value from a superseded load).
///
/// Put it inside a [NestedNavigator] with an `onPop`, as above, so its
/// loading and error pages can be left with back.
class FutureNavigator<T, R> extends StatefulNavigator<R> {
  const FutureNavigator({
    required LocalKey super.key,
    required this.load,
    required this.builder,
    required this.loading,
    required this.error,
    this.initialData,
    this.onDispose,
  });

  final Future<T> Function() load;
  final FutureChildBuilder<T, R> builder;
  final Widget loading;
  final Widget Function(Object error, VoidCallback retry) error;

  /// Already available data (e.g. from the list the user tapped): shown at
  /// once, without calling [load].
  final T? initialData;

  final void Function(T data)? onDispose;

  @override
  StatefulNavigatorState<FutureNavigator<T, R>, R> createState() {
    return _FutureNavigatorState<T, R>();
  }
}

class _FutureNavigatorState<T, R>
    extends StatefulNavigatorState<FutureNavigator<T, R>, R> {
  late T _data;
  bool _hasData = false;
  Object? _error;
  R? _route;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    final initial = navigator.initialData;
    if (initial != null) {
      _data = initial;
      _hasData = true;
    } else {
      unawaited(_load());
    }
  }

  @override
  void applyRoute(R route) => _route = route;

  Future<void> _load() async {
    final generation = ++_generation;
    final T data;
    try {
      data = await navigator.load();
    } on Object catch (error) {
      if (!mounted || generation != _generation) return;
      // a failed reload keeps the current data on screen
      if (_hasData) rethrow;
      setState(() => _error = error);
      return;
    }
    if (!mounted || generation != _generation) {
      navigator.onDispose?.call(data);
      return;
    }
    final previous = _hasData ? _data : null;
    setState(() {
      _data = data;
      _hasData = true;
      _error = null;
    });
    if (previous != null) navigator.onDispose?.call(previous);
  }

  void _retry() {
    setState(() => _error = null);
    unawaited(_load());
  }

  @override
  List<NavEntry<R>> build() {
    if (_hasData) {
      return [
        NestedNavigator<R, R>(
          route: _route,
          child: navigator.builder(_data, _load),
        ),
      ];
    }
    final error = _error;
    return [
      NavPage<R>(
        route: _route,
        child: error == null
            ? navigator.loading
            : navigator.error(error, _retry),
      ),
    ];
  }

  @override
  void dispose() {
    _generation++;
    // the children built from the data are disposed before it is released
    super.dispose();
    if (_hasData) navigator.onDispose?.call(_data);
  }
}
