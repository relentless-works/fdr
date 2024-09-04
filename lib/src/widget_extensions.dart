import 'package:fdr/fdr.dart';
import 'package:fdr/src/pages/cupertino_page.dart';
import 'package:fdr/src/pages/material_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

extension DeclarativeNavigatableFromWidget on Widget {
  DeclarativeNavigatablePage page({
    /// Provide `null` if the page should not be poppable
    required VoidCallback? onPop,
  }) {
    return DeclarativeNavigatablePage(
      builder: (onPop) => defaultTargetPlatform == TargetPlatform.android
          ? FDRMaterialPage(
              child: this,
              canPop: onPop != null,
              onPopInvoked: (didPop, _) {
                if (didPop) {
                  // When the route was popped, it had to be pop-able (`canPop = true`),
                  // such that there is a callback to update the state to reflect its absence
                  onPop!();
                }
              },
            )
          : FDRCupertinoPage(
              child: this,
              canPop: onPop != null,
              onPopInvoked: (didPop, _) {
                if (didPop) {
                  // When the route was popped, it had to be pop-able (`canPop = true`),
                  // such that there is a callback to update the state to reflect its absence
                  onPop!();
                }
              },
            ),
      onPop: onPop,
    );
  }

  DeclarativeNavigatablePage popup({
    /// Provide `null` if the model should not be poppable
    required VoidCallback? onPop,
  }) {
    return DeclarativeNavigatablePage(
      builder: (onPop) => _CupertinoModalPopupPage(child: this),
      onPop: onPop,
    );
  }
}

class _CupertinoModalPopupPage<T> extends Page<T> {
  const _CupertinoModalPopupPage({
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
    required this.child,
  });

  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) {
    return CupertinoModalPopupRoute(
      settings: this,
      barrierDismissible: true, // TODO(tp): Adapt
      barrierColor: Colors.transparent,
      builder: (context) => child,
    );
  }
}
