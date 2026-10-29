import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'core/core.dart';
import 'pages/fdr_page.dart';

/// A shell: one page with persistent chrome around one nested navigator per
/// branch, e.g. tabs behind a bottom navigation bar (see [ShellNavigatable]).
///
/// [key] identifies the shell page in its owner's stack; it must be stable,
/// so that a URL change inside a branch does not replace the shell page.
DeclarativeNavigatable<R> shell<R>({
  required List<DeclarativeNavigatable<R>> branches,
  required int active,
  required ShellBuilder builder,
  VoidCallback? onPop,
  LocalKey key = const ValueKey('fdr:shell'),
}) {
  return ShellNavigatable<R>(
    branches: branches,
    active: active,
    builder: builder,
    page: (body) => body.page<R>(onPop: onPop, key: key),
  );
}

extension DeclarativeNavigatableFromWidget on Widget {
  /// A full-screen page. [route] addresses it in the enclosing navigator's
  /// route type; omit it for pages without a URL. Provide `onPop: null` if
  /// the page should not be poppable.
  DeclarativeNavigatablePage<R> page<R>({
    required VoidCallback? onPop,
    R? route,
    LocalKey? key,
  }) {
    return DeclarativeNavigatablePage<R>(
      builder: ({required canPop, key}) {
        return FDRPage<Object?>(key: key, child: this, canPop: canPop);
      },
      onPop: onPop,
      route: route,
      key: key,
    );
  }

  /// A modal popup. Barrier taps and back go through [onPop] like any pop.
  DeclarativeNavigatablePage<R> popup<R>({
    required VoidCallback? onPop,
    R? route,
    LocalKey? key,
  }) {
    return DeclarativeNavigatablePage<R>(
      builder: ({required canPop, key}) =>
          _PopupPage<Object?>(key: key, child: this, canPop: canPop),
      onPop: onPop,
      route: route,
      key: key,
    );
  }
}

class _PopupPage<T> extends Page<T> {
  const _PopupPage({super.key, required this.child, super.canPop});

  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) {
    return CupertinoModalPopupRoute<T>(
      settings: this,
      barrierDismissible: canPop,
      barrierColor: Colors.transparent,
      builder: (context) => child,
    );
  }
}
