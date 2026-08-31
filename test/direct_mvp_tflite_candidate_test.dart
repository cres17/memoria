import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/ai/ai_manager.dart';
import 'package:memoria/ai/models/lut_predictor.dart';
import 'package:memoria/engine/lut_engine.dart';

const candidateModelPath = String.fromEnvironment(
  'DIRECT_MVP_TFLITE_PATH',
  defaultValue: 'assets/models/direct_mvp_color_transfer_fp16.tflite',
);

void main() {
  test('direct MVP TFLite candidate loads through the app predictor contract',
      () async {
    const modelPath = candidateModelPath;
    const imagePath = 'test/원본_1.jpg';
    expect(File(modelPath).existsSync(), isTrue,
        reason: 'the bundled Direct MVP model must be present');
    expect(File(imagePath).existsSync(), isTrue);

    final predictor = await LutPredictor.fromPath(modelPath);
    final watch = Stopwatch()..start();
    final lut = await predictor.predict(imagePath);
    watch.stop();
    predictor.dispose();

    var minimum = double.infinity;
    var maximum = double.negativeInfinity;
    for (final value in lut) {
      if (value < minimum) minimum = value;
      if (value > maximum) maximum = value;
    }

    // Keep a locally visible integration measurement without making a mobile
    // device-latency claim from a desktop Flutter test.
    // ignore: avoid_print
    print('direct_mvp_flutter_wrapper_elapsed_ms=${watch.elapsedMilliseconds}');
    expect(lut.length, 65 * 65 * 65 * 3);
    expect(minimum, inInclusiveRange(0.0, 1.0));
    expect(maximum, inInclusiveRange(0.0, 1.0));
    expect(maximum - minimum, greaterThan(0.05));
  });

  test('single reference uses Direct MVP and persists deterministic recipe',
      () async {
    const modelPath = candidateModelPath;
    const imagePath = 'test/원본_1.jpg';
    final outputDirectory =
        await Directory.systemTemp.createTemp('memoria-direct-mvp-e2e-');
    AiManager.instance.useLocalModelForTesting(
      kModelColorTransfer,
      modelPath,
    );

    try {
      final first = await generateLutFromStyle(
        const [imagePath],
        basePath: outputDirectory.path,
      );
      final second = await generateLutFromStyle(
        const [imagePath],
        basePath: outputDirectory.path,
      );
      final recipe = Map<String, dynamic>.from(first['filterRecipe'] as Map);
      final firstBytes = await File(first['lutPath'] as String).readAsBytes();
      final secondBytes = await File(second['lutPath'] as String).readAsBytes();

      expect(first['generatorType'], 'neural');
      expect(recipe['generatorType'], 'neural');
      expect(recipe['modelId'], kColorTransferModelId);
      expect(recipe['modelVersion'], kColorTransferModelVersion);
      expect(secondBytes, orderedEquals(firstBytes));
    } finally {
      LutPredictor.resetForTesting();
      AiManager.instance.clearLocalModelForTesting(kModelColorTransfer);
      if (await outputDirectory.exists()) {
        await outputDirectory.delete(recursive: true);
      }
    }
  });
}
