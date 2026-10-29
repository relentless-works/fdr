import 'browser_history_stub.dart'
    if (dart.library.js_interop) 'browser_history_web.dart'
    as impl;

/// Platform hook used for in-app pops on the web (`window.history.go(-n)`).
abstract interface class BrowserHistory {
  bool get supportsTraversal;
  void go(int delta);

  /// `window.history` on the web, [NoBrowserHistory] elsewhere.
  static BrowserHistory platform() => impl.platformBrowserHistory();
}

final class NoBrowserHistory implements BrowserHistory {
  const NoBrowserHistory();

  @override
  bool get supportsTraversal => false;

  @override
  void go(int delta) {}
}
