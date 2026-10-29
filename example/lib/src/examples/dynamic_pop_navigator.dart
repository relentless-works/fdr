import 'package:fdr/fdr.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class DynamicPopNavigator extends StatefulNavigator<Never> {
  @override
  StatefulNavigatorState<DynamicPopNavigator, Never> createState() =>
      _DynamicPopNavigatorState();
}

class _DynamicPopNavigatorState
    extends StatefulNavigatorState<DynamicPopNavigator, Never> {
  bool showChild = true;
  bool canPop = false;

  @override
  List<NavEntry<Never>> build() {
    return [
      NavPage(
        child: Scaffold(
          appBar: AppBar(title: const Text('Dynamic pop parent')),
          body: Center(
            child: FilledButton(
              onPressed: () => setState(() => showChild = true),
              child: const Text('Open child page'),
            ),
          ),
        ),
      ),
      if (showChild)
        NavPage(
          onPop: canPop ? () => setState(() => showChild = false) : null,
          child: PopToggle(
            value: canPop,
            onChange: (v) => setState(() => canPop = v),
          ),
        ),
    ];
  }
}

class PopToggle extends StatelessWidget {
  @visibleForTesting
  const PopToggle({super.key, required this.value, required this.onChange});

  final bool value;

  final ValueSetter<bool> onChange;

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).platform == TargetPlatform.android) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dynamic pop')),
        body: Switch(value: value, onChanged: onChange),
      );
    }

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Dynamic Pop')),
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
