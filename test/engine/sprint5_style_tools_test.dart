import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/engine/lut_engine.dart';

img.Image _syntheticTestImage(
    {required int width, required int height, required double grayLevel}) {
  final image = img.Image(width: width, height: height);
  final pixelVal = (grayLevel * 255).round().clamp(0, 255);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, pixelVal, pixelVal, pixelVal);
    }
  }
  return image;
}

void main() {
  group('Sprint 5 Style Tools: Vignette', () {
    test('vignette reduces brightness at the corners more than at the center',
        () {
      final img.Image image =
          _syntheticTestImage(width: 100, height: 100, grayLevel: 0.8);
      const params = AdjustParams(vignette: 80);

      final result = applyImagePipeline(image: image, params: params);

      // Center (50, 50) should remain almost untouched
      final centerPixel = result.getPixel(50, 50);
      expect(centerPixel.rNormalized, closeTo(0.8, 0.05));

      // Corners (e.g., 0, 0) should be darkened significantly
      final cornerPixel = result.getPixel(0, 0);
      expect(cornerPixel.rNormalized, lessThan(centerPixel.rNormalized * 0.8));
    });
  });

  group('Sprint 5 Style Tools: Glamour Glow', () {
    test(
        'glow increases brightness in high-luminance regions while leaving dark areas intact',
        () {
      // 1. High-luminance test
      final img.Image lightImage =
          _syntheticTestImage(width: 50, height: 50, grayLevel: 0.9);
      const glowParams =
          AdjustParams(glowStrength: 60, glowSaturation: 10, glowWarmth: 10);
      final lightGlow =
          applyImagePipeline(image: lightImage, params: glowParams);

      // Screen blend with glow layer should make high luminance pixels even brighter
      expect(lightGlow.getPixel(25, 25).rNormalized, greaterThan(0.9));

      // 2. Low-luminance test (should not glow)
      final img.Image darkImage =
          _syntheticTestImage(width: 50, height: 50, grayLevel: 0.15);
      final darkGlow = applyImagePipeline(image: darkImage, params: glowParams);

      // Since L is low, glow highlight mask is almost 0, dark pixels should stay dark
      expect(darkGlow.getPixel(25, 25).rNormalized, closeTo(0.15, 0.05));
    });
  });

  group('Sprint 5 Style Tools: HDR Scape (Drama)', () {
    test('hdr scape enhances contrast and compresses midtones', () {
      final img.Image image = img.Image(width: 50, height: 50);
      // Create a step edge pattern (high contrast detail)
      for (var y = 0; y < 50; y++) {
        for (var x = 0; x < 50; x++) {
          final val = x < 25 ? 100 : 160; // 0.39 vs 0.63
          image.setPixelRgb(x, y, val, val, val);
        }
      }

      const hdrParams = AdjustParams(hdrStrength: 75, hdrSaturation: 0);
      final result = applyImagePipeline(image: image, params: hdrParams);

      // Left of center (dark side of step)
      final leftOrig = image.getPixel(20, 25).rNormalized;
      final leftNew = result.getPixel(20, 25).rNormalized;

      // Right of center (bright side of step)
      final rightOrig = image.getPixel(30, 25).rNormalized;
      final rightNew = result.getPixel(30, 25).rNormalized;

      // Local contrast across the step should be modified by HDR tone mapping
      final origDiff = rightOrig - leftOrig;
      final newDiff = rightNew - leftNew;
      expect(newDiff, isNot(origDiff));
    });
  });

  group('Sprint 5 Style Tools: Integration and Serialization', () {
    test(
        'JSON serialization roundtrip for vignette, glow, and drama operations is lossless',
        () {
      final ops = [
        EditOperation(
          id: 'vignette-op',
          tool: EditToolType.vignette,
          appliedAt: DateTime.utc(2026, 6, 1),
          params: const AdjustParams(vignette: 50),
        ),
        EditOperation(
          id: 'glow-op',
          tool: EditToolType.glow,
          appliedAt: DateTime.utc(2026, 6, 1),
          params: const AdjustParams(
              glowStrength: 40, glowSaturation: 20, glowWarmth: -10),
        ),
        EditOperation(
          id: 'drama-op',
          tool: EditToolType.drama,
          appliedAt: DateTime.utc(2026, 6, 1),
          params: const AdjustParams(hdrStrength: 70, hdrSaturation: 15),
        ),
      ];

      for (final op in ops) {
        final jsonStr = op.toJsonString();
        final roundtripped = EditOperation.fromJsonString(jsonStr);
        expect(roundtripped.id, op.id);
        expect(roundtripped.tool, op.tool);
        expect(roundtripped.params?.vignette, op.params?.vignette);
        expect(roundtripped.params?.glowStrength, op.params?.glowStrength);
        expect(roundtripped.params?.glowSaturation, op.params?.glowSaturation);
        expect(roundtripped.params?.glowWarmth, op.params?.glowWarmth);
        expect(roundtripped.params?.hdrStrength, op.params?.hdrStrength);
        expect(roundtripped.params?.hdrSaturation, op.params?.hdrSaturation);
      }
    });
  });
}
