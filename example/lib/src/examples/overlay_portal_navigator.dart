import 'package:fdr/fdr.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class OverlayPortalNavigator extends StatelessNavigator {
  @override
  List<DeclarativeNavigatable> build() {
    return [
      const OverlayTogglePage().page(onPop: null),
    ];
  }
}

class OverlayTogglePage extends StatefulWidget {
  @visibleForTesting
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
