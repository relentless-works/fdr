import 'package:fdr/fdr.dart';
import 'package:fdr_example/src/examples/dynamic_pop_navigator.dart';
import 'package:fdr_example/src/examples/list_detail_navigator.dart';
import 'package:flutter/material.dart';

/// Two tabs behind a persistent bottom bar; each tab keeps its own stack.
class TabShellNavigator extends StatefulNavigator<Never> {
  @override
  StatefulNavigatorState<TabShellNavigator, Never> createState() =>
      _TabShellNavigatorState();
}

class _TabShellNavigatorState
    extends StatefulNavigatorState<TabShellNavigator, Never> {
  int tab = 0;

  @override
  List<DeclarativeNavigatable<Never>> build() {
    return [
      shell(
        active: tab,
        branches: [ListDetailNavigator(), DynamicPopNavigator()],
        builder: (context, branches, active) => Scaffold(
          body: IndexedStack(index: active, children: branches),
          bottomNavigationBar: NavigationBar(
            selectedIndex: active,
            onDestinationSelected: (i) => setState(() => tab = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.format_list_numbered),
                label: 'List detail',
              ),
              NavigationDestination(
                icon: Icon(Icons.swap_horiz),
                label: 'Dynamic pop',
              ),
            ],
          ),
        ),
      ),
    ];
  }
}
