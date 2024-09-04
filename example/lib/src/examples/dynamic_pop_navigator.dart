import 'package:fdr/fdr.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class DynamicPopNavigator extends StatefulNavigator {
  @override
  StatefulNavigatorState<DynamicPopNavigator> createState() =>
      _DynamicPopNavigatorState();
}

class _DynamicPopNavigatorState
    extends StatefulNavigatorState<DynamicPopNavigator> {
  bool showChild = true;
  bool canPop = false;

  @override
  List<DeclarativeNavigatable> build() {
    return [
      Scaffold(
        appBar: AppBar(
          title: const Text('Dynamic pop parent'),
        ),
        body: Center(
          child: FilledButton(
            onPressed: () => setState(() => showChild = true),
            child: const Text('Open child page'),
          ),
        ),
      ).page(onPop: null),
      if (showChild)
        PopToggle(
          value: canPop,
          onChange: (v) => setState(() => canPop = v),
        ).page(onPop: canPop ? () => setState(() => showChild = false) : null),
    ];
  }
}

class PopToggle extends StatelessWidget {
  @visibleForTesting
  const PopToggle({
    super.key,
    required this.value,
    required this.onChange,
  });

  final bool value;

  final ValueSetter<bool> onChange;

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).platform == TargetPlatform.android) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Dynamic pop'),
        ),
        body: Switch(
          value: value,
          onChanged: onChange,
        ),
      );
    }

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Dynamic Pop'),
      ),
      child: Container(
        color: CupertinoColors.systemGroupedBackground,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20.0),
                    child: CupertinoFormSection.insetGrouped(
                      children: [
                        CupertinoListTile.notched(
                          trailing: CupertinoSwitch(
                            value: value,
                            onChanged: onChange,
                          ),
                          title: const Text('Can pop'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
