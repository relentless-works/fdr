import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';

import '../file_comparator_with_threshold.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  return GoldenToolkit.runWithConfiguration(
    () async {
      final testUrl = (goldenFileComparator as LocalFileComparator).basedir;

      goldenFileComparator = LocalFileComparatorWithThreshold(
        Uri.parse('$testUrl/test.dart'),
        Platform.environment['IS_CI'] == 'true' ? 0.5 / 1000 : 0.0,
      );

      await loadAppFonts();
      WidgetController.hitTestWarningShouldBeFatal = true;
      EditableText.debugDeterministicCursor = true;

      await testMain();
    },
    config: GoldenToolkitConfiguration(),
  );
}
