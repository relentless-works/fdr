import 'package:fdr/fdr.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class ListDetailNavigator extends StatefulNavigator<Never> {
  ListDetailNavigator();

  @override
  StatefulNavigatorState<ListDetailNavigator, Never> createState() =>
      _ListDetailNavigatorState();
}

class _ListDetailNavigatorState
    extends StatefulNavigatorState<ListDetailNavigator, Never> {
  int? selectedNumber;

  @override
  List<NavEntry<Never>> build() {
    final selectedNumber = this.selectedNumber;

    clear() => setState(() => this.selectedNumber = null);

    return [
      NavPage(
        child: NumberSelectionPage(
          onNumberSelect: (number) =>
              setState(() => this.selectedNumber = number),
        ),
      ),
      if (selectedNumber != null)
        if (selectedNumber == 7)
          DialogPage(
            onPop: clear,
            child: LuckyNumberSevenPage(onTap: clear),
          )
        else
          NavPage(
            onPop: clear,
            child: NumberDetailPage(number: selectedNumber),
          ),
    ];
  }
}

class NumberSelectionPage extends StatelessWidget {
  @visibleForTesting
  const NumberSelectionPage({super.key, required this.onNumberSelect});

  final ValueSetter<int> onNumberSelect;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pick a number')),
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
  const NumberDetailPage({super.key, required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your choice')),
      body: Center(
        child: Text('$number', style: const TextStyle(fontSize: 90)),
      ),
    );
  }
}

class LuckyNumberSevenPage extends StatelessWidget {
  @visibleForTesting
  const LuckyNumberSevenPage({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: const Text('Lucky you!'),
      content: const Text('🥳', style: TextStyle(fontSize: 90)),
      actions: [
        CupertinoDialogAction(onPressed: onTap, child: const Text('Thanks')),
      ],
    );
  }
}
