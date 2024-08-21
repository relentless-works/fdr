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

  @override
  List<DeclarativeNavigatable> build() {
    final state = this.state;

    return [
      ExampleSelectionPage(
        examples: {
          'List Detail': () => ListDetailNavigator(),
          'Dynamic back behavior': () => DynamicPopNavigator(),
        },
        // TODO(tp): Dispose previous if needed
        onExampleSelect: (exampleFactory) {
          final state = this.state;
          if (state is MappedNavigatableSource) {
            // TODO: Move `dispose` interface up, so we don't have to handle just the child-class here
            state.dispose();
          }

          this.state = exampleFactory();
        },
      ).page(onPop: null),
      if (state != null)
        if (state is NavigatableSource)
          // Use pipe type trick for type preservation? (not extension, but rather on class)
          state.poppable(onPop: () {
            if (state is MappedNavigatableSource) {
              state.dispose();
            }

            this.state = null;
          })
        else
          state,
    ];
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
