import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';

class HotReloadableStatelessNavigator extends StatelessNavigator<Never> {
  @override
  List<DeclarativeNavigatable<Never>> build() {
    return [
      StatelessNavigatorDemo(greeting: 'hello, world!'),
    ];
  }
}

class StatelessNavigatorDemo extends StatelessNavigator<Never> {
  @visibleForTesting
  StatelessNavigatorDemo({
    required this.greeting,
  });

  final String greeting;

  @override
  List<DeclarativeNavigatable<Never>> build() {
    return [
      Scaffold(
        appBar: AppBar(
          title: const Text('Stateless Navigator'),
        ),
        body: Center(
          child: Text(greeting),
        ),
      ).page(onPop: null),
    ];
  }
}
