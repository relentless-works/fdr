// Drives the URL routing demo through the real browser history and checks,
// after every step, that the app state, the address bar and the number of
// history entries agree, including across a page reload. Run by
// `tool/browser_probe.sh` in headless Chrome; results are printed to the
// console as `PROBE ...` lines.
// ignore_for_file: avoid_print

import 'dart:async';

import 'package:fdr_example/url_routing/shop.dart';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

final _router = createShopRouter(
  ShopApi(delay: const Duration(milliseconds: 100)),
);
var _failures = 0;

void main() {
  runApp(MaterialApp.router(routerConfig: _router.config));
  unawaited(_run());
}

web.Storage get _storage => web.window.sessionStorage;

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 700));

Future<void> _step(
  String name,
  FutureOr<void> Function() action, {
  required String url,
  required int entries,
}) async {
  await action();
  await _settle();
  final app = _router.delegate.currentUrl;
  final bar = web.window.location.hash;
  final base = int.parse(_storage.getItem('probe.base')!);
  final count = web.window.history.length - base;
  final ok = app == url && bar == '#$url' && count == entries;
  if (!ok) _failures++;
  print(
    'PROBE ${ok ? 'ok  ' : 'FAIL'} ${name.padRight(34)} '
    'app=$app bar=$bar entries=$count (expected $url, $entries)',
  );
}

Future<void> _run() async {
  try {
    if (_storage.getItem('probe.phase') == null) {
      // history entries that existed before the app's first one
      _storage.setItem('probe.base', '${web.window.history.length - 1}');
      _storage.setItem('probe.phase', 'reloaded');
      await _beforeReload();
      _storage.setItem('probe.failures', '$_failures');
      web.window.location.reload();
    } else {
      _failures = int.parse(_storage.getItem('probe.failures') ?? '0');
      await _afterReload();
      print('PROBE DONE $_failures failed');
    }
  } on Object catch (error, stack) {
    print('PROBE ERROR $error\n$stack');
  }
}

Future<void> _beforeReload() async {
  final nav = _router.delegate;
  await _step('start', () {}, url: '/orders', entries: 1);
  await _step(
    'open order 42 (loads)',
    () => nav.navigate(const OrdersTab(OrderAt(42))),
    url: '/orders/42',
    entries: 2,
  );
  await _step(
    'open item 3 (loads)',
    () => nav.navigate(const OrdersTab(OrderAt(42, ItemAt(3)))),
    url: '/orders/42/items/3',
    entries: 3,
  );
  await _step(
    'open reviews',
    () => nav.navigate(const OrdersTab(OrderAt(42, ItemAt(3, ItemReviews())))),
    url: '/orders/42/items/3/reviews',
    entries: 4,
  );
  await _step(
    'state-driven pop is a browser back',
    () => nav.navigate(const OrdersTab(OrderAt(42, ItemAt(3)))),
    url: '/orders/42/items/3',
    entries: 4,
  );
  await _step(
    'system back inside the tab',
    nav.popRoute,
    url: '/orders/42',
    entries: 4,
  );
  await _step(
    'browser forward reloads the item',
    () => web.window.history.forward(),
    url: '/orders/42/items/3',
    entries: 4,
  );
  await _step(
    'browser back',
    () => web.window.history.back(),
    url: '/orders/42',
    entries: 4,
  );
  await _step(
    'open reviews in one go',
    () => nav.navigate(const OrdersTab(OrderAt(42, ItemAt(3, ItemReviews())))),
    url: '/orders/42/items/3/reviews',
    entries: 3,
  );
  await _step(
    'close all levels at once',
    () => nav.navigate(const OrdersTab()),
    url: '/orders',
    entries: 3,
  );
  await _step(
    'browser forward',
    () => web.window.history.forward(),
    url: '/orders/42',
    entries: 3,
  );
}

Future<void> _afterReload() async {
  final nav = _router.delegate;
  await _step('after reload', () {}, url: '/orders/42', entries: 3);
  await _step(
    'back after reload is a browser back',
    () => nav.navigate(const OrdersTab()),
    url: '/orders',
    entries: 3,
  );
  await _step(
    'browser forward after reload',
    () => web.window.history.forward(),
    url: '/orders/42',
    entries: 3,
  );
  await _step(
    'switch tab',
    () => nav.navigate(const SettingsTab(Profile())),
    url: '/settings/profile',
    entries: 3,
  );
  await _step(
    'browser back to the orders tab',
    () => web.window.history.back(),
    url: '/orders/42',
    entries: 3,
  );
  await _step(
    'unknown URL typed into the bar',
    () => web.window.location.hash = '/nope',
    url: '/nope',
    entries: 3,
  );
  await _step(
    'browser back',
    () => web.window.history.back(),
    url: '/orders/42',
    entries: 3,
  );
}
