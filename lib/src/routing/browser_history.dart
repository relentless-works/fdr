import 'browser_history_stub.dart'
    if (dart.library.js_interop) 'browser_history_web.dart'
    as impl;

/// Platform hook used for in-app pops on the web (`window.history.go(-n)`).
abstract interface class BrowserHistory {
  bool get supportsTraversal;
  void go(int delta);

  /// The state the app stored in the current entry. The engine hands only
  /// the path to the framework after a reload, but the entry still holds it.
  Object? get currentState;

  /// `window.history` on the web, [NoBrowserHistory] elsewhere.
  static BrowserHistory platform() => impl.platformBrowserHistory();
}

final class NoBrowserHistory implements BrowserHistory {
  const NoBrowserHistory();

  @override
  bool get supportsTraversal => false;

  @override
  void go(int delta) {}

  @override
  Object? get currentState => null;
}
