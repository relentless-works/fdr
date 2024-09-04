import 'dart:async';

import 'package:fdr/fdr.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class HotReloadableNavigator extends StatelessNavigator {
  @override
  List<DeclarativeNavigatable> build() {
    return [
      StatefulNavigatorDemo(initialCount: 100),
    ];
  }
}

class StatefulNavigatorDemo extends StatefulNavigator {
  @visibleForTesting
  StatefulNavigatorDemo({
    required this.initialCount,
  });

  final int initialCount;

  @override
  StatefulNavigatorState<StatefulNavigatorDemo> createState() =>
      _StatefulNavigatorDemoState();
}

class _StatefulNavigatorDemoState
    extends StatefulNavigatorState<StatefulNavigatorDemo> {
  late final Timer timer;

  late int ticks;

  @override
  void initState() {
    super.initState();

    ticks = navigator.initialCount;

    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        ticks++;
      });
    });
  }

  @override
  void didUpdateNavigator(covariant StatefulNavigatorDemo oldNavigator) {
    super.didUpdateNavigator(oldNavigator);

    if (navigator.initialCount != oldNavigator.initialCount) {
      ticks = navigator.initialCount;
      // for the best behavior, we would also have to reset the timer here
    }
  }

  @override
  List<DeclarativeNavigatable> build() {
    return [
      CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(
          middle: Text('Ticks'), // TODO(tp): Check hot reload on change
        ),
        child: SafeArea(
          child: Scaffold(
            body: Center(
              child: Text(
                '$ticks',
                style: const TextStyle(
                  fontSize: 90,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ).page(onPop: null),
    ];
  }

  @override
  void dispose() {
    timer.cancel();

    super.dispose();
  }
}
