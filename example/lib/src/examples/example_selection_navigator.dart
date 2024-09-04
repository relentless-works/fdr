import 'package:fdr/fdr.dart';
import 'package:fdr_example/src/examples/dynamic_pop_navigator.dart';
import 'package:fdr_example/src/examples/hot_reloadable_stateful_navigator.dart';
import 'package:fdr_example/src/examples/hot_reloadable_stateless_navigator.dart';
import 'package:fdr_example/src/examples/list_detail_navigator.dart';
import 'package:fdr_example/src/examples/overlay_portal_navigator.dart';
import 'package:flutter/cupertino.dart';

class ExampleSelectionNavigator extends StatefulNavigator {
  @override
  StatefulNavigatorState<ExampleSelectionNavigator> createState() =>
      _ExampleSelectionNavigatorState();
}

class _ExampleSelectionNavigatorState
    extends StatefulNavigatorState<ExampleSelectionNavigator> {
  DeclarativeNavigatable? child;

  @override
  List<DeclarativeNavigatable> build() {
    final child = this.child;

    return [
      ExampleSelectionPage(
        examples: {
          'List Detail': () => ListDetailNavigator(),
          'Dynamic back behavior': () => DynamicPopNavigator(),
          'Stateful Navigator': () => HotReloadableStatefulNavigator(),
          'Stateless Navigator': () => HotReloadableStatelessNavigator(),
          'Overlay Portal': () => OverlayPortalNavigator(),
        },
        onExampleSelect: (exampleFactory) => setState(
          () => this.child = exampleFactory(),
        ),
      ).page(onPop: null),
      if (child != null)
        child.poppable(onPop: () => setState(() => this.child = null)),
    ];
  }
}

class ExampleSelectionPage extends StatelessWidget {
  @visibleForTesting
  const ExampleSelectionPage({
    super.key,
    required this.examples,
    required this.onExampleSelect,
  });

  final Map<String, ValueGetter<DeclarativeNavigatable>> examples;

  final ValueSetter<ValueGetter<DeclarativeNavigatable>> onExampleSelect;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Example selection'),
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
                        for (final entry in examples.entries)
                          CupertinoListTile.notched(
                            onTap: () => onExampleSelect(entry.value),
                            trailing: const CupertinoListTileChevron(),
                            title: Text(entry.key),
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
