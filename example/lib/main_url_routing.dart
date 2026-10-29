// The URL routing demo; best tried in a browser:
//   flutter run -d chrome -t lib/main_url_routing.dart
import 'package:fdr_example/url_routing/shop.dart';
import 'package:flutter/material.dart';

final _router = createShopRouter(ShopApi());

void main() {
  runApp(
    MaterialApp.router(
      title: 'fdr URL routing',
      routerConfig: _router.config,
      restorationScopeId: 'app',
    ),
  );
}
