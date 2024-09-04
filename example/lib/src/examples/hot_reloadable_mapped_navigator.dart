import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';

class HotReloadableMappedNavigator extends StatelessNavigator {
  @override
  List<DeclarativeNavigatable> build() {
    return [
      MappedNavigatorDemo(),
    ];
  }
}

class MappedNavigatorDemo extends MappedNavigatableSource<int> {
  MappedNavigatorDemo() : super(initialState: 0);

  @override
  List<DeclarativeNavigatable> build() {
    return [
      Scaffold(
        appBar: AppBar(
          title: const Text('Stateless Navigator'),
        ),
        body: Center(
          child: Column(
            children: [
              Text('Count: $state'),
              FilledButton(
                onPressed: () {
                  state++;
                },
                child: const Text('Increment'),
              )
            ],
          ),
        ),
      ).page(onPop: null),
    ];
  }
}
