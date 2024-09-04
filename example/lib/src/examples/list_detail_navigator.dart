import 'package:fdr/fdr.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class ListDetailNavigator extends MappedNavigatableSource<int?> {
  ListDetailNavigator() : super(initialState: null);

  @override
  List<DeclarativeNavigatable> build() {
    final state = this.state;

    return [
      NumberSelectionPage(
        onNumberSelect: (number) => this.state = number,
      ).page(onPop: null),
      if (state != null)
        if (state == 7)
          LuckyNumberSevenPage(
            onTap: () => this.state = null,
          ).popup(onPop: () => this.state = null)
        else
          NumberDetailPage(number: state).page(onPop: () => this.state = null),
    ];
  }
}

class NumberSelectionPage extends StatelessWidget {
  @visibleForTesting
  const NumberSelectionPage({
    super.key,
    required this.onNumberSelect,
  });

  final ValueSetter<int> onNumberSelect;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick a number'),
      ),
      body: ListView.builder(
        itemCount: 1000,
        itemBuilder: (context, index) {
          final n = index + 1;

          return CupertinoListTile(
            title: Text('$n'),
            trailing: const CupertinoListTileChevron(),
            onTap: () => onNumberSelect(n),
          );
        },
      ),
    );
  }
}

class NumberDetailPage extends StatelessWidget {
  @visibleForTesting
  const NumberDetailPage({
    super.key,
    required this.number,
  });

  final int number;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your choice'),
      ),
      body: Center(
        child: Text(
          '$number',
          style: const TextStyle(fontSize: 90),
        ),
      ),
    );
  }
}

class LuckyNumberSevenPage extends StatelessWidget {
  @visibleForTesting
  const LuckyNumberSevenPage({
    super.key,
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Lucky you!'),
        automaticallyImplyLeading: false,
      ),
      child: SafeArea(
        child: SizedBox(
          width: 300,
          child: GestureDetector(
            onTap: onTap,
            child: const Text(
              '🥳',
              style: TextStyle(fontSize: 90),
            ),
          ),
        ),
      ),
    );
  }
}
