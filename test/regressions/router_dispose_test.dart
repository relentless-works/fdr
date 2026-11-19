import 'package:fdr/fdr.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'routes.dart';

class Root extends StatefulNavigator<RR> {
  const Root();
  @override
  RootState createState() => RootState();
}

class RootState extends StatefulNavigatorState<Root, RR> {
  static int inits = 0;
  static int disposes = 0;
  RR shown = const RA();

  @override
  void initState() {
    super.initState();
    inits++;
  }

  @override
  void applyRoute(RR route) => shown = route;

  @override
  List<NavEntry<RR>> build() => [
    NavPage(route: const RA(), child: scaffold('A')),
    if (shown is RB)
      NavPage(
        route: const RB(),
        onPop: () => setState(() => shown = const RA()),
        child: scaffold('B'),
      ),
  ];

  @override
  void dispose() {
    disposes++;
    super.dispose();
  }
}

// debug builds report a use after dispose (the delegate's ChangeNotifier
// check); in no build mode may a navigator state come back
bool reported(VoidCallback use) {
  try {
    use();
  } on FlutterError {
    return true;
  }
  return false;
}

void main() {
  setUp(() {
    RootState.inits = 0;
    RootState.disposes = 0;
  });

  testWidgets('open() after dispose() creates no navigator state', (
    tester,
  ) async {
    final router = FdrRouter<RR>(
      root: const Root(),
      fromUrl: RR.fromUrl,
      initialRouteInformation: RouteInformation(uri: Uri.parse('/')),
    );
    router.dispose();
    expect((RootState.inits, RootState.disposes), (1, 1));

    // e.g. a late push-notification handler after logout
    expect(reported(() => router.open(const RB())), kDebugMode);
    expect((RootState.inits, RootState.disposes), (1, 1));
  });

  testWidgets('a route from the platform after dispose() creates none', (
    tester,
  ) async {
    final router = FdrRouter<RR>(
      root: const Root(),
      fromUrl: RR.fromUrl,
      initialRouteInformation: RouteInformation(uri: Uri.parse('/')),
    );
    router.dispose();

    expect(
      reported(
        () => router.delegate.setNewRoutePath(const RouteSnapshot(RB())),
      ),
      kDebugMode,
    );
    expect((RootState.inits, RootState.disposes), (1, 1));
  });
}
