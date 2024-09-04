import 'dart:async';

import 'package:fdr/fdr.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FDR Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    return DeclarativeNavigator.managing(
      navigatorFactory: () => ExampleSelectionNavigator(),
    );
  }
}

class ExampleSelectionNavigator
    extends MappedNavigatableSource<DeclarativeNavigatable?> {
  ExampleSelectionNavigator() : super(initialState: null);

  // Manage state, such that any previous value is always cleaned up
  @override
  set state(DeclarativeNavigatable? newState) {
    final state = this.state;
    if (state is DisposableNavigatable) {
      state.dispose();
    }

    super.state = newState;
  }

  @override
  List<DeclarativeNavigatable> build() {
    final state = this.state;

    return [
      ExampleSelectionPage(
        examples: {
          'List Detail': () => ListDetailNavigator(),
          'Dynamic back behavior': () => DynamicPopNavigator(),
          'Stateful Navigator': () => HotReloadableStatefulNavigator(),
          'Overlay Portal': () => OverlayPortalNavigator(),
        },
        onExampleSelect: (exampleFactory) => this.state = exampleFactory(),
      ).page(onPop: null),
      if (state != null) state.poppable(onPop: () => this.state = null)
    ];
  }

  @override
  void dispose() {
    // clean up any potentially created navigators
    state = null;

    super.dispose();
  }
}

class ExampleSelectionPage extends StatelessWidget {
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

class OverlayPortalNavigator extends StatelessNavigator {
  @override
  List<DeclarativeNavigatable> build() {
    return [
      const OverlayTogglePage().page(onPop: null),
    ];
  }
}

class OverlayTogglePage extends StatefulWidget {
  const OverlayTogglePage({super.key});

  @override
  State<OverlayTogglePage> createState() => _OverlayTogglePageState();
}

class _OverlayTogglePageState extends State<OverlayTogglePage> {
  final controller = OverlayPortalController();

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Overlay Portal'),
      ),
      child: SafeArea(
        child: OverlayPortal(
          controller: controller,
          overlayChildBuilder: (context) => Center(
            child: GestureDetector(
              onTap: controller.toggle,
              child: Container(
                width: 300,
                height: 300,
                color: Colors.red.withOpacity(0.8),
              ),
            ),
          ),
          child: Center(
            child: CupertinoButton.filled(
              child: const Text('Show overlay'),
              onPressed: () {
                controller.toggle();
              },
            ),
          ),
        ),
      ),
    );
  }
}

class DynamicPopNavigator extends MappedNavigatableSource<
    (
      bool /* shows child */,
      bool /* can pop */,
    )> {
  DynamicPopNavigator() : super(initialState: (true, false));

  @override
  List<DeclarativeNavigatable> build() {
    final canPop = state.$2;

    return [
      const Placeholder().page(onPop: null),
      if (state.$1)
        PopToggle(
          value: canPop,
          onChange: (v) => state = (true, v),
        ).page(onPop: canPop ? () => state = (false, false) : null),
    ];
  }
}

class PopToggle extends StatelessWidget {
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

class HotReloadableStatefulNavigator extends MappedNavigatableSource<void> {
  HotReloadableStatefulNavigator() : super(initialState: null);

  @override
  List<DeclarativeNavigatable> build() {
    return [
      StatefulNavigatorDemo(initialCount: 100),
    ];
  }
}

class StatefulNavigatorDemo extends StatefulNavigator {
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
