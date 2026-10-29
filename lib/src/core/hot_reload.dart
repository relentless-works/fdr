part of 'core.dart';

final class _HotReloadNotifier extends ChangeNotifier {
  void trigger() => notifyListeners();
}

/// Process-wide hot-reload signal every navigator state rebuilds on.
abstract final class FdrHotReload {
  static final _notifier = _HotReloadNotifier();

  static Listenable get listenable => _notifier;

  static void trigger() => _notifier.trigger();
}
