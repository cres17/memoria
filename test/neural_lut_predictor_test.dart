import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/ai/models/lut_predictor.dart';

void main() {
  test('bundled color transfer model predicts a 65 cubed LUT', () async {
    const modelPath = 'assets/models/color_transfer.tflite';
    const imagePath = 'test/원본_1.jpg';

    expect(File(modelPath).existsSync(), isTrue);
    expect(File(imagePath).existsSync(), isTrue);

    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    if (Platform.isWindows && flutterRoot != null) {
      final dll = File(
        '$flutterRoot/bin/cache/artifacts/engine/windows-x64/blobs/'
        'libtensorflowlite_c-win.dll',
      );
      if (!dll.existsSync()) {
        // ignore: avoid_print
        print('skipped: local Flutter TFLite DLL not found at ${dll.path}');
        return;
      }
    }

    final predictor = await LutPredictor.fromPath(modelPath);
    final watch = Stopwatch()..start();
    final lut = await predictor.predict(imagePath);
    watch.stop();
    predictor.dispose();

    var minValue = double.infinity;
    var maxValue = double.negativeInfinity;
    var sum = 0.0;
    for (final value in lut) {
      if (value < minValue) minValue = value;
      if (value > maxValue) maxValue = value;
      sum += value;
    }

    // These prints are intentional: the test doubles as a local smoke report.
    // ignore: avoid_print
    print('neural_lut_elapsed_ms=${watch.elapsedMilliseconds}');
    // ignore: avoid_print
    print('neural_lut_min=${minValue.toStringAsFixed(6)}');
    // ignore: avoid_print
    print('neural_lut_max=${maxValue.toStringAsFixed(6)}');
    // ignore: avoid_print
    print('neural_lut_mean=${(sum / lut.length).toStringAsFixed(6)}');

    expect(lut.length, 65 * 65 * 65 * 3);
    expect(minValue, inInclusiveRange(0.0, 1.0));
    expect(maxValue, inInclusiveRange(0.0, 1.0));
    expect(maxValue - minValue, greaterThan(0.05));
  });
}
