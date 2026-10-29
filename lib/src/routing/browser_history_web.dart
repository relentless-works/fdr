import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'browser_history.dart';

BrowserHistory platformBrowserHistory() => const _WindowHistory();

final class _WindowHistory implements BrowserHistory {
  const _WindowHistory();

  @override
  bool get supportsTraversal => true;

  @override
  void go(int delta) => web.window.history.go(delta);

  // the engine wraps the app's state as {serialCount, state}
  @override
  Object? get currentState {
    final state = web.window.history.state.dartify();
    return state is Map ? state['state'] : null;
  }
}
