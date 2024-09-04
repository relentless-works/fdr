import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';

class HotReloadableStatelessNavigator extends StatelessNavigator {
  @override
  List<DeclarativeNavigatable> build() {
    return [
      StatelessNavigatorDemo(greeting: 'hello, world!'),
    ];
  }
}

class StatelessNavigatorDemo extends StatelessNavigator {
  @visibleForTesting
  StatelessNavigatorDemo({
    required this.greeting,
  });

  final String greeting;

  @override
  List<DeclarativeNavigatable> build() {
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
