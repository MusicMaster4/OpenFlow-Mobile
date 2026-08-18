import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  goldenFileComparator = _CrossPlatformGoldenComparator(
    Uri.file(
      '${Directory.current.path}${Platform.pathSeparator}test'
      '${Platform.pathSeparator}flutter_test_config.dart',
    ),
    precisionTolerance: 0.006,
  );
  await testMain();
}

class _CrossPlatformGoldenComparator extends LocalFileComparator {
  _CrossPlatformGoldenComparator(
    super.testFile, {
    required double precisionTolerance,
  }) : assert(
         precisionTolerance >= 0 && precisionTolerance <= 1,
         'precisionTolerance must be between 0 and 1',
       ),
       _precisionTolerance = precisionTolerance;

  // Linux and Windows rasterize the same bundled Material icons and system
  // fonts with a tiny amount of antialiasing drift. Semantic widget assertions
  // still protect the layout; this only absorbs a sub-percent pixel variance.
  final double _precisionTolerance;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= _precisionTolerance) {
      result.dispose();
      return true;
    }

    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
