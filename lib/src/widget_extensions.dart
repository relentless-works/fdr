import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/core.dart';
import 'pages/cupertino_page.dart';
import 'pages/material_page.dart';

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
        return defaultTargetPlatform == TargetPlatform.android
            ? FDRMaterialPage<Object?>(key: key, child: this, canPop: canPop)
            : FDRCupertinoPage<Object?>(key: key, child: this, canPop: canPop);
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
