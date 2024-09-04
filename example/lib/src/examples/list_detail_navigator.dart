import 'package:fdr/fdr.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class ListDetailNavigator extends StatefulNavigator {
  ListDetailNavigator();

  @override
  StatefulNavigatorState<ListDetailNavigator> createState() =>
      _ListDetailNavigatorState();
}

class _ListDetailNavigatorState
    extends StatefulNavigatorState<ListDetailNavigator> {
  int? selectedNumber;

  @override
  List<DeclarativeNavigatable> build() {
    final selectedNumber = this.selectedNumber;

    clear() => setState(() => this.selectedNumber = null);

    return [
      NumberSelectionPage(
        onNumberSelect: (number) =>
            setState(() => this.selectedNumber = number),
      ).page(onPop: null),
      if (selectedNumber != null)
        if (selectedNumber == 7)
          LuckyNumberSevenPage(
            onTap: clear,
          ).popup(onPop: clear)
        else
          NumberDetailPage(number: selectedNumber).page(onPop: clear),
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
