import 'package:fdr/fdr.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// "Per tab: each tab gets its own HeroController, and inactive tabs are
// muted with TickerMode" (doc section 8), and the index must name a tab.

class App extends StatefulNavigator<Never> {
  const App();
  @override
  AppState createState() => AppState();
}

class AppState extends StatefulNavigatorState<App, Never> {
  static late AppState latest;
  int tab = 0;
  bool detail = false;

  @override
  void initState() {
    super.initState();
    latest = this;
  }

  @override
  List<NavEntry<Never>> build() {
    // the builder shows the index this TabsPage takes, not a later one
    final index = tab;
    return [
      TabsPage(
        index: index,
        tabs: [
          Branch(
            name: 't0',
            detail: detail,
            onPop: () => setState(() => detail = false),
          ),
          Branch(name: 't1', detail: false, onPop: () {}),
        ],
        builder: (context, tabs) => IndexedStack(index: index, children: tabs),
      ),
    ];
  }
}

class Branch extends StatelessNavigator<Never> {
  const Branch({required this.name, required this.detail, required this.onPop});
  final String name;
  final bool detail;
  final VoidCallback onPop;

  @override
  List<NavEntry<Never>> build() => [
    NavPage(
      child: Material(
        child: Column(
          children: [
            Ticking(name),
            Hero(
              tag: 'hero',
              child: SizedBox(key: Key('$name small'), width: 20, height: 20),
            ),
          ],
        ),
      ),
    ),
    if (detail)
      NavPage(
        onPop: onPop,
        child: Align(
          alignment: Alignment.bottomRight,
          child: Hero(
            tag: 'hero',
            child: SizedBox(key: Key('$name large'), width: 200, height: 200),
          ),
        ),
      ),
  ];
}

/// Counts the frames its ticker sees.
class Ticking extends StatefulWidget {
  const Ticking(this.name, {super.key});
  final String name;

  static final ticks = <String, int>{};

  @override
  State<Ticking> createState() => _TickingState();
}

class _TickingState extends State<Ticking> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    Ticking.ticks[widget.name] = 0;
    _ticker = createTicker(
      (_) => Ticking.ticks.update(widget.name, (n) => n + 1),
    )..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(widget.name);
}

Finder tabNavigator(String name) => find.ancestor(
  of: find.text(name, skipOffstage: false),
  matching: find.byType(Navigator, skipOffstage: false),
);

void main() {
  testWidgets('inactive tabs are muted', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DeclarativeNavigator(navigator: App())),
    );
    // the frames each tab's ticker sees in the next five frames
    Future<Map<String, int>> ticks() async {
      final before = {...Ticking.ticks};
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      return {
        for (final MapEntry(:key, :value) in Ticking.ticks.entries)
          key: value - before[key]!,
      };
    }

    expect(await ticks(), {'t0': 5, 't1': 0});

    AppState.latest.setState(() => AppState.latest.tab = 1);
    await tester.pump();
    expect(await ticks(), {'t0': 0, 't1': 5});
  });

  testWidgets('each tab has a HeroController of its own', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DeclarativeNavigator(navigator: App())),
    );
    final controllers = [
      for (final name in ['t0', 't1'])
        HeroControllerScope.maybeOf(tester.element(tabNavigator(name).first)),
    ];
    expect(controllers, everyElement(isNotNull));
    expect(controllers.first, isNot(same(controllers.last)));

    // so a hero flies between the pages of a tab
    AppState.latest.setState(() => AppState.latest.detail = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // the hero on the page below is hidden while its copy is in flight
    expect(find.byKey(const Key('t0 small')), findsNothing);
    final size = tester.getSize(find.byKey(const Key('t0 large')));
    expect(size.width, inExclusiveRange(20, 200));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getSize(find.byKey(const Key('t0 large'))).width, 200);
  });

  testWidgets('an index that names no tab is an error', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DeclarativeNavigator(navigator: App())),
    );
    final state = AppState.latest;
    expect(
      () => state.setState(() => state.tab = 2),
      throwsA(
        isA<AssertionError>().having(
          (e) => e.message,
          'message',
          'tab index 2 out of range',
        ),
      ),
    );
    // the tabs stay as they were
    await tester.pump();
    expect(find.text('t0'), findsOneWidget);
  });
}
