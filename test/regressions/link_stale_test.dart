import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// root owns ?f=, the child the path
final class HomeAt extends NavRoute {
  const HomeAt(this.child, {this.f});
  final CR child;
  final String? f;

  static HomeAt fromUrl(Url url) => HomeAt(CR.fromUrl(url), f: url['f']);

  @override
  Url toUrl() =>
      Url(
        [],
        query: {
          if (f case final f?) 'f': [f],
        },
      ) +
      child.toUrl();
}

sealed class CR extends NavRoute {
  const CR();
  static CR fromUrl(Url url) => switch (url.segments) {
    [] => const C0(),
    ['x'] => const CX(),
    _ => throw NotFound(url),
  };

  @override
  Url toUrl() => switch (this) {
    C0() => const Url([]),
    CX() => const Url(['x']),
  };
}

final class C0 extends CR {
  const C0();
}

final class CX extends CR {
  const CX();
}

class Root extends StatefulNavigator<HomeAt> {
  const Root();
  @override
  RootState createState() => RootState();
}

class RootState extends StatefulNavigatorState<Root, HomeAt> {
  static late RootState latest;
  String? f;
  CR? child;

  @override
  void initState() {
    super.initState();
    latest = this;
  }

  @override
  void applyRoute(HomeAt route) {
    f = route.f;
    child = route.child;
  }

  @override
  List<NavEntry<HomeAt>> build() {
    final f = this.f;
    return [
      NestedNavigator(
        at: (route) => HomeAt(route, f: f),
        route: child,
        child: const Child(),
      ),
    ];
  }
}

class Child extends StatefulNavigator<CR> {
  const Child();
  @override
  ChildState createState() => ChildState();
}

class ChildState extends StatefulNavigatorState<Child, CR> {
  bool x = false;

  @override
  void applyRoute(CR route) => x = route is CX;

  @override
  List<NavEntry<CR>> build() => [
    const NavPage(
      route: C0(),
      child: Scaffold(body: Links()),
    ),
    if (x)
      NavPage(
        route: const CX(),
        onPop: () => setState(() => x = false),
        child: const Scaffold(body: Text('X')),
      ),
  ];
}

class Links extends StatelessWidget {
  const Links({super.key});
  @override
  Widget build(BuildContext context) => RouteLink(
    route: const CX(),
    builder: (context, open) =>
        TextButton(onPressed: open, child: const Text('go')),
  );
}

void main() {
  testWidgets('a link in a const subtree follows a changed parent lift', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/?f=a';
    final router = FdrRouter<HomeAt>(
      root: const Root(),
      fromUrl: HomeAt.fromUrl,
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config));
    await tester.pump();
    expect(router.currentUrl, '/?f=a');

    final root = RootState.latest;
    root.setState(() => root.f = 'b');
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/?f=b');

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/x?f=b');
    expect(root.f, 'b');
  });
}
