import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/engine/personal_filter_core.dart';

void main() {
  test('personal filter fit produces a safe LUT and compact recipe', () async {
    final tempDir = Directory.systemTemp.createTempSync('memoria-personal-fit-');
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    final beforePath = '${tempDir.path}/before.png';
    final afterPath = '${tempDir.path}/after.png';
    _writeSyntheticPair(beforePath, afterPath);

    final result = await generateLutFromBeforeAfterPair(
      beforePath,
      afterPath,
      basePath: tempDir.path,
      sampleLimitPerPair: 4000,
    );

    final fitReport = Map<String, dynamic>.from(result['fitReport'] as Map);
    final fitMetrics =
        Map<String, dynamic>.from(fitReport['fitMetrics'] as Map);
    final recipe =
        Map<String, dynamic>.from(result['filterRecipe'] as Map<String, dynamic>);

    expect(result['generatorType'], 'personalized_pair_fit');
    expect(
      result['fallbackReason'],
      anyOf(isNull, 'lut_safety_strength_reduced'),
    );
    expect(result['safetyMetrics']['isSafe'], isTrue);
    expect(fitMetrics['affineRMSE'], lessThan(0.02));
    expect(fitMetrics['lutRMSE'], lessThan(0.02));
    expect(recipe['generatorType'], 'personalized_pair_fit');
    expect(recipe['modelId'], 'affine_plus_residual_lut');
    expect(File(result['lutPath'] as String).existsSync(), isTrue);
    expect(File(result['thumbnailPath'] as String).existsSync(), isTrue);
  });
}

void _writeSyntheticPair(String beforePath, String afterPath) {
  const size = 32;
  final before = img.Image(width: size, height: size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final r = (40 + x * 6 + y * 2).clamp(0, 255);
      final g = (50 + x * 3 + y * 5).clamp(0, 255);
      final b = (60 + x * 2 + y * 4).clamp(0, 255);
      before.setPixelRgb(x, y, r, g, b);
    }
  }

  final after = img.Image.from(before);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final p = before.getPixel(x, y);
      final r = (p.r * 1.05 - p.g * 0.03 + 7).clamp(0, 255).toInt();
      final g = (p.r * 0.02 + p.g * 1.02 + 3).clamp(0, 255).toInt();
      final b = (p.b * 0.94 + p.g * 0.03 + 5).clamp(0, 255).toInt();
      after.setPixelRgb(x, y, r, g, b);
    }
  }

  File(beforePath).writeAsBytesSync(img.encodePng(before));
  File(afterPath).writeAsBytesSync(img.encodePng(after));
}
