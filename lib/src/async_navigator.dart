import 'dart:async';

import 'package:flutter/widgets.dart';

import 'core/core.dart';
import 'widget_extensions.dart';

/// Builds the navigator that shows the loaded [data]. [reload] loads again
/// while the current data stays on screen; it completes with the load's
/// error if that fails.
typedef AsyncChildBuilder<T, R> = StatefulNavigator<R> Function(
  T data,
  Future<void> Function() reload,
);

/// Loads a value and then shows the navigator built from it, so that child
/// receives a domain model (or a controller owning one) instead of an id, and
/// never deals with loading or errors of its own input.
///
/// Its route type is the child's. While loading, or after a failure, it shows
/// a [loading] or [failed] page addressed by the route it was given, so the
/// URL stays where the user is going and finishing the load adds no history
/// entry. The pending route is applied to the child before its first build,
/// which makes deep links into nested, separately loaded levels work without
/// any asynchronous route resolution.
///
/// What is loaded is identified by [key]: a different key is a different
/// navigator, so its state starts over and a load still in flight for the
/// old key is ignored. The loaded value lives as long as this navigator's
/// state; [onDispose] releases it (also a value from a superseded load).
class AsyncNavigator<T, R> extends StatefulNavigator<R> {
  const AsyncNavigator({
    required LocalKey super.key,
    required this.load,
    required this.builder,
    required this.loading,
    required this.failed,
    this.initialData,
    this.onDispose,
  });

  final Future<T> Function() load;
  final AsyncChildBuilder<T, R> builder;
  final Widget loading;
  final Widget Function(Object error, VoidCallback retry) failed;

  /// Already available data (e.g. from the list the user tapped): shown at
  /// once, without calling [load].
  final T? initialData;

  final void Function(T data)? onDispose;

  @override
  StatefulNavigatorState<AsyncNavigator<T, R>, R> createState() {
    return _AsyncNavigatorState<T, R>();
  }
}

class _AsyncNavigatorState<T, R>
    extends StatefulNavigatorState<AsyncNavigator<T, R>, R> {
  late T _data;
  bool _hasData = false;
  Object? _error;
  R? _pending;
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
  void applyRoute(R route) {
    // kept for the child created once the data is there; a child that
    // already exists gets the route from the library directly
    _pending = route;
  }

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
  List<DeclarativeNavigatable<R>> build() {
    if (_hasData) {
      return [
        navigator
            .builder(_data, _load)
            .mount<R>(
              embed: (route) => route,
              unwrap: (route) => route,
              initialRoute: _pending,
            ),
      ];
    }
    final error = _error;
    final content = error == null
        ? navigator.loading
        : navigator.failed(error, _retry);
    return [content.page<R>(onPop: null, route: _pending)];
  }

  @override
  void dispose() {
    _generation++;
    if (_hasData) navigator.onDispose?.call(_data);
    super.dispose();
  }
}
