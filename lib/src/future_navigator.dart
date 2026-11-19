import 'dart:async';

import 'package:flutter/widgets.dart';

import 'core/core.dart';

/// Builds the navigator that shows the loaded [data]. [reload] loads again
/// while the current data stays on screen; it completes with the error if
/// the load fails or the child built from the new data throws, which keeps
/// the current data, and normally if a later reload superseded it.
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
///   onPop: () => setState(() {
///     id = null;
///     orderRoute = null;
///   }),
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
/// The route it is given is the [NestedNavigator.route] around it, so open
/// it with one: `open(OrderAt(id))` or a [RouteLink], which set `orderRoute`
/// through `applyRoute`, or a `setState` that sets `orderRoute` with `id`.
/// Without a route, its loading and error pages have no URL: the URL stays
/// at the page below, and the loaded child's first page adds the entry.
///
/// What is loaded is identified by [key]: a different key is a different
/// navigator, so its state starts over and a load still in flight for the
/// old key is ignored. The loaded value lives as long as this navigator's
/// state; [onDispose] releases it (also a value from a superseded load)
/// once it is no longer shown, and each instance once: a reload that
/// returns the instance on screen does not release it.
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
  /// once, without calling [load]. It stays the app's: [onDispose] does not
  /// release it.
  final T? initialData;

  /// Releases a value [load] returned, once it is no longer shown: when a
  /// reload replaces it, when this navigator is disposed, or for a
  /// superseded load once the newest load completes, which may return the
  /// same instance. Each instance once; not called for [initialData].
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
  // whether _data came from load: initialData is not released
  bool _loaded = false;
  Object? _error;
  R? _route;
  int _generation = 0;
  // whether the newest load is in flight: a superseded load's value waits
  // for it, as both may return one instance (requests deduplicated)
  bool _loading = false;
  final List<T> _superseded = [];
  // the loads in flight, and what was released while any was or since
  // dispose: a load that completes later does not release it again
  int _inFlight = 0;
  final List<T> _released = [];

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
    _loading = true;
    _inFlight++;
    try {
      await _complete(generation);
    } finally {
      if (--_inFlight == 0 && mounted) _released.clear();
    }
  }

  Future<void> _complete(int generation) async {
    final T data;
    try {
      data = await navigator.load();
    } on Object catch (error) {
      if (!mounted || generation != _generation) return;
      _loading = false;
      _superseded.forEach(_release);
      _superseded.clear();
      // a failed reload keeps the current data on screen
      if (_hasData) rethrow;
      setState(() => _error = error);
      return;
    }
    // a load may return the value already shown (a cached view model):
    // that one is released when it is no longer shown, once
    if (!mounted || generation != _generation) {
      if (_hasData && identical(data, _data)) return;
      if (mounted && _loading) {
        _superseded.add(data);
      } else {
        _release(data);
      }
      return;
    }
    final hadData = _hasData;
    final previous = hadData ? _data : null;
    final loaded = _loaded;
    _loading = false;
    try {
      setState(() {
        _data = data;
        _hasData = true;
        _loaded = true;
        _error = null;
      });
    } on Object {
      // the child built from the new data threw, so the navigators still
      // show the data before it: a failed reload, which keeps that data
      if (hadData && mounted) {
        _data = previous as T;
        _loaded = loaded;
      }
      rethrow;
    } finally {
      // the loaded values other than the one kept are no longer shown
      for (final value in [if (loaded) previous as T, data, ..._superseded]) {
        if (!identical(value, _data)) _release(value);
      }
      _superseded.clear();
    }
  }

  void _release(T value) {
    if (_released.any((other) => identical(other, value))) return;
    _released.add(value);
    navigator.onDispose?.call(value);
  }

  void _retry() {
    setState(() => _error = null);
    unawaited(_load());
  }

  @override
  List<NavEntry<R>> build() {
    if (_hasData) {
      // handed over once, to the child this build creates or addresses: a
      // child created later (another navigator for reloaded data) starts
      // at its first page, not at a deep link it never received
      final route = _route;
      _route = null;
      return [
        NestedNavigator<R, R>(
          route: route,
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
    // the children built from the data are disposed before it is released;
    // a load still in flight does not keep the superseded values
    try {
      super.dispose();
    } finally {
      _superseded.forEach(_release);
      _superseded.clear();
      if (_loaded) _release(_data);
    }
  }
}
