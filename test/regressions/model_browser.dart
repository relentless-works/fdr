import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../routing/example_app.dart';

typedef BrowserEntry = ({String uri, Object? state});

/// A model of the browser's session history. The app's reports are applied
/// the way the engine applies them (replaceState / pushState), and a
/// traversal delivers the entry that really is at the new position, so a
/// shadow history that went wrong shows as a wrong address bar or entry
/// count.
class ModelBrowser implements BrowserHistory {
  ModelBrowser(String initialUrl) : entries = [(uri: initialUrl, state: null)];

  final List<BrowserEntry> entries;
  int index = 0;

  /// The `history.go` calls of the app, and those not yet carried out.
  final deltas = <int>[];
  final pending = <int>[];

  /// `routeInformationUpdated` calls, as (uri, replace).
  final reports = <(String, bool)>[];

  /// The address bar.
  String get bar => entries[index].uri;
  List<String> get urls => [for (final e in entries) e.uri];

  @override
  bool get supportsTraversal => true;

  @override
  void go(int delta) {
    deltas.add(delta);
    pending.add(delta);
  }

  @override
  Object? get currentState => entries[index].state;

  void report(String uri, bool replace, Object? state) {
    reports.add((uri, replace));
    if (replace) {
      entries[index] = (uri: uri, state: state);
    } else {
      entries
        ..removeRange(index + 1, entries.length)
        ..add((uri: uri, state: state));
      index = entries.length - 1;
    }
  }
}

/// The example app in a [ModelBrowser], driven by user actions.
class BrowserSession {
  BrowserSession(this.tester, String initialUrl)
    : browser = ModelBrowser(initialUrl);

  final WidgetTester tester;
  final ModelBrowser browser;
  late FdrRouter<AppRoute> router;

  /// Loads the page at the current entry: the first start, or a reload.
  Future<void> load() async {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.navigation, (call) async {
      if (call.method == 'routeInformationUpdated') {
        final args = call.arguments as Map;
        browser.report(
          args['uri'] as String,
          args['replace'] as bool,
          args['state'],
        );
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.navigation, null);
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue();
    });
    // a new document: what the old one asked for is gone
    browser.pending.clear();
    await tester.pumpWidget(const SizedBox());
    tester.binding.platformDispatcher.defaultRouteNameTestValue = browser.bar;
    router = FdrRouter<AppRoute>(
      root: const AppNavigator(loggedIn: true),
      fromUrl: AppRoute.fromUrl,
      notFound: (url) => NotFoundPage(url: url),
      browserHistory: browser,
      sessionId: 1,
    );
    // the page transitions of a few taps take longer than the browser may
    // take for a traversal
    router.provider.backTimeout = lost;
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
    await tester.pumpAndSettle();
  }

  Future<void> _deliver() async {
    final entry = browser.entries[browser.index];
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(
        MethodCall('pushRouteInformation', {
          'location': entry.uri,
          'state': entry.state,
        }),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  /// The browser carries out the traversals the app asked for. One past
  /// the start of the history does nothing and delivers nothing.
  Future<void> arrive() async {
    while (browser.pending.isNotEmpty) {
      final target = browser.index + browser.pending.removeAt(0);
      if (target < 0 || target >= browser.entries.length) continue;
      browser.index = target;
      await _deliver();
    }
  }

  /// Browser back (-1) or forward (1) by the user.
  Future<void> traverse(int delta) async {
    browser.index += delta;
    await _deliver();
  }

  /// A hash typed into the address bar: a new entry without state.
  Future<void> type(String uri) async {
    browser.entries
      ..removeRange(browser.index + 1, browser.entries.length)
      ..add((uri: uri, state: null));
    browser.index = browser.entries.length - 1;
    await _deliver();
  }

  /// Taps without letting the browser answer: a traversal stays in flight.
  Future<void> tapInFlight(Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> tap(Finder finder) async {
    await tapInFlight(finder);
    await arrive();
  }

  /// What the app shows, the address bar and the browser's entries.
  void expectAt(String app, {required List<String> entries, int? at}) {
    final position = at ?? entries.length - 1;
    expect(router.currentUrl, app, reason: 'app');
    expect(browser.bar, app, reason: 'address bar');
    expect(browser.urls, entries, reason: 'browser entries');
    expect(browser.index, position, reason: 'browser position');
    expect(router.provider.pendingBacks, 0);
    expect(
      (router.provider.shadowIndex, router.provider.shadowHistory.length),
      (position, entries.length),
      reason: 'shadow: ${router.provider.shadowHistory}',
    );
  }
}

/// After this time, a traversal that did not arrive counts as lost.
const lost = Duration(seconds: 10);

final back = find.byType(BackButton);
final open42 = find.byKey(const Key('open-42'));
final item3 = find.byKey(const Key('item-3'));
final tabSettings = find.byKey(const Key('tab-settings'));
final profile = find.byKey(const Key('profile'));
