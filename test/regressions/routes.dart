import 'package:fdr/fdr.dart';
import 'package:flutter/material.dart';

sealed class RR extends NavRoute {
  const RR();
  static RR fromUrl(Url url) => switch (url.segments) {
    [] => const RA(),
    ['b'] => const RB(),
    ['c'] => const RC(),
    _ => throw NotFound(url),
  };

  @override
  Url toUrl() => switch (this) {
    RA() => const Url([]),
    RB() => const Url(['b']),
    RC() => const Url(['c']),
  };
}

final class RA extends RR {
  const RA();
}

final class RB extends RR {
  const RB();
}

final class RC extends RR {
  const RC();
}

Widget scaffold(String text, [List<Widget> children = const []]) => Scaffold(
  appBar: AppBar(title: Text(text)),
  body: Column(children: children),
);
